"""Blueprint back-office admin : validation documents chauffeurs, statistiques et seeding."""

import random
from datetime import datetime, timezone
from flask import Blueprint, current_app, g, request
from sqlalchemy import desc, func

from app.extensions import db
from app.models import Driver, DriverDocument, PromoCode, Ride, User, Vehicle
from app.models.user import utcnow
from app.tools.auth_helpers import admin_required
from app.tools.realtime import (
    create_and_emit_notification,
    emit_to_driver,
    emit_to_passengers_map,
)
from app.views.realtime import sync_driver_rooms
from app.tools.responses import fail, ok
from app.tools.vehicles import sync_vehicle_from_driver

admin_bp = Blueprint("admin", __name__, url_prefix="/api/admin")


@admin_bp.get("/promo-codes")
@admin_required
def list_promo_codes():
    from app.models import RideBenefit

    codes = PromoCode.query.order_by(desc(PromoCode.created_at)).all()
    usage = dict(
        db.session.query(RideBenefit.promo_code_id, func.count(RideBenefit.ride_id))
        .filter(RideBenefit.status == "redeemed", RideBenefit.promo_code_id.isnot(None))
        .group_by(RideBenefit.promo_code_id)
        .all()
    )
    return ok(
        data={"promoCodes": [{**code.to_dict(), "usedCount": usage.get(code.id, 0)} for code in codes]}
    )


@admin_bp.post("/promo-codes")
@admin_required
def create_promo_code():
    data = request.get_json(silent=True) or {}
    code = str(data.get("code") or "").strip().upper()
    if not code or len(code) > 40 or any(character.isspace() for character in code):
        return fail("Code promo invalide.", status=422, code="INVALID_PROMO_CODE")
    if PromoCode.query.filter_by(code=code).first():
        return fail("Ce code promo existe déjà.", status=409, code="PROMO_CODE_EXISTS")
    try:
        discount = int(data.get("discountAmount", 500))
        max_uses = int(data["maxUses"]) if data.get("maxUses") is not None else None
    except (TypeError, ValueError):
        return fail("Montant ou nombre d'utilisations invalide.", status=422, code="INVALID_PROMO")
    if discount <= 0 or (max_uses is not None and max_uses <= 0):
        return fail("Montant et limite doivent être positifs.", status=422, code="INVALID_PROMO")

    expires_at = None
    if data.get("expiresAt"):
        try:
            expires_at = datetime.fromisoformat(str(data["expiresAt"]).replace("Z", "+00:00"))
            if expires_at.tzinfo:
                expires_at = expires_at.astimezone(timezone.utc).replace(tzinfo=None)
        except ValueError:
            return fail("Date d'expiration invalide.", status=422, code="INVALID_EXPIRY")

    promo = PromoCode(
        code=code,
        discount_amount=discount,
        max_uses=max_uses,
        expires_at=expires_at,
        created_by=g.current_user.id,
    )
    db.session.add(promo)
    db.session.commit()
    return ok(data=promo.to_dict(), message="Code promo créé.", status=201)


@admin_bp.patch("/promo-codes/<string:promo_id>")
@admin_required
def update_promo_code(promo_id: str):
    promo = db.session.get(PromoCode, promo_id)
    if not promo:
        return fail("Code promo introuvable.", status=404, code="PROMO_NOT_FOUND")
    data = request.get_json(silent=True) or {}
    if "isActive" not in data:
        return fail("Le champ isActive est requis.", status=422, code="MISSING_FIELD")
    promo.is_active = bool(data["isActive"])
    db.session.commit()
    return ok(data=promo.to_dict(), message="Code promo mis à jour.")


@admin_bp.get("/drivers")
@admin_required
def list_drivers():
    status_filter = request.args.get("verificationStatus")
    page = max(1, request.args.get("page", default=1, type=int))
    per_page = min(50, max(1, request.args.get("perPage", default=20, type=int)))

    query = Driver.query
    if status_filter:
        query = query.filter_by(verification_status=status_filter)
    online = request.args.get("online")
    if online in {"true", "false"}:
        query = query.filter(Driver.is_available.is_(online == "true"))
    if request.args.get("blocked") == "true":
        query = query.filter(Driver.is_wallet_blocked.is_(True))
    vehicle_type = request.args.get("vehicleType")
    if vehicle_type:
        query = query.filter(Driver.vehicle_type == vehicle_type)
    q = (request.args.get("q") or "").strip()
    if q:
        from sqlalchemy import or_

        like = f"%{q}%"
        query = query.filter(
            or_(
                Driver.plate.ilike(like),
                Driver.user.has(
                    or_(User.first_name.ilike(like), User.last_name.ilike(like),
                        User.phone_number.ilike(like))
                ),
            )
        )

    pagination = query.order_by(desc(Driver.updated_at)).paginate(
        page=page, per_page=per_page, error_out=False
    )
    return ok(
        data={
            "drivers": [
                d.to_dict(include_user=True, include_documents=True)
                for d in pagination.items
            ],
            "pagination": {
                "page": pagination.page,
                "perPage": pagination.per_page,
                "total": pagination.total,
                "pages": pagination.pages,
            },
        }
    )


@admin_bp.get("/drivers/<string:driver_id>")
@admin_required
def get_driver_detail(driver_id: str):
    driver = db.session.get(Driver, driver_id)
    if not driver:
        return fail("Chauffeur introuvable.", status=404, code="DRIVER_NOT_FOUND")
    return ok(data=driver.to_dict(include_user=True, include_documents=True))


@admin_bp.post("/drivers/<string:driver_id>/documents/<string:doc_type>/review")
@admin_required
def review_driver_document(driver_id: str, doc_type: str):
    driver = db.session.get(Driver, driver_id)
    if not driver:
        return fail("Chauffeur introuvable.", status=404, code="DRIVER_NOT_FOUND")

    doc = DriverDocument.query.filter_by(
        driver_id=driver.id, doc_type=doc_type.strip().lower()
    ).first()
    if not doc:
        return fail("Document introuvable.", status=404, code="DOCUMENT_NOT_FOUND")

    data = request.get_json(silent=True) or {}
    decision = str(data.get("status") or "").strip().lower()
    if decision not in {"verified", "rejected"}:
        return fail(
            "Le statut doit être 'verified' ou 'rejected'.",
            status=422,
            code="INVALID_STATUS",
        )

    doc.status = decision
    doc.rejection_reason = (
        str(data.get("reason") or "").strip()[:255] if decision == "rejected" else None
    )
    doc.reviewed_by = g.current_user.id
    doc.reviewed_at = utcnow()
    was_available = driver.is_available

    # Recalcul automatique du verification_status global du chauffeur
    required = driver.required_document_types()
    docs_map = {d.doc_type: d for d in driver.documents}
    if any(
        docs_map.get(rt) is not None and docs_map[rt].status == "rejected"
        for rt in required
    ):
        driver.verification_status = "rejected"
    elif all(
        docs_map.get(rt) is not None and docs_map[rt].status == "verified"
        for rt in required
    ):
        driver.verification_status = "approved"
    else:
        driver.verification_status = "pending"
    if driver.verification_status != "approved":
        driver.is_available = False
    sync_vehicle_from_driver(driver)

    create_and_emit_notification(
        user_id=driver.user_id,
        title="Vérification de document",
        body=(
            f"Document '{doc.doc_type}' validé."
            if decision == "verified"
            else f"Document '{doc.doc_type}' refusé: {doc.rejection_reason or 'Veuillez le renvoyer.'}"
        ),
        notif_type="document_reviewed",
        payload={
            "docType": doc.doc_type,
            "status": decision,
            "verificationStatus": driver.verification_status,
        },
    )
    db.session.commit()
    sync_driver_rooms(driver)
    if was_available and not driver.is_available:
        emit_to_passengers_map(
            "driver:availability_changed",
            {
                "driverId": driver.id,
                "isAvailable": False,
                "vehicleType": driver.vehicle_type,
            },
        )

    emit_to_driver(
        driver.id,
        "driver:verification_updated",
        {
            "driverId": driver.id,
            "verificationStatus": driver.verification_status,
            "documents": driver.documents_summary(),
        },
    )

    return ok(
        data=driver.to_dict(include_user=True, include_documents=True),
        message="Document examiné.",
    )


@admin_bp.post("/drivers/<string:driver_id>/verify")
@admin_required
def verify_driver_bulk(driver_id: str):
    """Validation/rejet global rapide d'un dossier chauffeur."""
    driver = db.session.get(Driver, driver_id)
    if not driver:
        return fail("Chauffeur introuvable.", status=404, code="DRIVER_NOT_FOUND")

    data = request.get_json(silent=True) or {}
    decision = str(data.get("verificationStatus") or "approved").strip().lower()
    if decision not in {"approved", "rejected", "pending"}:
        return fail("Statut invalide.", status=422, code="INVALID_STATUS")

    driver.verification_status = decision
    was_available = driver.is_available
    if decision != "approved":
        driver.is_available = False
    sync_vehicle_from_driver(driver)
    if decision == "approved":
        for doc in driver.documents:
            doc.status = "verified"
            doc.reviewed_by = g.current_user.id
            doc.reviewed_at = utcnow()
            doc.rejection_reason = None

    create_and_emit_notification(
        user_id=driver.user_id,
        title="Statut de dossier chauffeur",
        body=f"Votre dossier chauffeur est maintenant : {decision}.",
        notif_type="driver_verification",
        payload={"verificationStatus": decision},
    )
    db.session.commit()
    sync_driver_rooms(driver)
    if was_available and not driver.is_available:
        emit_to_passengers_map(
            "driver:availability_changed",
            {
                "driverId": driver.id,
                "isAvailable": False,
                "vehicleType": driver.vehicle_type,
            },
        )
    emit_to_driver(
        driver.id,
        "driver:verification_updated",
        {"driverId": driver.id, "verificationStatus": driver.verification_status},
    )
    return ok(data=driver.to_dict(include_user=True, include_documents=True))


@admin_bp.post("/drivers/<string:driver_id>/vehicles/<string:vehicle_id>/review")
@admin_required
def review_driver_vehicle(driver_id: str, vehicle_id: str):
    driver = db.session.get(Driver, driver_id)
    if not driver:
        return fail("Chauffeur introuvable.", status=404, code="DRIVER_NOT_FOUND")
    vehicle = Vehicle.query.filter_by(id=vehicle_id, driver_id=driver.id).first()
    if not vehicle:
        return fail("Véhicule introuvable.", status=404, code="VEHICLE_NOT_FOUND")

    data = request.get_json(silent=True) or {}
    decision = str(data.get("verificationStatus") or "").strip().lower()
    if decision not in {"approved", "rejected", "pending"}:
        return fail("Statut invalide.", status=422, code="INVALID_STATUS")
    vehicle.verification_status = decision
    should_offline = vehicle.is_active and decision != "approved" and driver.is_available
    if vehicle.is_active:
        driver.verification_status = decision
        if should_offline:
            driver.is_available = False
    db.session.commit()
    sync_driver_rooms(driver)
    if should_offline:
        emit_to_passengers_map(
            "driver:availability_changed",
            {
                "driverId": driver.id,
                "isAvailable": False,
                "vehicleType": driver.vehicle_type,
            },
        )
    emit_to_driver(
        driver.id,
        "driver:vehicle_verification_updated",
        {
            "driverId": driver.id,
            "vehicle": vehicle.to_dict(),
            "verificationStatus": driver.verification_status,
        },
    )
    return ok(data=vehicle.to_dict(), message="Véhicule examiné.")


@admin_bp.get("/stats")
@admin_required
def get_stats():
    total_users = User.query.count()
    total_drivers = Driver.query.count()
    online_drivers = Driver.query.filter_by(is_available=True).count()
    pending_verifications = Driver.query.filter_by(verification_status="pending").count()
    total_rides = Ride.query.count()
    completed_rides = Ride.query.filter_by(status="completed").count()
    total_commission = (
        db.session.query(func.coalesce(func.sum(Ride.platform_commission), 0.0))
        .filter(Ride.is_paid.is_(True))
        .scalar()
    )
    total_volume = (
        db.session.query(func.coalesce(func.sum(Ride.paid_amount), 0.0))
        .filter(Ride.is_paid.is_(True))
        .scalar()
    )
    return ok(
        data={
            "usersCount": total_users,
            "driversCount": total_drivers,
            "onlineDriversCount": online_drivers,
            "pendingDriverVerifications": pending_verifications,
            "ridesCount": total_rides,
            "completedRidesCount": completed_rides,
            "totalRideVolume": round(float(total_volume or 0), 2),
            "totalPlatformCommission": round(float(total_commission or 0), 2),
        }
    )


@admin_bp.post("/seed-test-drivers")
@admin_required
def seed_test_drivers_endpoint():
    if current_app.config.get("APP_ENV") == "production":
        return fail(
            "Les chauffeurs de test sont interdits en production.", status=403, code="FORBIDDEN_IN_PRODUCTION"
        )
    count = min(50, max(1, (request.get_json(silent=True) or {}).get("count", 10)))
    created = seed_test_drivers_in_libreville(count=count)
    return ok(data={"created": created}, message=f"{created} chauffeurs de test ajoutés.")


def seed_test_drivers_in_libreville(count: int = 15) -> int:
    if current_app.config.get("APP_ENV") == "production":
        raise RuntimeError("Les chauffeurs de test sont interdits en production.")
    """Crée des chauffeurs de démonstration autour de Libreville (Gabon)."""
    brands = [
        ("Toyota", "Corolla", "voiture"),
        ("Hyundai", "Accent", "voiture"),
        ("Toyota", "RAV4", "confort"),
        ("Suzuki", "Swift", "voiture"),
        ("Bajaj", "Boxer", "moto"),
    ]
    colors = ["Gris", "Blanc", "Noir", "Bleu", "Rouge"]
    created = 0
    for idx in range(1, count + 1):
        phone = f"+2410799{idx:04d}"
        if User.query.filter_by(phone_number=phone).first():
            continue
        user = User(
            phone_number=phone,
            first_name="Chauffeur",
            last_name=f"Libreville {idx:02d}",
            role="driver",
        )
        db.session.add(user)
        db.session.flush()

        brand, model, vtype = brands[idx % len(brands)]
        lat = 0.4162 + random.uniform(-0.035, 0.035)
        lng = 9.4673 + random.uniform(-0.035, 0.035)
        drv = Driver(
            user_id=user.id,
            vehicle_type=vtype,
            brand=brand,
            model=model,
            color=colors[idx % len(colors)],
            plate=f"{1000 + idx}-GA-01",
            verification_status="approved",
            is_available=True,
            is_test=True,
            latitude=lat,
            longitude=lng,
            city="Libreville",
            wallet_balance=5000.0,
            last_location_at=utcnow(),
        )
        db.session.add(drv)
        created += 1
    db.session.commit()
    return created
