"""Blueprint espace passager : profil, historique, parrainage et gestion de compte."""

from flask import Blueprint, current_app, g, request
from sqlalchemy import desc, func, or_

from app.extensions import db
from app.models import (
    ACTIVE_RIDE_STATUSES,
    DeviceToken,
    DriverDocument,
    Notification,
    OtpCode,
    Referral,
    ReferralCode,
    Ride,
    RideBenefit,
    RideMessage,
    RideOffer,
    User,
    UserCreditTransaction,
    WalletTransaction,
)
from app.tools.auth_helpers import auth_required
from app.tools.benefits import get_or_create_referral_code
from app.tools.geo import is_valid_phone_number, normalize_phone_number
from app.tools.responses import fail, ok
from app.tools.storage import delete_stored_file, save_uploaded_file
from app.views.realtime import disconnect_user_sessions

users_bp = Blueprint("users", __name__, url_prefix="/api/users")




def _consume_otp(phone: str, code: str) -> bool:
    from app.models import OtpCode
    from app.models.user import utcnow
    from app.tools.auth_helpers import verify_secret

    if len(code) != 6 or not code.isdigit():
        return False
    record = (
        OtpCode.query.filter_by(phone_number=phone, is_used=False)
        .order_by(OtpCode.created_at.desc())
        .first()
    )
    max_attempts = current_app.config.get("OTP_MAX_ATTEMPTS", 5)
    if not record or record.expires_at < utcnow() or record.attempts >= max_attempts:
        return False
    if not verify_secret(record.code_hash, code):
        record.attempts += 1
        db.session.commit()
        return False
    record.is_used = True
    return True

@users_bp.get("/me")
@auth_required
def get_profile():
    return ok(data=g.current_user.to_dict(include_driver=True))


@users_bp.route("/me", methods=["PUT", "PATCH"])
@auth_required
def update_profile():
    user: User = g.current_user
    data = request.get_json(silent=True) or {}

    if "firstName" in data:
        first_name = str(data["firstName"] or "").strip()
        if not first_name:
            return fail("Le prénom est obligatoire.", status=422, code="INVALID_FIRST_NAME")
        user.first_name = first_name

    if "lastName" in data:
        last_name = str(data["lastName"] or "").strip()
        if not last_name:
            return fail("Le nom est obligatoire.", status=422, code="INVALID_LAST_NAME")
        user.last_name = last_name

    if "phone" in data or "phoneNumber" in data:
        raw_phone = data.get("phoneNumber") if "phoneNumber" in data else data.get("phone")
        phone = normalize_phone_number(str(raw_phone or ""))
        if not is_valid_phone_number(phone):
            return fail(
                "Numéro de téléphone invalide (minimum 8 chiffres).",
                status=422,
                code="INVALID_PHONE",
            )
        conflict = User.query.filter(
            User.phone_number == phone, User.id != user.id
        ).first()
        if conflict:
            return fail(
                "Ce numéro est déjà utilisé par un autre compte.",
                status=409,
                code="PHONE_EXISTS",
            )
        if phone != user.phone_number:
            # Le numéro est l'identifiant de connexion : il ne change qu'avec
            # le code OTP envoyé au nouveau numéro (/api/auth/otp/send).
            if not _consume_otp(phone, str(data.get("otpCode") or "").strip()):
                return fail(
                    "Confirmez le nouveau numéro avec le code reçu par WhatsApp.",
                    status=403,
                    code="PHONE_REQUIRES_OTP",
                )
        user.phone_number = phone

    if "email" in data:
        email = str(data["email"] or "").strip().lower()
        if email:
            if "@" not in email:
                return fail("Email invalide.", status=422, code="INVALID_EMAIL")
            conflict = User.query.filter(
                User.email == email, User.id != user.id
            ).first()
            if conflict:
                return fail(
                    "Cet email est déjà utilisé par un autre compte.",
                    status=409,
                    code="EMAIL_EXISTS",
                )
            user.email = email
        else:
            user.email = None

    if "language" in data:
        lang = str(data["language"] or "fr").strip()[:10]
        if lang:
            user.language = lang

    if "notificationsEnabled" in data:
        user.notifications_enabled = bool(data["notificationsEnabled"])

    db.session.commit()
    return ok(
        data=user.to_dict(include_driver=True),
        message="Profil mis à jour.",
    )


@users_bp.post("/me/avatar")
@auth_required
def upload_avatar():
    user: User = g.current_user
    file = request.files.get("avatar") or request.files.get("file")
    if not file:
        return fail("Aucun fichier image fourni.", status=422, code="MISSING_FILE")

    old_path = user.photo_path
    try:
        rel_path, public_url = save_uploaded_file(
            file, subdir=f"users/{user.id}", prefix="avatar"
        )
    except ValueError as exc:
        return fail(str(exc), status=422, code="INVALID_FILE")

    user.photo_path = rel_path
    user.photo_url = public_url
    db.session.commit()

    if old_path and old_path != rel_path:
        delete_stored_file(old_path)

    return ok(
        data={"photoPath": rel_path, "photoUrl": public_url, "user": user.to_dict()},
        message="Photo de profil mise à jour.",
    )


@users_bp.delete("/me/avatar")
@auth_required
def delete_avatar():
    user: User = g.current_user
    old_path = user.photo_path
    user.photo_path = None
    user.photo_url = None
    db.session.commit()
    delete_stored_file(old_path)
    return ok(data=user.to_dict(), message="Photo de profil supprimée.")


@users_bp.delete("/me")
@auth_required
def delete_my_account():
    user: User = g.current_user
    active_conditions = [Ride.client_id == user.id]
    if user.driver_profile:
        active_conditions.append(Ride.driver_id == user.driver_profile.id)
    active_ride = Ride.query.filter(
        Ride.status.in_(list(ACTIVE_RIDE_STATUSES)),
        or_(*active_conditions),
    ).first()
    if active_ride:
        return fail(
            "La suppression est indisponible pendant une course active.",
            status=409,
            code="ACTIVE_RIDE_EXISTS",
            details={"activeRideId": active_ride.id},
        )

    driver = user.driver_profile
    old_phone = user.phone_number
    old_photo = user.photo_path
    files_to_delete = [old_photo]
    if old_phone:
        OtpCode.query.filter_by(phone_number=old_phone).delete()
    DeviceToken.query.filter_by(user_id=user.id).delete()
    Notification.query.filter_by(user_id=user.id).delete()
    RideMessage.query.filter_by(sender_user_id=user.id).delete()
    RideBenefit.query.filter_by(user_id=user.id, status="reserved").update(
        {"status": "released"}
    )
    referral_code = ReferralCode.query.filter_by(user_id=user.id).first()
    if referral_code:
        referral_code.is_active = False

    if driver:
        WalletTransaction.query.filter_by(driver_id=driver.id).update(
            {"phone_number": None}
        )
        for document in list(driver.documents):
            files_to_delete.append(document.file_path)
            db.session.delete(document)
        driver.is_available = False
        driver.latitude = None
        driver.longitude = None
        driver.last_location_at = None
        driver.brand = ""
        driver.model = ""
        driver.color = ""
        driver.plate = ""
        driver.verification_status = "pending"
        for vehicle in driver.vehicles:
            vehicle.is_active = False
            vehicle.brand = ""
            vehicle.model = ""
            vehicle.color = ""
            vehicle.plate = f"deleted-{vehicle.id[:8]}"
            vehicle.verification_status = "pending"

        for ride in Ride.query.filter_by(driver_id=driver.id).all():
            ride.driver_name = "Compte supprimé"
            ride.driver_phone = None
            ride.driver_car = None
            ride.driver_plate = None
            ride.driver_photo_url = None
        for offer in RideOffer.query.filter_by(driver_id=driver.id).all():
            offer.driver_name = "Compte supprimé"
            offer.car = ""
            offer.plate = ""
            offer.photo_url = None

    user.is_active = False
    user.role = "deleted"
    user.phone_number = None
    user.email = None
    user.password_hash = None
    user.first_name = "Compte"
    user.last_name = "supprimé"
    user.photo_path = None
    user.photo_url = None
    user.notifications_enabled = False
    db.session.commit()
    for path in files_to_delete:
        delete_stored_file(path)
    disconnect_user_sessions(user.id)
    return ok(
        message="Compte désactivé et données personnelles anonymisées. Les transactions sont conservées."
    )


@users_bp.get("/me/rides")
@auth_required
def get_my_rides():
    page = max(1, request.args.get("page", default=1, type=int))
    per_page = min(50, max(1, request.args.get("perPage", default=20, type=int)))
    status_filter = request.args.get("status")

    query = Ride.query.filter_by(client_id=g.current_user.id)
    if status_filter:
        query = query.filter_by(status=status_filter)

    pagination = query.order_by(desc(Ride.created_at)).paginate(
        page=page, per_page=per_page, error_out=False
    )
    return ok(
        data={
            "rides": [r.to_dict() for r in pagination.items],
            "pagination": {
                "page": pagination.page,
                "perPage": pagination.per_page,
                "total": pagination.total,
                "pages": pagination.pages,
            },
        }
    )


@users_bp.get("/me/referral")
@auth_required
def get_referral_summary():
    user: User = g.current_user
    code = get_or_create_referral_code(user)
    credit_total = (
        db.session.query(func.coalesce(func.sum(UserCreditTransaction.amount), 0))
        .filter_by(user_id=user.id)
        .scalar()
    )
    reserved_credit = (
        db.session.query(func.coalesce(func.sum(RideBenefit.credit_discount), 0))
        .filter(
            RideBenefit.user_id == user.id,
            RideBenefit.status == "reserved",
        )
        .scalar()
    )
    referrals = (
        Referral.query.filter_by(referrer_id=user.id)
        .order_by(desc(Referral.created_at))
        .all()
    )
    db.session.commit()
    return ok(
        data={
            "referralCode": code.code,
            "availableCredit": max(0, int(credit_total or 0) - int(reserved_credit or 0)),
            "referrals": [
                {
                    "status": referral.status,
                    "createdAt": referral.created_at.isoformat(),
                    "rewardedAt": (
                        referral.rewarded_at.isoformat() if referral.rewarded_at else None
                    ),
                    "rewardAmount": referral.reward_amount,
                }
                for referral in referrals
            ],
        }
    )


@users_bp.get("/me/recent-destinations")
@auth_required
def get_recent_destinations():
    limit = min(10, max(1, request.args.get("limit", default=3, type=int)))
    rides = (
        Ride.query.filter_by(client_id=g.current_user.id)
        .order_by(desc(Ride.created_at))
        .limit(30)
        .all()
    )
    seen = set()
    destinations = []
    for ride in rides:
        key = ride.destination_address.strip().lower()
        if key in seen:
            continue
        seen.add(key)
        destinations.append(
            {
                "address": ride.destination_address,
                "latitude": ride.destination_lat,
                "longitude": ride.destination_lng,
                "lastRideAt": ride.created_at.isoformat() if ride.created_at else None,
            }
        )
        if len(destinations) >= limit:
            break
    return ok(data={"destinations": destinations})


@users_bp.post("/me/device-token")
@auth_required
def register_device_token():
    data = request.get_json(silent=True) or {}
    token = str(data.get("token") or "").strip()
    platform = str(data.get("platform") or "android").strip().lower()[:16]
    if not token:
        return fail("Token push requis.", status=422, code="MISSING_TOKEN")

    existing = DeviceToken.query.filter_by(token=token).first()
    if existing:
        existing.user_id = g.current_user.id
        existing.platform = platform
    else:
        db.session.add(
            DeviceToken(user_id=g.current_user.id, token=token, platform=platform)
        )
    db.session.commit()
    return ok(message="Token de notification enregistré.")
