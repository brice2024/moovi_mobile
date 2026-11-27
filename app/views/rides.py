"""Blueprint des courses VTC : estimation, création, offres, négociation, machine à états, notation."""

import math

from flask import Blueprint, current_app, g, request
from sqlalchemy import desc

from app.extensions import db, limiter
from app.models import (
    ACTIVE_RIDE_STATUSES,
    RIDE_ALLOWED_TRANSITIONS,
    Driver,
    Ride,
    RideOffer,
    RideRating,
    Referral,
    User,
)
from app.models.user import utcnow
from app.tools.auth_helpers import auth_required, driver_required
from app.tools.benefits import (
    BenefitError,
    release_ride_benefit,
    reserve_ride_benefit,
    reward_completed_referral,
)
from app.tools.geo import (
    bounding_box,
    estimate_arrival_minutes,
    format_distance_text,
    format_duration_text,
    haversine_km,
)
from app.tools.pricing import clamp_ride_price, estimate_ride_prices
from app.tools.commission import announce_wallet_change, charge_ride_commission
from app.tools.realtime import (
    SERVING_VEHICLE_TYPES,
    create_and_emit_notification,
    emit_to_rooms,
    emit_to_online_drivers,
)
from app.tools.responses import fail, ok

rides_bp = Blueprint("rides", __name__, url_prefix="/api/rides")
ride_rate_limit = limiter.shared_limit("30 per minute", scope="rides")

VALID_RIDE_TYPES = {"voiture", "confort", "moto"}


def _finite(value) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if math.isfinite(number) else None


def _valid_coords(lat, lng) -> bool:
    return lat is not None and lng is not None and -90 <= lat <= 90 and -180 <= lng <= 180


def _driver_can_serve(driver: Driver, ride: Ride) -> bool:
    return driver.vehicle_type in SERVING_VEHICLE_TYPES.get(ride.ride_type, (ride.ride_type,))


def _driver_active_ride(driver: Driver) -> Ride | None:
    return Ride.query.filter(
        Ride.driver_id == driver.id,
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
    ).first()


def _driver_ineligibility(driver: Driver) -> tuple[str, str] | None:
    """Raison (message, code) pour laquelle le chauffeur ne peut pas prendre de course."""
    if driver.user is not None and not driver.user.is_active:
        return "Compte chauffeur désactivé.", "ACCOUNT_DISABLED"
    if driver.is_wallet_blocked or float(driver.wallet_balance or 0) < 0:
        return (
            "Portefeuille bloqué : rechargez votre compte avant de prendre une course.",
            "WALLET_BLOCKED",
        )
    if (
        current_app.config.get("REQUIRE_DRIVER_VERIFICATION")
        and driver.verification_status != "approved"
    ):
        return "Dossier chauffeur non validé.", "DRIVER_NOT_VERIFIED"
    return None


@rides_bp.post("/estimate")
@ride_rate_limit
@auth_required
def estimate_ride():
    data = request.get_json(silent=True) or {}
    distance_km = data.get("distanceKm")
    if distance_km is None and data.get("distanceMeters") is not None:
        distance_km = float(data["distanceMeters"]) / 1000.0
    if (
        distance_km is None
        and data.get("departureLat") is not None
        and data.get("departureLng") is not None
        and data.get("destinationLat") is not None
        and data.get("destinationLng") is not None
    ):
        # Estimation à vol d'oiseau * facteur routier 1.3 si Google Routes n'est pas fourni
        distance_km = (
            haversine_km(
                float(data["departureLat"]),
                float(data["departureLng"]),
                float(data["destinationLat"]),
                float(data["destinationLng"]),
            )
            * 1.3
        )
    estimates = estimate_ride_prices(
        float(distance_km) if distance_km is not None else None
    )
    return ok(
        data={
            "distanceKm": round(float(distance_km), 2) if distance_km else None,
            "options": list(estimates.values()),
        }
    )


@rides_bp.post("")
@ride_rate_limit
@auth_required
def create_ride():
    data = request.get_json(silent=True) or {}
    required = [
        "departureLat",
        "departureLng",
        "departureAddress",
        "destinationLat",
        "destinationLng",
        "destinationAddress",
    ]
    missing = [f for f in required if data.get(f) in (None, "")]
    if missing:
        return fail(
            f"Champs obligatoires manquants: {', '.join(missing)}",
            status=422,
            code="MISSING_FIELDS",
        )

    ride_type = str(data.get("rideType") or "voiture").strip().lower()
    if ride_type not in VALID_RIDE_TYPES:
        return fail(
            "Catégorie de course invalide (voiture, confort ou moto).",
            status=422,
            code="INVALID_RIDE_TYPE",
        )

    existing_active = Ride.query.filter(
        Ride.client_id == g.current_user.id,
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES)),
    ).first()
    if existing_active:
        return fail(
            "Vous avez déjà une course en cours ou en recherche.",
            status=409,
            code="ACTIVE_RIDE_EXISTS",
            details={"activeRideId": existing_active.id, "status": existing_active.status},
        )

    raw_price = data.get("price")
    if raw_price is None:
        raw_price = 2000 if ride_type == "voiture" else (3500 if ride_type == "confort" else 1000)

    min_price = current_app.config.get("MIN_RIDE_PRICE", 500)
    max_price = current_app.config.get("MAX_RIDE_PRICE", 50000)
    numeric_price = _finite(raw_price)
    if numeric_price is None:
        return fail("Prix invalide.", status=422, code="INVALID_PRICE")

    if numeric_price < min_price or numeric_price > max_price:
        return fail(
            f"Le prix doit être compris entre {min_price} et {max_price} XAF.",
            status=422,
            code="PRICE_OUT_OF_RANGE",
        )
    price = clamp_ride_price(numeric_price)

    dep_lat = _finite(data["departureLat"])
    dep_lng = _finite(data["departureLng"])
    dest_lat = _finite(data["destinationLat"])
    dest_lng = _finite(data["destinationLng"])
    if not (_valid_coords(dep_lat, dep_lng) and _valid_coords(dest_lat, dest_lng)):
        return fail("Coordonnées invalides.", status=422, code="INVALID_COORDINATES")

    distance_meters = data.get("distanceMeters")
    duration_seconds = data.get("durationSeconds")
    if distance_meters is None:
        estimated_km = haversine_km(dep_lat, dep_lng, dest_lat, dest_lng) * 1.25
        distance_meters = int(round(estimated_km * 1000))
    if duration_seconds is None:
        duration_seconds = max(60, int(round((float(distance_meters) / 1000.0) / 25.0 * 3600)))

    ride = Ride(
        client_id=g.current_user.id,
        departure_lat=dep_lat,
        departure_lng=dep_lng,
        departure_address=str(data["departureAddress"]).strip(),
        destination_lat=dest_lat,
        destination_lng=dest_lng,
        destination_address=str(data["destinationAddress"]).strip(),
        ride_type=ride_type,
        price=price,
        currency="XAF",  # portefeuilles et paiements sont tenus en XAF
        distance_meters=int(distance_meters),
        distance_text=str(
            data.get("distanceText")
            or data.get("distance")
            or format_distance_text(distance_meters)
        ),
        duration_seconds=int(duration_seconds),
        duration_text=str(
            data.get("durationText")
            or data.get("duration")
            or format_duration_text(duration_seconds)
        ),
        polyline=data.get("polyline"),
        status="searching",
    )
    db.session.add(ride)
    db.session.flush()
    try:
        reserve_ride_benefit(ride, g.current_user, data.get("promoCode"))
    except BenefitError as exc:
        db.session.rollback()
        return fail(str(exc), status=exc.status, code=exc.code)
    db.session.commit()

    ride_payload = ride.to_dict()
    from app.views.realtime import add_user_to_room

    add_user_to_room(ride.client_id, f"ride:{ride.id}")
    emit_to_online_drivers("ride:new", ride.to_dict(private=False), vehicle_type=ride.ride_type)
    return ok(data=ride_payload, message="Course créée. Recherche de chauffeurs en cours.", status=201)


@rides_bp.get("/active")
@ride_rate_limit
@auth_required
def get_active_ride():
    """Retourne la course active de l'utilisateur (passager ou chauffeur)."""
    role = request.args.get("role")
    ride = None
    if role == "driver" and g.current_user.driver_profile:
        ride = (
            Ride.query.filter(
                Ride.driver_id == g.current_user.driver_profile.id,
                Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
            )
            .order_by(desc(Ride.created_at))
            .first()
        )
    else:
        ride = (
            Ride.query.filter(
                Ride.client_id == g.current_user.id,
                Ride.status.in_(list(ACTIVE_RIDE_STATUSES)),
            )
            .order_by(desc(Ride.created_at))
            .first()
        )
        if not ride and g.current_user.driver_profile and role != "passenger":
            ride = (
                Ride.query.filter(
                    Ride.driver_id == g.current_user.driver_profile.id,
                    Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
                )
                .order_by(desc(Ride.created_at))
                .first()
            )
    if ride is None:
        # Course terminée mais pas encore réglée : l'application doit pouvoir
        # rouvrir le règlement (passager) ou l'encaissement (chauffeur).
        conditions = []
        if role != "driver":
            conditions.append(Ride.client_id == g.current_user.id)
        if g.current_user.driver_profile and role != "passenger":
            conditions.append(Ride.driver_id == g.current_user.driver_profile.id)
        if conditions:
            from datetime import timedelta

            from sqlalchemy import or_

            ride = (
                Ride.query.filter(
                    Ride.status == "completed",
                    Ride.is_paid.is_(False),
                    Ride.completed_at >= utcnow() - timedelta(hours=24),
                    or_(*conditions),
                )
                .order_by(desc(Ride.completed_at))
                .first()
            )
    return ok(data={"ride": ride.to_dict(include_offers=True) if ride else None})


@rides_bp.get("/available")
@ride_rate_limit
@driver_required()
def get_available_rides():
    """Liste des courses en recherche filtrées par proximité et type de véhicule du chauffeur."""
    driver: Driver = g.current_driver
    lat = request.args.get("lat", default=driver.latitude, type=float)
    lng = request.args.get("lng", default=driver.longitude, type=float)
    radius_km = request.args.get(
        "radiusKm",
        default=current_app.config.get("DEFAULT_SEARCH_RADIUS_KM", 6.0),
        type=float,
    )
    radius_km = min(max(radius_km or 0, 0), 30.0)
    match_vehicle = request.args.get("matchVehicle", default="true").lower() == "true"

    query = Ride.query.filter(
        Ride.status == "searching",
        Ride.client_id != g.current_user.id,
    )
    if match_vehicle:
        if driver.vehicle_type == "confort":
            query = query.filter(Ride.ride_type.in_(["voiture", "confort"]))
        else:
            query = query.filter(Ride.ride_type == driver.vehicle_type)

    if lat is not None and lng is not None and radius_km > 0:
        min_lat, max_lat, min_lng, max_lng = bounding_box(lat, lng, radius_km)
        query = query.filter(
            Ride.departure_lat.between(min_lat, max_lat),
            Ride.departure_lng.between(min_lng, max_lng),
        )

    rides = query.order_by(desc(Ride.created_at)).limit(50).all()
    results = []
    for ride in rides:
        item = ride.to_dict(private=False)
        if lat is not None and lng is not None:
            pickup_km = haversine_km(lat, lng, ride.departure_lat, ride.departure_lng)
            if radius_km > 0 and pickup_km > radius_km:
                continue
            item["pickupDistanceKm"] = round(pickup_km, 2)
            item["pickupEtaMinutes"] = estimate_arrival_minutes(pickup_km)
        results.append(item)

    if lat is not None and lng is not None:
        results.sort(key=lambda r: r.get("pickupDistanceKm", 0))

    return ok(data={"rides": results, "count": len(results)})


@rides_bp.get("/<string:ride_id>")
@ride_rate_limit
@auth_required
def get_ride_detail(ride_id: str):
    ride = db.session.get(Ride, ride_id)
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")

    driver = g.current_user.driver_profile
    is_participant = (
        ride.client_id == g.current_user.id
        or (driver is not None and ride.driver_id == driver.id)
        or g.current_user.role == "admin"
    )
    if is_participant:
        return ok(data=ride.to_dict(include_offers=True))

    # Chauffeur candidat : course encore en recherche et de sa catégorie, ou
    # course sur laquelle il a fait une offre (pour apprendre qu'elle est prise).
    has_offer = driver is not None and RideOffer.query.filter_by(
        ride_id=ride.id, driver_id=driver.id
    ).first() is not None
    if driver is not None and (
        has_offer or (ride.status == "searching" and _driver_can_serve(driver, ride))
    ):
        data = ride.to_dict(private=False)
        if has_offer:
            own = RideOffer.query.filter_by(ride_id=ride.id, driver_id=driver.id).first()
            data["offers"] = [own.to_dict()]
        return ok(data=data)
    return fail("Accès non autorisé à cette course.", status=403, code="FORBIDDEN")


@rides_bp.get("/<string:ride_id>/offers")
@ride_rate_limit
@auth_required
def list_ride_offers(ride_id: str):
    ride = db.session.get(Ride, ride_id)
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")

    driver = g.current_user.driver_profile
    is_client = ride.client_id == g.current_user.id
    if not is_client and not driver:
        return fail("Accès refusé.", status=403, code="FORBIDDEN")

    sort_by = request.args.get("sortBy", default="price")
    if is_client or g.current_user.role == "admin":
        offers = RideOffer.query.filter_by(ride_id=ride.id).all()
    else:
        # Un chauffeur ne voit jamais les offres de ses concurrents.
        offers = RideOffer.query.filter_by(ride_id=ride.id, driver_id=driver.id).all()
    if sort_by == "rating":
        offers.sort(key=lambda o: (-o.rating, o.price))
    elif sort_by == "fastest":
        offers.sort(key=lambda o: (o.arrival_minutes, o.price))
    elif sort_by == "recent":
        offers.sort(key=lambda o: o.updated_at, reverse=True)
    else:
        offers.sort(key=lambda o: (o.price, o.arrival_minutes))

    return ok(data={"offers": [o.to_dict() for o in offers]})


@rides_bp.post("/<string:ride_id>/offers")
@ride_rate_limit
@driver_required()
def submit_ride_offer(ride_id: str):
    driver: Driver = g.current_driver
    problem = _driver_ineligibility(driver)
    if problem:
        return fail(problem[0], status=402 if problem[1] == "WALLET_BLOCKED" else 403, code=problem[1])
    if _driver_active_ride(driver):
        return fail(
            "Terminez votre course en cours avant de proposer une nouvelle offre.",
            status=409,
            code="DRIVER_BUSY",
        )

    ride = db.session.get(Ride, ride_id)
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    if ride.status != "searching":
        return fail(
            "Cette course n'est plus disponible pour recevoir des offres.",
            status=409,
            code="RIDE_NOT_SEARCHING",
        )
    if ride.client_id == g.current_user.id:
        return fail(
            "Vous ne pouvez pas faire une offre sur votre propre course.",
            status=400,
            code="SELF_RIDE_NOT_ALLOWED",
        )

    if not _driver_can_serve(driver, ride):
        return fail(
            "Cette course demande une autre catégorie de véhicule.",
            status=403,
            code="VEHICLE_TYPE_MISMATCH",
        )
    max_km = float(current_app.config.get("DEFAULT_SEARCH_RADIUS_KM", 6.0)) * 3
    if driver.latitude is not None and driver.longitude is not None and haversine_km(
        driver.latitude, driver.longitude, ride.departure_lat, ride.departure_lng
    ) > max_km:
        return fail(
            "Vous êtes trop loin du point de départ de cette course.",
            status=403,
            code="TOO_FAR",
        )

    data = request.get_json(silent=True) or {}
    numeric_price = _finite(data.get("price", ride.price))
    if numeric_price is None:
        return fail("Prix d'offre invalide.", status=422, code="INVALID_PRICE")
    numeric_price = float(int(round(numeric_price)))

    min_price = current_app.config.get("MIN_RIDE_PRICE", 500)
    max_price = current_app.config.get("MAX_RIDE_PRICE", 50000)
    if numeric_price < min_price or numeric_price > max_price:
        return fail(
            f"L'offre doit être comprise entre {min_price} et {max_price} XAF.",
            status=422,
            code="PRICE_OUT_OF_RANGE",
        )

    arrival_minutes = data.get("arrivalMinutes")
    if arrival_minutes is None:
        if driver.latitude is not None and driver.longitude is not None:
            dist = haversine_km(
                driver.latitude, driver.longitude, ride.departure_lat, ride.departure_lng
            )
            arrival_minutes = estimate_arrival_minutes(dist)
        else:
            arrival_minutes = 5

    offer = RideOffer.query.filter_by(ride_id=ride.id, driver_id=driver.id).first()
    if offer is None:
        offer = RideOffer(ride_id=ride.id, driver_id=driver.id)
        db.session.add(offer)

    offer.driver_name = g.current_user.fullname or "Chauffeur Moovi"
    offer.rating = float(driver.rating or 4.8)
    offer.level = driver.level or "Or"
    offer.car = driver.vehicle_label
    offer.plate = driver.plate or ""
    offer.price = numeric_price
    offer.arrival_minutes = max(1, int(arrival_minutes))
    offer.photo_url = g.current_user.photo_url
    offer.message = (data.get("message") or "").strip()[:255] or None
    offer.status = "pending"

    create_and_emit_notification(
        user_id=ride.client_id,
        title="Nouvelle offre chauffeur",
        body=f"{offer.driver_name} propose {int(offer.price)} FCFA ({offer.arrival_minutes} min).",
        notif_type="ride_offer",
        payload={"rideId": ride.id, "offerId": offer.id, "price": offer.price},
    )
    db.session.commit()

    offer_payload = offer.to_dict()
    # Seul le passager reçoit les offres (les concurrents ne les voient pas).
    emit_to_rooms("ride:offer_received", offer_payload, user_ids=[ride.client_id])

    return ok(data=offer_payload, message="Proposition envoyée au client.")


@rides_bp.post("/<string:ride_id>/offers/<string:offer_or_driver_id>/accept")
@ride_rate_limit
@auth_required
def accept_offer(ride_id: str, offer_or_driver_id: str):
    """Accepte atomiquement une offre chauffeur et rejette les autres."""
    ride = (
        db.session.query(Ride)
        .filter(Ride.id == ride_id)
        .with_for_update()
        .first()
    )
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    if ride.client_id != g.current_user.id:
        return fail(
            "Seul le passager créateur peut accepter une offre.",
            status=403,
            code="FORBIDDEN",
        )
    if ride.status != "searching":
        return fail(
            "Cette course a déjà été attribuée ou annulée.",
            status=409,
            code="RIDE_NOT_SEARCHING",
        )

    offer = RideOffer.query.filter(
        RideOffer.ride_id == ride.id,
        (RideOffer.id == offer_or_driver_id)
        | (RideOffer.driver_id == offer_or_driver_id),
    ).first()
    if not offer:
        return fail("Offre introuvable.", status=404, code="OFFER_NOT_FOUND")
    if offer.status != "pending":
        return fail("Cette offre n'est plus valable.", status=409, code="OFFER_NOT_PENDING")

    driver = (
        db.session.query(Driver).filter(Driver.id == offer.driver_id).with_for_update().first()
    )
    if not driver:
        return fail("Chauffeur introuvable.", status=404, code="DRIVER_NOT_FOUND")
    problem = _driver_ineligibility(driver)
    if problem is None and _driver_active_ride(driver):
        problem = ("Ce chauffeur vient de prendre une autre course.", "DRIVER_BUSY")
    if problem is None and not _driver_can_serve(driver, ride):
        problem = ("Ce chauffeur ne peut plus assurer cette catégorie.", "VEHICLE_TYPE_MISMATCH")
    if problem:
        offer.status = "cancelled"
        db.session.commit()
        emit_to_rooms("ride:offer_withdrawn", {"rideId": ride.id, "offerId": offer.id},
                      user_ids=[ride.client_id])
        return fail(
            f"{problem[0]} Choisissez une autre offre.", status=409, code=problem[1]
        )

    now = utcnow()
    ride.status = "accepted"
    ride.driver_id = driver.id
    ride.agreed_price = offer.price
    ride.driver_name = offer.driver_name
    ride.driver_car = offer.car
    ride.driver_plate = offer.plate
    ride.driver_photo_url = offer.photo_url
    ride.driver_phone = driver.user.phone_number if driver.user else None
    ride.accepted_at = now

    offer.status = "accepted"
    RideOffer.query.filter(
        RideOffer.ride_id == ride.id, RideOffer.id != offer.id
    ).update({"status": "rejected"})

    create_and_emit_notification(
        user_id=driver.user_id,
        title="Offre acceptée !",
        body=f"Le passager a accepté votre offre de {int(offer.price)} FCFA.",
        notif_type="offer_accepted",
        payload={"rideId": ride.id, "agreedPrice": offer.price},
    )
    db.session.commit()

    ride_payload = ride.to_dict(include_offers=True)
    from app.views.realtime import add_user_to_room

    add_user_to_room(ride.client_id, f"ride:{ride.id}")
    add_user_to_room(driver.user_id, f"ride:{ride.id}")
    emit_to_rooms(
        "ride:accepted",
        ride_payload,
        ride_id=ride.id,
        user_ids=[ride.client_id, driver.user_id],
        driver_ids=[driver.id],
        admins=True,
    )
    emit_to_online_drivers("ride:taken", {"rideId": ride.id}, vehicle_type=ride.ride_type)

    return ok(data=ride_payload, message="Chauffeur confirmé. En route vers vous.")


def _transition_driver_ride(ride_id: str, target_status: str):
    driver: Driver = g.current_driver
    ride = (
        db.session.query(Ride)
        .filter(Ride.id == ride_id)
        .with_for_update()
        .first()
    )
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    if ride.driver_id != driver.id:
        return fail(
            "Vous n'êtes pas le chauffeur assigné à cette course.",
            status=403,
            code="FORBIDDEN",
        )

    allowed = RIDE_ALLOWED_TRANSITIONS.get(ride.status, set())
    if target_status not in allowed:
        return fail(
            f"Transition impossible de '{ride.status}' vers '{target_status}'.",
            status=409,
            code="INVALID_STATE_TRANSITION",
        )

    now = utcnow()
    ride.status = target_status
    referral_rewarded = target_status == "completed" and reward_completed_referral(ride)
    if target_status == "driver_arrived":
        ride.driver_arrived_at = now
        notif_title = "Votre chauffeur est arrivé"
        notif_body = f"{ride.driver_name or 'Votre chauffeur'} vous attend au point de départ."
    elif target_status == "in_progress":
        ride.started_at = now
        notif_title = "Course démarrée"
        notif_body = "Bon trajet avec Moovi !"
    elif target_status == "completed":
        ride.completed_at = now
        notif_title = "Vous êtes arrivé à destination"
        notif_body = "Course terminée. Veuillez procéder au règlement."
        locked_driver = (
            db.session.query(Driver).filter(Driver.id == driver.id).with_for_update().first()
        )
        went_offline = charge_ride_commission(ride, locked_driver, "Course terminée")
    else:
        notif_title = "Mise à jour de course"
        notif_body = f"Nouveau statut: {target_status}"

    create_and_emit_notification(
        user_id=ride.client_id,
        title=notif_title,
        body=notif_body,
        notif_type=f"ride_{target_status}",
        payload={"rideId": ride.id, "status": target_status},
    )
    if referral_rewarded:
        referral = Referral.query.filter_by(
            referred_user_id=ride.client_id, status="rewarded"
        ).first()
        if referral:
            for recipient_id, role in (
                (referral.referrer_id, "parrain"),
                (referral.referred_user_id, "filleul"),
            ):
                create_and_emit_notification(
                    user_id=recipient_id,
                    title="Bonus de parrainage reçu",
                    body=f"Votre bonus de parrainage de {referral.reward_amount} XAF est disponible.",
                    notif_type="referral_reward",
                    payload={"amount": referral.reward_amount, "role": role},
                )
    db.session.commit()

    payload = ride.to_dict()
    emit_to_rooms(
        "ride:status_changed",
        payload,
        ride_id=ride.id,
        user_ids=[ride.client_id],
        driver_ids=[driver.id],
        admins=True,
    )
    if target_status == "completed":
        announce_wallet_change(driver, went_offline)
    return ok(data=payload, message=notif_title)


@rides_bp.post("/<string:ride_id>/arrived")
@ride_rate_limit
@driver_required()
def mark_driver_arrived(ride_id: str):
    return _transition_driver_ride(ride_id, "driver_arrived")


@rides_bp.post("/<string:ride_id>/start")
@ride_rate_limit
@driver_required()
def start_ride(ride_id: str):
    return _transition_driver_ride(ride_id, "in_progress")


@rides_bp.post("/<string:ride_id>/complete")
@ride_rate_limit
@driver_required()
def complete_ride(ride_id: str):
    return _transition_driver_ride(ride_id, "completed")


@rides_bp.post("/<string:ride_id>/cancel")
@ride_rate_limit
@auth_required
def cancel_ride(ride_id: str):
    ride = (
        db.session.query(Ride)
        .filter(Ride.id == ride_id)
        .with_for_update()
        .first()
    )
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")

    driver = g.current_user.driver_profile
    is_client = ride.client_id == g.current_user.id
    is_assigned_driver = driver is not None and ride.driver_id == driver.id
    if not (is_client or is_assigned_driver or g.current_user.role == "admin"):
        return fail("Non autorisé à annuler cette course.", status=403, code="FORBIDDEN")

    if "cancelled" not in RIDE_ALLOWED_TRANSITIONS.get(ride.status, set()):
        return fail(
            f"Impossible d'annuler une course au statut '{ride.status}'.",
            status=409,
            code="CANNOT_CANCEL_RIDE",
        )

    data = request.get_json(silent=True) or {}
    reason = str(data.get("reason") or "").strip()[:255] or None

    previous_status = ride.status
    ride.status = "cancelled"
    ride.cancelled_by = "passenger" if is_client else ("driver" if is_assigned_driver else "admin")
    ride.cancel_reason = reason
    ride.cancelled_at = utcnow()
    release_ride_benefit(ride)

    if previous_status == "searching":
        RideOffer.query.filter_by(ride_id=ride.id, status="pending").update(
            {"status": "cancelled"}
        )

    if is_client and ride.driver_id and ride.driver:
        create_and_emit_notification(
            user_id=ride.driver.user_id,
            title="Course annulée",
            body="Le passager a annulé la course.",
            notif_type="ride_cancelled",
            payload={"rideId": ride.id, "reason": reason},
        )
    elif is_assigned_driver:
        create_and_emit_notification(
            user_id=ride.client_id,
            title="Course annulée par le chauffeur",
            body="Votre chauffeur a annulé la course. Vous pouvez relancer une recherche.",
            notif_type="ride_cancelled",
            payload={"rideId": ride.id, "reason": reason},
        )

    db.session.commit()
    payload = ride.to_dict()
    emit_to_rooms(
        "ride:cancelled",
        payload,
        ride_id=ride.id,
        user_ids=[ride.client_id],
        driver_ids=[ride.driver_id],
        admins=True,
    )
    if previous_status == "searching":
        emit_to_online_drivers("ride:taken", {"rideId": ride.id}, vehicle_type=ride.ride_type)

    return ok(data=payload, message="Course annulée.")


@rides_bp.post("/<string:ride_id>/rate")
@ride_rate_limit
@auth_required
def rate_ride(ride_id: str):
    ride = db.session.get(Ride, ride_id)
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    if ride.status != "completed":
        return fail(
            "Vous pouvez uniquement noter une course terminée.",
            status=409,
            code="RIDE_NOT_COMPLETED",
        )

    driver = g.current_user.driver_profile
    is_client = ride.client_id == g.current_user.id
    is_assigned_driver = driver is not None and ride.driver_id == driver.id
    if not (is_client or is_assigned_driver):
        return fail("Accès refusé.", status=403, code="FORBIDDEN")

    data = request.get_json(silent=True) or {}
    try:
        score = int(data.get("score"))
    except (TypeError, ValueError):
        return fail("La note doit être un entier entre 1 et 5.", status=422, code="INVALID_SCORE")
    if score < 1 or score > 5:
        return fail("La note doit être comprise entre 1 et 5.", status=422, code="INVALID_SCORE")

    comment = (data.get("comment") or "").strip()[:500] or None

    if is_client:
        if not ride.driver_id or not ride.driver:
            return fail("Aucun chauffeur associé à cette course.", status=400, code="NO_DRIVER")
        target_user_id = ride.driver.user_id
        target_role = "driver"
    else:
        target_user_id = ride.client_id
        target_role = "passenger"

    existing = RideRating.query.filter_by(
        ride_id=ride.id, rater_user_id=g.current_user.id
    ).first()
    if existing:
        return fail("Vous avez déjà noté cette course.", status=409, code="ALREADY_RATED")

    rating_row = RideRating(
        ride_id=ride.id,
        rater_user_id=g.current_user.id,
        target_user_id=target_user_id,
        target_role=target_role,
        score=score,
        comment=comment,
    )
    db.session.add(rating_row)

    # Recalcul de la moyenne
    if target_role == "driver":
        target_drv = (
            db.session.query(Driver).filter(Driver.id == ride.driver_id).with_for_update().first()
        )
        total_score = (target_drv.rating * target_drv.rating_count) + score
        target_drv.rating_count += 1
        target_drv.rating = round(total_score / target_drv.rating_count, 2)
        target_drv.recompute_level()
    else:
        target_user = db.session.get(User, target_user_id)
        if target_user:
            total_score = (target_user.rating * target_user.rating_count) + score
            target_user.rating_count += 1
            target_user.rating = round(total_score / target_user.rating_count, 2)

    db.session.commit()
    return ok(data=rating_row.to_dict(), message="Merci pour votre évaluation !", status=201)
