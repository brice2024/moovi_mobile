"""Helpers temps réel (Socket.IO) et création de notifications persistantes."""

from app.extensions import db, socketio
from app.models import Notification


def emit_to_user(user_id: str, event: str, data: dict) -> None:
    if not user_id:
        return
    socketio.emit(event, data, to=f"user:{user_id}")


def emit_to_driver(driver_id: str, event: str, data: dict) -> None:
    if not driver_id:
        return
    socketio.emit(event, data, to=f"driver:{driver_id}")


def emit_to_ride(ride_id: str, event: str, data: dict) -> None:
    if not ride_id:
        return
    socketio.emit(event, data, to=f"ride:{ride_id}")


def emit_to_rooms(
    event: str,
    data: dict,
    *,
    ride_id: str | None = None,
    user_ids: tuple | list = (),
    driver_ids: tuple | list = (),
    admins: bool = False,
) -> None:
    """Émet UNE fois par connexion, même si elle est membre de plusieurs rooms.

    python-socketio dédoublonne les destinataires quand `to` est une liste :
    un passager abonné à `ride:<id>` et à `user:<id>` ne reçoit l'événement
    qu'une seule fois.
    """
    rooms = []
    if ride_id:
        rooms.append(f"ride:{ride_id}")
    rooms += [f"user:{uid}" for uid in user_ids if uid]
    rooms += [f"driver:{did}" for did in driver_ids if did]
    if admins:
        rooms.append("admins")  # carte du back-office en temps réel
    if rooms:
        socketio.emit(event, data, to=rooms)


# Types de véhicule pouvant servir une catégorie de course (un chauffeur
# « confort » prend aussi les courses « voiture », comme dans /rides/available).
SERVING_VEHICLE_TYPES = {
    "voiture": ("voiture", "confort"),
    "confort": ("confort",),
    "moto": ("moto",),
}


def emit_to_online_drivers(event: str, data: dict, vehicle_type: str | None = None) -> None:
    """Diffuse aux chauffeurs en ligne pouvant servir `vehicle_type` (tous sinon)."""
    if vehicle_type:
        rooms = [f"online_drivers:{vt}" for vt in SERVING_VEHICLE_TYPES.get(vehicle_type, (vehicle_type,))]
    else:
        rooms = ["online_drivers"]
    socketio.emit(event, data, to=rooms)


def emit_to_passengers_map(event: str, data: dict) -> None:
    # Les administrateurs suivent aussi la carte (back-office) ; une seule
    # émission par connexion grâce à la liste de rooms.
    socketio.emit(event, data, to=["passengers_map", "admins"])


def emit_driver_location(payload: dict, driver) -> None:
    """Nouvelle position d'un chauffeur.

    - Carte passagers (`driver:location_updated`) : position seule, uniquement
      si le chauffeur est disponible.
    - Back-office (`admin:driver_update`) : fiche complète (nom, plaque, état,
      course) pour que la carte se mette à jour sans aucune requête.
    """
    from app.tools.driver_map import driver_map_entry

    if driver.is_available:
        socketio.emit("driver:location_updated", payload, to="passengers_map", skip_sid=None)
    socketio.emit("admin:driver_update", driver_map_entry(driver), to="admins")


def create_and_emit_notification(
    user_id: str,
    title: str,
    body: str,
    notif_type: str = "general",
    payload: dict | None = None,
    commit: bool = False,
) -> Notification:
    notif = Notification(
        user_id=user_id,
        title=title,
        body=body,
        type=notif_type,
        payload=payload or {},
    )
    db.session.add(notif)
    if commit:
        db.session.commit()
    else:
        db.session.flush()
    emit_to_user(user_id, "notification:new", notif.to_dict())
    return notif
