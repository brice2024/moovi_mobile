"""Blueprint espace chauffeur : inscription véhicule, documents, disponibilité, GPS temps réel."""

from datetime import datetime, timedelta, timezone

from flask import Blueprint, current_app, g, request
from sqlalchemy import func
from sqlalchemy import desc

from app.extensions import db
from app.models import (
    ACTIVE_RIDE_STATUSES,
    Driver,
    DriverDocument,
    REQUIRED_DOCS_BY_VEHICLE,
    Ride,
    Vehicle,
)
from app.models.user import utcnow
from app.tools.auth_helpers import auth_required, driver_profile_required, driver_required
from app.tools.geo import bounding_box, clean_position, estimate_arrival_minutes, haversine_km
from app.tools.realtime import emit_driver_location, emit_to_passengers_map, emit_to_ride
from app.tools.responses import fail, ok
from app.tools.storage import delete_stored_file, save_uploaded_file
from app.tools.vehicles import activate_vehicle, ensure_active_vehicle, sync_vehicle_from_driver
from app.views.realtime import sync_driver_rooms

drivers_bp = Blueprint("drivers", __name__, url_prefix="/api/drivers")

VALID_VEHICLE_TYPES = {"voiture", "confort", "moto"}
VALID_DOC_TYPES = {
    "license",
    "registration",
    "front",
    "left",
    "right",
    "back",
    "interior",
    "plate",
}


def _save_driver_document(driver: Driver, doc_type: str, file) -> DriverDocument:
    subdir = f"drivers/{driver.id}"
    rel_path, public_url = save_uploaded_file(file, subdir=subdir, prefix=doc_type)

    existing = DriverDocument.query.filter_by(
        driver_id=driver.id, doc_type=doc_type
    ).first()
    if existing:
        old_path = existing.file_path
        existing.file_path = rel_path
        existing.file_url = public_url
        existing.status = "pending"
        existing.rejection_reason = None
        existing.reviewed_by = None
        existing.reviewed_at = None
        if old_path and old_path != rel_path:
            delete_stored_file(old_path)
        return existing

    doc = DriverDocument(
        driver_id=driver.id,
        doc_type=doc_type,
        file_path=rel_path,
        file_url=public_url,
        status="pending",
    )
    db.session.add(doc)
    return doc


@drivers_bp.post("/register")
@auth_required
def register_or_update_driver():
    """Inscription / mise à jour véhicule (JSON ou multipart/form-data avec documents)."""
    if request.content_type and "multipart/form-data" in request.content_type:
        data = request.form.to_dict()
    else:
        data = request.get_json(silent=True) or {}

    vehicle_type = str(data.get("vehicleType") or data.get("type") or "voiture").strip().lower()
    if vehicle_type not in VALID_VEHICLE_TYPES:
        return fail(
            "Type de véhicule invalide (voiture, confort ou moto).",
            status=422,
            code="INVALID_VEHICLE_TYPE",
        )

    brand = str(data.get("brand") or "").strip()
    model = str(data.get("model") or "").strip()
    color = str(data.get("color") or "").strip()
    plate = str(data.get("plate") or "").strip().upper()

    if not all([brand, model, color, plate]):
        return fail(
            "Marque, modèle, couleur et plaque d'immatriculation sont obligatoires.",
            status=422,
            code="MISSING_VEHICLE_FIELDS",
        )

    user = g.current_user
    driver = user.driver_profile
    is_new = driver is None
    if driver and Ride.query.filter(
        Ride.driver_id == driver.id,
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
    ).first():
        return fail(
            "Impossible de modifier le véhicule pendant une course active.",
            status=409,
            code="ACTIVE_RIDE_EXISTS",
        )
    if driver is None:
        driver = Driver(
            user_id=user.id,
            wallet_balance=float(current_app.config.get("DEFAULT_WALLET_BALANCE", 5000.0)),
        )
        db.session.add(driver)
        db.session.flush()

    driver.vehicle_type = vehicle_type
    driver.brand = brand
    driver.model = model
    driver.color = color
    driver.plate = plate
    driver.verification_status = "pending"
    driver.is_available = False
    if user.role == "passenger":
        user.role = "driver"

    # Gestion éventuelle des fichiers envoyés simultanément
    for doc_type in REQUIRED_DOCS_BY_VEHICLE[vehicle_type]:
        file = request.files.get(doc_type)
        if not file and doc_type == "plate":
            file = request.files.get("platePhoto") or request.files.get("plate_photo")
        if file and file.filename:
            try:
                _save_driver_document(driver, doc_type, file)
            except ValueError as exc:
                db.session.rollback()
                return fail(f"{doc_type}: {exc}", status=422, code="INVALID_FILE")

    sync_vehicle_from_driver(driver)
    db.session.commit()
    sync_driver_rooms(driver)
    return ok(
        data=driver.to_dict(include_user=True, include_documents=True),
        message=(
            "Inscription chauffeur enregistrée."
            if is_new
            else "Informations chauffeur mises à jour."
        ),
        status=201 if is_new else 200,
    )


@drivers_bp.get("/me")
@driver_profile_required
def get_my_driver_profile():
    return ok(data=g.current_driver.to_dict(include_user=True, include_documents=True))


@drivers_bp.get("/me/rides")
@driver_profile_required
def get_my_driver_rides():
    driver: Driver = g.current_driver
    page = max(1, request.args.get("page", default=1, type=int))
    per_page = min(50, max(1, request.args.get("perPage", default=20, type=int)))
    raw_statuses = request.args.get("status")
    statuses = (
        {value.strip() for value in raw_statuses.split(",") if value.strip()}
        if raw_statuses
        else {"completed", "cancelled", "expired"}
    )
    allowed_statuses = {"searching", "accepted", "driver_arrived", "in_progress", "completed", "cancelled", "expired"}
    if not statuses or not statuses.issubset(allowed_statuses):
        return fail("Filtre de statut invalide.", status=422, code="INVALID_STATUS")

    query = Ride.query.filter(
        Ride.driver_id == driver.id,
        Ride.status.in_(statuses),
    )
    pagination = query.order_by(desc(Ride.created_at)).paginate(
        page=page, per_page=per_page, error_out=False
    )

    local_tz = timezone(timedelta(hours=1))
    now = datetime.now(local_tz)
    month_start = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    week_start = (now - timedelta(days=now.weekday())).replace(
        hour=0, minute=0, second=0, microsecond=0
    )
    today_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    def as_utc_naive(value: datetime) -> datetime:
        return value.astimezone(timezone.utc).replace(tzinfo=None)

    def period_stats(start: datetime) -> dict:
        result = (
            db.session.query(
                func.count(Ride.id),
                func.coalesce(
                    func.sum(func.coalesce(Ride.agreed_price, Ride.price)), 0.0
                ),
                func.coalesce(func.sum(Ride.paid_amount), 0.0),
                func.coalesce(func.sum(Ride.platform_commission), 0.0),
            )
            .filter(
                Ride.driver_id == driver.id,
                Ride.status == "completed",
                Ride.is_paid.is_(True),
                Ride.paid_at >= as_utc_naive(start),
                Ride.paid_at <= as_utc_naive(now),
            )
            .one()
        )
        gross = float(result[1] or 0)
        amount_collected = float(result[2] or 0)
        commission = float(result[3] or 0)
        return {
            "ridesCount": int(result[0] or 0),
            "grossRevenue": round(gross, 2),
            "amountCollected": round(amount_collected, 2),
            "commission": round(commission, 2),
            "netRevenue": round(gross - commission, 2),
            "currency": "XAF",
        }

    return ok(
        data={
            "rides": [ride.to_dict() for ride in pagination.items],
            "pagination": {
                "page": pagination.page,
                "perPage": pagination.per_page,
                "total": pagination.total,
                "pages": pagination.pages,
            },
            "statistics": {
                "today": period_stats(today_start),
                "thisWeek": period_stats(week_start),
                "thisMonth": period_stats(month_start),
            },
        }
    )


@drivers_bp.get("/me/vehicles")
@driver_profile_required
def list_my_vehicles():
    driver: Driver = g.current_driver
    ensure_active_vehicle(driver)
    db.session.commit()
    return ok(data={"vehicles": [vehicle.to_dict() for vehicle in driver.vehicles]})


@drivers_bp.post("/me/vehicles")
@driver_profile_required
def add_vehicle():
    driver: Driver = g.current_driver
    data = request.get_json(silent=True) or {}
    vehicle_type = str(data.get("vehicleType") or "").strip().lower()
    fields = {
        "brand": str(data.get("brand") or "").strip(),
        "model": str(data.get("model") or "").strip(),
        "color": str(data.get("color") or "").strip(),
        "plate": str(data.get("plate") or "").strip().upper(),
    }
    if vehicle_type not in VALID_VEHICLE_TYPES:
        return fail("Type de véhicule invalide.", status=422, code="INVALID_VEHICLE_TYPE")
    if not all(fields.values()):
        return fail(
            "Marque, modèle, couleur et plaque sont obligatoires.",
            status=422,
            code="MISSING_VEHICLE_FIELDS",
        )
    limits = {"brand": 80, "model": 80, "color": 50, "plate": 32}
    if any(len(fields[key]) > limit for key, limit in limits.items()):
        return fail("Un champ véhicule dépasse la longueur maximale.", status=422, code="INVALID_VEHICLE_FIELDS")
    if Vehicle.query.filter_by(driver_id=driver.id, plate=fields["plate"]).first():
        return fail(
            "Cette plaque est déjà enregistrée pour votre compte.",
            status=409,
            code="VEHICLE_EXISTS",
        )

    ensure_active_vehicle(driver)
    vehicle = Vehicle(
        driver_id=driver.id,
        vehicle_type=vehicle_type,
        verification_status="pending",
        **fields,
    )
    if not Vehicle.query.filter_by(driver_id=driver.id, is_active=True).first():
        vehicle.is_active = True
        activate_vehicle(driver, vehicle)
    db.session.add(vehicle)
    db.session.commit()
    return ok(data=vehicle.to_dict(), message="Véhicule enregistré.", status=201)


@drivers_bp.put("/me/vehicles/<string:vehicle_id>/activate")
@driver_profile_required
def select_active_vehicle(vehicle_id: str):
    driver: Driver = g.current_driver
    vehicle = Vehicle.query.filter_by(id=vehicle_id, driver_id=driver.id).first()
    if not vehicle:
        return fail("Véhicule introuvable.", status=404, code="VEHICLE_NOT_FOUND")
    active_ride = Ride.query.filter(
        Ride.driver_id == driver.id,
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
    ).first()
    if active_ride:
        return fail(
            "Impossible de changer de véhicule pendant une course active.",
            status=409,
            code="ACTIVE_RIDE_EXISTS",
        )
    if (
        current_app.config.get("REQUIRE_DRIVER_VERIFICATION")
        and vehicle.verification_status != "approved"
    ):
        return fail(
            "Ce véhicule doit être vérifié avant son activation.",
            status=403,
            code="VEHICLE_NOT_VERIFIED",
        )
    was_available = driver.is_available
    driver.is_available = False
    activate_vehicle(driver, vehicle)
    db.session.commit()
    sync_driver_rooms(driver)
    if was_available:
        emit_to_passengers_map(
            "driver:availability_changed",
            {"driverId": driver.id, "isAvailable": False, "vehicleType": vehicle.vehicle_type},
        )
    return ok(
        data={"activeVehicle": vehicle.to_dict(), "isAvailable": driver.is_available},
        message="Véhicule actif mis à jour.",
    )


@drivers_bp.get("/me/documents")
@driver_profile_required
def get_my_documents():
    driver: Driver = g.current_driver
    return ok(
        data={
            "driverId": driver.id,
            "vehicleType": driver.vehicle_type,
            "verificationStatus": driver.verification_status,
            **driver.documents_summary(),
        }
    )


@drivers_bp.post("/me/documents/<string:doc_type>")
@driver_profile_required
def upload_driver_document(doc_type: str):
    doc_type = doc_type.strip().lower()
    if doc_type not in VALID_DOC_TYPES:
        return fail(
            f"Type de document invalide ({', '.join(sorted(VALID_DOC_TYPES))}).",
            status=422,
            code="INVALID_DOC_TYPE",
        )

    file = request.files.get("file") or request.files.get(doc_type)
    if not file or not file.filename:
        return fail("Aucun fichier fourni.", status=422, code="MISSING_FILE")

    current_driver = g.current_user.driver_profile
    if current_driver is not None and Ride.query.filter(
        Ride.driver_id == current_driver.id,
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
    ).first():
        # Le dossier repasse « en attente » après un envoi : interdit en pleine
        # course, sinon le chauffeur ne pourrait plus terminer ni encaisser.
        return fail(
            "Terminez votre course avant de modifier vos documents.",
            status=409,
            code="DRIVER_BUSY",
        )

    driver: Driver = g.current_driver
    try:
        doc = _save_driver_document(driver, doc_type, file)
    except ValueError as exc:
        return fail(str(exc), status=422, code="INVALID_FILE")

    driver.verification_status = "pending"
    db.session.commit()
    return ok(
        data={
            "document": doc.to_dict(),
            "documentsSummary": driver.documents_summary(),
            "verificationStatus": driver.verification_status,
        },
        message="Document téléchargé et soumis pour vérification.",
    )


@drivers_bp.put("/me/availability")
@driver_required()
def update_availability():
    driver: Driver = g.current_driver
    data = request.get_json(silent=True) or {}
    if "isAvailable" not in data:
        return fail("Le champ isAvailable est requis.", status=422, code="MISSING_FIELD")

    desired_online = bool(data["isAvailable"])

    if desired_online:
        if current_app.config.get("REQUIRE_DRIVER_VERIFICATION") and driver.verification_status != "approved":
            return fail(
                "Vos documents doivent être vérifiés avant de passer en ligne.",
                status=403,
                code="DRIVER_NOT_VERIFIED",
                details={"verificationStatus": driver.verification_status},
            )
        if driver.is_wallet_blocked or float(driver.wallet_balance or 0) < 0:
            return fail(
                "Solde du portefeuille insuffisant ou bloqué. Veuillez recharger votre compte.",
                status=402,
                code="WALLET_BLOCKED",
                details={
                    "walletBalance": driver.wallet_balance,
                    "isWalletBlocked": driver.is_wallet_blocked,
                },
            )

    position = clean_position(data.get("latitude"), data.get("longitude"), data.get("heading"))
    if position:
        driver.latitude, driver.longitude = position[0], position[1]
        driver.last_location_at = utcnow()
        if position[2] is not None:
            driver.heading = position[2]

    if desired_online:
        driver.last_location_at = utcnow()
    driver.is_available = desired_online
    db.session.commit()
    sync_driver_rooms(driver)

    emit_to_passengers_map(
        "driver:availability_changed",
        {
            "driverId": driver.id,
            "isAvailable": driver.is_available,
            "vehicleType": driver.vehicle_type,
            "latitude": driver.latitude,
            "longitude": driver.longitude,
            "heading": driver.heading,
        },
    )

    return ok(
        data={
            "isAvailable": driver.is_available,
            "latitude": driver.latitude,
            "longitude": driver.longitude,
            "walletBalance": driver.wallet_balance,
            "isWalletBlocked": driver.is_wallet_blocked,
        },
        message=(
            "Vous êtes maintenant EN LIGNE."
            if driver.is_available
            else "Vous êtes maintenant HORS LIGNE."
        ),
    )


@drivers_bp.put("/me/location")
@driver_required()
def update_location():
    driver: Driver = g.current_driver
    data = request.get_json(silent=True) or {}
    lat = data.get("latitude")
    lng = data.get("longitude")
    if lat is None or lng is None:
        return fail("latitude et longitude sont requis.", status=422, code="MISSING_COORDS")

    position = clean_position(lat, lng, data.get("heading"))
    if not position:
        return fail("Position GPS invalide.", status=422, code="INVALID_COORDINATES")
    driver.latitude, driver.longitude = position[0], position[1]
    if position[2] is not None:
        driver.heading = position[2]
    driver.last_location_at = utcnow()
    db.session.commit()

    payload = {
        "driverId": driver.id,
        "vehicleType": driver.vehicle_type,
        "latitude": driver.latitude,
        "longitude": driver.longitude,
        "heading": driver.heading,
        "timestamp": driver.last_location_at.isoformat(),
    }

    emit_driver_location(payload, driver)

    # Si le chauffeur a une course active, notifier directement le passager dans la room de la course
    active_ride = Ride.query.filter(
        Ride.driver_id == driver.id,
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES - {"searching"})),
    ).first()
    if active_ride:
        emit_to_ride(
            active_ride.id,
            "ride:driver_location",
            {"rideId": active_ride.id, **payload},
        )

    return ok(data=payload)


@drivers_bp.get("/nearby")
@auth_required
def get_nearby_drivers():
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    if lat is None or lng is None:
        return fail("Paramètres lat et lng requis.", status=422, code="MISSING_COORDS")

    radius_km = request.args.get(
        "radiusKm",
        default=current_app.config.get("DEFAULT_SEARCH_RADIUS_KM", 6.0),
        type=float,
    )
    radius_km = min(max(radius_km or 0, 0), 20.0)  # pas d'aspiration de toute la flotte
    vehicle_type = request.args.get("vehicleType")
    include_test = request.args.get("includeTest", default="true").lower() == "true"

    min_lat, max_lat, min_lng, max_lng = bounding_box(lat, lng, radius_km)
    query = Driver.query.filter(
        Driver.is_available.is_(True),
        Driver.is_wallet_blocked.is_(False),
        Driver.latitude.isnot(None),
        Driver.longitude.isnot(None),
        Driver.latitude.between(min_lat, max_lat),
        Driver.longitude.between(min_lng, max_lng),
    )
    if vehicle_type in VALID_VEHICLE_TYPES:
        query = query.filter(Driver.vehicle_type == vehicle_type)
    if not include_test:
        query = query.filter(Driver.is_test.is_(False))
    if current_app.config.get("REQUIRE_DRIVER_VERIFICATION"):
        query = query.filter(Driver.verification_status == "approved")

    candidates = query.all()
    results = []
    for drv in candidates:
        dist = haversine_km(lat, lng, drv.latitude, drv.longitude)
        if dist <= radius_km:
            item = drv.to_public_dict()
            item["distanceKm"] = round(dist, 2)
            item["arrivalMinutes"] = estimate_arrival_minutes(dist)
            results.append(item)

    results.sort(key=lambda x: x["distanceKm"])
    return ok(data={"drivers": results, "count": len(results), "radiusKm": radius_km})
