"""Gestionnaire temps réel Socket.IO (remplace tous les StreamBuilder Firestore)."""

from flask import current_app, request
from flask_jwt_extended import decode_token
from flask_socketio import emit, join_room, leave_room
from sqlalchemy import or_

from app.extensions import db, socketio
from app.models import ACTIVE_RIDE_STATUSES, Driver, Ride, RideMessage, TokenBlocklist, User
from app.models.user import utcnow
from app.tools.geo import clean_position
from app.tools.realtime import emit_driver_location, emit_to_passengers_map, emit_to_ride, emit_to_rooms

# Mapping sid -> {user_id, driver_id, role}
_CONNECTED_SESSIONS: dict[str, dict] = {}


def _authenticate_socket(auth_payload) -> User | None:
    token = None
    if isinstance(auth_payload, dict):
        token = auth_payload.get("token")
    # Pas de jeton dans l'URL : il finirait dans les journaux des proxys.
    if not token:
        header = request.headers.get("Authorization", "")
        if header.lower().startswith("bearer "):
            token = header.split(None, 1)[1]
    if not token:
        return None
    if token.lower().startswith("bearer "):
        token = token.split(None, 1)[1]

    try:
        decoded = decode_token(token)
    except Exception:
        return None
    if decoded.get("type") != "access":
        return None  # un jeton de rafraîchissement n'ouvre pas de socket

    jti = decoded.get("jti")
    if jti and db.session.query(TokenBlocklist.id).filter_by(jti=jti).first() is not None:
        return None

    user_id = decoded.get("sub")
    if not user_id:
        return None
    user = db.session.get(User, user_id)
    if not user or not user.is_active:
        return None
    return user


def on_connect(auth=None):
    user = _authenticate_socket(auth)
    if not user:
        return False  # Rejette la connexion WebSocket non authentifiée

    driver = user.driver_profile
    _CONNECTED_SESSIONS[request.sid] = {
        "user_id": user.id,
        "driver_id": driver.id if driver else None,
        "role": user.role,
    }

    join_room(f"user:{user.id}")
    join_room("passengers_map")
    if user.role == "admin":
        join_room("admins")  # carte du back-office : toutes les positions

    if driver:
        join_room(f"driver:{driver.id}")
        if _driver_may_receive_rides(driver):
            driver.last_location_at = utcnow()
            join_room("online_drivers")
            join_room(f"online_drivers:{driver.vehicle_type}")
            db.session.commit()

    conditions = [Ride.client_id == user.id]
    if driver:
        conditions.append(Ride.driver_id == driver.id)
    active_rides = Ride.query.filter(
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES)),
        or_(*conditions),
    ).all()
    for ride in active_rides:
        join_room(f"ride:{ride.id}")

    emit(
        "connected",
        {
            "userId": user.id,
            "driverId": driver.id if driver else None,
            "rooms": [
                f"user:{user.id}",
                *[f"ride:{ride.id}" for ride in active_rides],
            ],
            "activeRideIds": [ride.id for ride in active_rides],
        },
    )


def _driver_may_receive_rides(driver: Driver) -> bool:
    if not driver.is_available or driver.is_wallet_blocked:
        return False
    if current_app.config.get("REQUIRE_DRIVER_VERIFICATION"):
        return driver.verification_status == "approved"
    return True


def on_disconnect():
    session = _CONNECTED_SESSIONS.pop(request.sid, None)
    driver_id = session.get("driver_id") if session else None
    if not driver_id:
        return
    driver = db.session.get(Driver, driver_id)
    if driver and driver.is_available:
        driver.last_location_at = utcnow()
        db.session.commit()


def disconnect_user_sessions(user_id: str) -> None:
    for sid, session in list(_CONNECTED_SESSIONS.items()):
        if session["user_id"] != user_id:
            continue
        _CONNECTED_SESSIONS.pop(sid, None)
        socketio.server.disconnect(sid, namespace="/")


def _user_sids(user_id: str) -> list[str]:
    return [sid for sid, s in list(_CONNECTED_SESSIONS.items()) if s["user_id"] == user_id]


def add_user_to_room(user_id: str | None, room: str) -> None:
    """Abonne côté serveur toutes les connexions Socket.IO d'un utilisateur à une room.

    Utilisé quand l'état change via une route REST (course créée, offre acceptée…)
    afin que le client reçoive les événements sans devoir se réabonner lui-même.
    """
    if not user_id:
        return
    for sid in _user_sids(user_id):
        try:
            socketio.server.enter_room(sid, room, namespace="/")
        except Exception:  # pragma: no cover - session fermée entre-temps
            _CONNECTED_SESSIONS.pop(sid, None)


def sync_driver_rooms(driver: Driver | None) -> None:
    """Aligne les rooms Socket.IO du chauffeur sur son état (profil, en ligne, véhicule)."""
    if driver is None:
        return
    vehicle_rooms = [f"online_drivers:{vt}" for vt in ("voiture", "moto", "confort")]
    for sid in _user_sids(driver.user_id):
        _CONNECTED_SESSIONS[sid]["driver_id"] = driver.id
        try:
            socketio.server.enter_room(sid, f"driver:{driver.id}", namespace="/")
            for room in ["online_drivers", *vehicle_rooms]:
                socketio.server.leave_room(sid, room, namespace="/")
            if _driver_may_receive_rides(driver):
                socketio.server.enter_room(sid, "online_drivers", namespace="/")
                socketio.server.enter_room(
                    sid, f"online_drivers:{driver.vehicle_type}", namespace="/"
                )
        except Exception:  # pragma: no cover - session fermée entre-temps
            _CONNECTED_SESSIONS.pop(sid, None)


def on_ping(_data=None):
    session = _CONNECTED_SESSIONS.get(request.sid)
    if session and session["driver_id"]:
        driver = db.session.get(Driver, session["driver_id"])
        if driver and driver.is_available:
            driver.last_location_at = utcnow()
            db.session.commit()
    emit("pong", {"timestamp": utcnow().isoformat()})


def on_join_ride(data):
    session = _CONNECTED_SESSIONS.get(request.sid)
    if not session:
        return
    ride_id = (data or {}).get("rideId")
    if not ride_id:
        return
    ride = db.session.get(Ride, ride_id)
    if not ride:
        emit("error", {"code": "RIDE_NOT_FOUND", "message": "Course introuvable."})
        return

    # Salle réservée au passager et au chauffeur attribué (chat, position,
    # paiement) : les chauffeurs candidats n'y entrent pas.
    is_allowed = ride.client_id == session["user_id"] or (
        session["driver_id"] and ride.driver_id == session["driver_id"]
    )
    if not is_allowed:
        emit("error", {"code": "FORBIDDEN", "message": "Accès course refusé."})
        return

    join_room(f"ride:{ride.id}")
    emit("ride:joined", {"rideId": ride.id, "status": ride.status})


def on_leave_ride(data):
    ride_id = (data or {}).get("rideId")
    if ride_id:
        leave_room(f"ride:{ride_id}")


def on_driver_go_online(data=None):
    session = _CONNECTED_SESSIONS.get(request.sid)
    if not session or not session["driver_id"]:
        emit("error", {"code": "DRIVER_NOT_REGISTERED", "message": "Chauffeur non enregistré."})
        return

    driver = db.session.get(Driver, session["driver_id"])
    if not driver:
        return
    if driver.is_wallet_blocked or float(driver.wallet_balance or 0) < 0:
        emit(
            "error",
            {
                "code": "WALLET_BLOCKED",
                "message": "Solde insuffisant. Rechargez votre portefeuille.",
            },
        )
        return
    if (
        current_app.config.get("REQUIRE_DRIVER_VERIFICATION")
        and driver.verification_status != "approved"
    ):
        emit(
            "error",
            {
                "code": "DRIVER_NOT_VERIFIED",
                "message": "Vos documents doivent être vérifiés avant de passer en ligne.",
            },
        )
        return

    payload = data or {}
    position = clean_position(payload.get("latitude"), payload.get("longitude"), payload.get("heading"))
    if position:
        driver.latitude, driver.longitude = position[0], position[1]
        if position[2] is not None:
            driver.heading = position[2]

    driver.last_location_at = utcnow()
    driver.is_available = True
    db.session.commit()

    join_room("online_drivers")
    join_room(f"online_drivers:{driver.vehicle_type}")

    event_payload = {
        "driverId": driver.id,
        "isAvailable": True,
        "vehicleType": driver.vehicle_type,
        "latitude": driver.latitude,
        "longitude": driver.longitude,
        "heading": driver.heading,
    }
    emit("driver:online_ack", event_payload)
    emit_to_passengers_map("driver:availability_changed", event_payload)


def on_driver_go_offline(_data=None):
    session = _CONNECTED_SESSIONS.get(request.sid)
    if not session or not session["driver_id"]:
        return
    driver = db.session.get(Driver, session["driver_id"])
    if not driver:
        return

    driver.is_available = False
    db.session.commit()
    leave_room("online_drivers")
    leave_room(f"online_drivers:{driver.vehicle_type}")

    event_payload = {
        "driverId": driver.id,
        "isAvailable": False,
        "vehicleType": driver.vehicle_type,
    }
    emit("driver:offline_ack", event_payload)
    emit_to_passengers_map("driver:availability_changed", event_payload)


def on_driver_location_update(data):
    session = _CONNECTED_SESSIONS.get(request.sid)
    if not session or not session["driver_id"]:
        return
    payload = data or {}
    lat = payload.get("latitude")
    lng = payload.get("longitude")
    if lat is None or lng is None:
        return

    driver = db.session.get(Driver, session["driver_id"])
    if not driver:
        return

    position = clean_position(lat, lng, payload.get("heading"))
    if not position:
        return
    driver.latitude, driver.longitude = position[0], position[1]
    if position[2] is not None:
        driver.heading = position[2]
    driver.last_location_at = utcnow()
    db.session.commit()

    loc_payload = {
        "driverId": driver.id,
        "vehicleType": driver.vehicle_type,
        "latitude": driver.latitude,
        "longitude": driver.longitude,
        "heading": driver.heading,
        "timestamp": driver.last_location_at.isoformat(),
    }
    emit_driver_location(loc_payload, driver)

    ride_id = payload.get("rideId")
    if ride_id:
        ride = db.session.get(Ride, ride_id)
        if ride and ride.driver_id == driver.id and ride.status in ACTIVE_RIDE_STATUSES:
            emit_to_ride(ride.id, "ride:driver_location", {"rideId": ride.id, **loc_payload})
    else:
        active_ride = Ride.query.filter(
            Ride.driver_id == driver.id,
            Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
        ).first()
        if active_ride:
            emit_to_ride(
                active_ride.id,
                "ride:driver_location",
                {"rideId": active_ride.id, **loc_payload},
            )


def on_ride_send_message(data):
    session = _CONNECTED_SESSIONS.get(request.sid)
    if not session:
        return
    payload = data or {}
    ride_id = payload.get("rideId")
    content = str(payload.get("content") or "").strip()
    if not ride_id or not content:
        return

    ride = db.session.get(Ride, ride_id)
    if not ride:
        return
    if ride.client_id == session["user_id"]:
        sender_role = "passenger"
        recipient_user_id = ride.driver.user_id if ride.driver else None
    elif session["driver_id"] and ride.driver_id == session["driver_id"]:
        sender_role = "driver"
        recipient_user_id = ride.client_id
    else:
        return

    msg = RideMessage(
        ride_id=ride.id,
        sender_user_id=session["user_id"],
        sender_role=sender_role,
        content=content[:2000],
    )
    db.session.add(msg)
    db.session.commit()

    msg_dict = msg.to_dict()
    emit_to_rooms("ride:message", msg_dict, ride_id=ride.id, user_ids=[recipient_user_id])


def register_socketio_handlers() -> None:
    """Enregistre explicitement tous les handlers Socket.IO sur le serveur courant."""
    socketio.on_event("connect", on_connect)
    socketio.on_event("disconnect", on_disconnect)
    socketio.on_event("ping", on_ping)
    socketio.on_event("driver:heartbeat", on_ping)
    socketio.on_event("join_ride", on_join_ride)
    socketio.on_event("leave_ride", on_leave_ride)
    socketio.on_event("driver:go_online", on_driver_go_online)
    socketio.on_event("driver:go_offline", on_driver_go_offline)
    socketio.on_event("driver:location_update", on_driver_location_update)
    socketio.on_event("ride:send_message", on_ride_send_message)
