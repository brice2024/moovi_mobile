"""Blueprint d'authentification (OTP téléphone, email/mot de passe, JWT, déconnexion)."""

from datetime import timedelta
from flask import Blueprint, current_app, g, request
from sqlalchemy import func
from flask_jwt_extended import (
    create_access_token,
    create_refresh_token,
    get_jwt_identity,
    jwt_required,
)

from app.extensions import db, limiter
from app.models import OtpCode, User
from app.models.user import utcnow
from app.tools.auth_helpers import (
    auth_required,
    generate_otp_code,
    hash_secret,
    revoke_current_jwt,
    revoke_refresh_token,
    verify_secret,
)
from app.tools.benefits import BenefitError, attach_referral, get_or_create_referral_code
from app.tools.geo import is_valid_phone_number, normalize_phone_number
from app.tools.responses import fail, ok
from app.tools.sms import send_otp_sms
from app.tools.waha import OtpDeliveryError

auth_bp = Blueprint("auth", __name__, url_prefix="/api/auth")
otp_send_rate_limit = limiter.shared_limit("5 per minute", scope="otp-send")

# Plafonds par numéro (en plus des limites par IP) : un attaquant réparti sur
# plusieurs IP ne peut ni harceler un numéro ni deviner un code.
OTP_SENDS_PER_HOUR = 5
OTP_FAILED_ATTEMPTS_PER_HOUR = 10


def _recent_otps(phone: str):
    return OtpCode.query.filter(
        OtpCode.phone_number == phone,
        OtpCode.created_at >= utcnow() - timedelta(hours=1),
    )


def _issue_tokens(user: User) -> dict:
    additional_claims = {"role": user.role}
    return {
        "accessToken": create_access_token(
            identity=user.id, additional_claims=additional_claims
        ),
        "refreshToken": create_refresh_token(
            identity=user.id, additional_claims=additional_claims
        ),
        "tokenType": "Bearer",
    }


def _create_and_send_otp(phone: str) -> tuple[dict | None, tuple | None]:
    now = utcnow()
    cooldown = current_app.config.get("OTP_RESEND_COOLDOWN_SECONDS", 30)
    latest = (
        OtpCode.query.filter_by(phone_number=phone, is_used=False)
        .order_by(OtpCode.created_at.desc())
        .first()
    )
    if _recent_otps(phone).count() >= OTP_SENDS_PER_HOUR:
        return None, fail(
            "Trop de codes demandés pour ce numéro. Réessayez dans une heure.",
            status=429,
            code="OTP_TOO_MANY_REQUESTS",
        )
    if latest and (now - latest.created_at).total_seconds() < cooldown:
        remaining = int(cooldown - (now - latest.created_at).total_seconds())
        return None, fail(
            f"Veuillez patienter {max(1, remaining)} s avant de redemander un code.",
            status=429,
            code="OTP_COOLDOWN",
            details={"retryAfterSeconds": max(1, remaining)},
        )

    # Invalider les anciens OTP actifs pour ce numéro
    OtpCode.query.filter_by(phone_number=phone, is_used=False).update(
        {"is_used": True}
    )

    code = generate_otp_code(6)
    ttl = current_app.config.get("OTP_EXPIRATION_SECONDS", 300)
    otp_record = OtpCode(
        phone_number=phone,
        code_hash=hash_secret(code),
        expires_at=now + timedelta(seconds=ttl),
    )
    db.session.add(otp_record)
    db.session.commit()

    try:
        sms_result = send_otp_sms(phone, code)
    except OtpDeliveryError:
        current_app.logger.exception(
            "Échec de l'envoi du code OTP via %s.",
            current_app.config.get("SMS_PROVIDER", "console"),
        )
        return None, fail(
            "Impossible d'envoyer le code OTP pour le moment.",
            status=502,
            code="OTP_DELIVERY_FAILED",
        )
    payload = {
        "phoneNumber": phone,
        "expiresInSeconds": ttl,
        "resendCooldownSeconds": cooldown,
        "delivery": sms_result,
    }
    if current_app.config.get("OTP_DEBUG_RETURN_CODE"):
        payload["debugOtp"] = code
    return payload, None


@auth_bp.post("/otp/send")
@otp_send_rate_limit
def send_otp():
    data = request.get_json(silent=True) or {}
    phone = normalize_phone_number(data.get("phoneNumber") or data.get("phone") or "")
    if not is_valid_phone_number(phone):
        return fail(
            "Numéro de téléphone invalide (format international attendu, ex: +24107123456).",
            status=422,
            code="INVALID_PHONE",
        )
    payload, err = _create_and_send_otp(phone)
    if err:
        return err
    return ok(data=payload, message="Code OTP envoyé.")


@auth_bp.post("/otp/resend")
@otp_send_rate_limit
def resend_otp():
    data = request.get_json(silent=True) or {}
    phone = normalize_phone_number(data.get("phoneNumber") or data.get("phone") or "")
    if not is_valid_phone_number(phone):
        return fail("Numéro de téléphone invalide.", status=422, code="INVALID_PHONE")
    payload, err = _create_and_send_otp(phone)
    if err:
        return err
    return ok(data=payload, message="Nouveau code OTP envoyé.")


@auth_bp.post("/otp/verify")
@limiter.limit("10 per minute")
def verify_otp():
    data = request.get_json(silent=True) or {}
    phone = normalize_phone_number(data.get("phoneNumber") or data.get("phone") or "")
    code = str(data.get("code") or data.get("otp") or "").strip()

    if not is_valid_phone_number(phone):
        return fail("Numéro de téléphone invalide.", status=422, code="INVALID_PHONE")
    if not code or len(code) != 6 or not code.isdigit():
        return fail("Le code OTP doit contenir 6 chiffres.", status=422, code="INVALID_OTP_FORMAT")

    now = utcnow()
    otp_record = (
        OtpCode.query.filter_by(phone_number=phone, is_used=False)
        .order_by(OtpCode.created_at.desc())
        .first()
    )
    if not otp_record or otp_record.expires_at < now:
        return fail(
            "Code OTP expiré ou introuvable. Demandez un nouveau code.",
            status=400,
            code="OTP_EXPIRED",
        )

    max_attempts = current_app.config.get("OTP_MAX_ATTEMPTS", 5)
    failed_last_hour = (
        _recent_otps(phone).with_entities(func.coalesce(func.sum(OtpCode.attempts), 0)).scalar()
    )
    if failed_last_hour >= OTP_FAILED_ATTEMPTS_PER_HOUR:
        return fail(
            "Trop de codes erronés pour ce numéro. Réessayez dans une heure.",
            status=429,
            code="OTP_LOCKED",
        )
    if otp_record.attempts >= max_attempts:
        otp_record.is_used = True
        db.session.commit()
        return fail(
            "Nombre maximal de tentatives dépassé. Demandez un nouveau code.",
            status=429,
            code="OTP_MAX_ATTEMPTS",
        )

    # Réserve atomiquement une tentative (requêtes parallèles comprises).
    reserved = (
        OtpCode.query.filter(
            OtpCode.id == otp_record.id,
            OtpCode.is_used.is_(False),
            OtpCode.attempts < max_attempts,
        ).update({"attempts": OtpCode.attempts + 1}, synchronize_session=False)
    )
    db.session.commit()
    if not reserved:
        return fail(
            "Nombre maximal de tentatives dépassé. Demandez un nouveau code.",
            status=429,
            code="OTP_MAX_ATTEMPTS",
        )
    db.session.refresh(otp_record)
    if not verify_secret(otp_record.code_hash, code):
        return fail(
            "Code OTP incorrect.",
            status=401,
            code="INVALID_OTP",
            details={"remainingAttempts": max(0, max_attempts - otp_record.attempts)},
        )

    # Le code est consommé ; la tentative réussie ne compte pas comme un échec.
    otp_record.is_used = True
    otp_record.attempts = max(0, otp_record.attempts - 1)

    user = User.query.filter_by(phone_number=phone).first()
    is_new_user = False
    if user is None:
        is_new_user = True
        user = User(
            phone_number=phone,
            first_name=(data.get("firstName") or "").strip(),
            last_name=(data.get("lastName") or "").strip(),
            role="passenger",
        )
        db.session.add(user)
        db.session.flush()
        try:
            attach_referral(user, data.get("referralCode"))
        except BenefitError as exc:
            db.session.rollback()
            return fail(str(exc), status=exc.status, code=exc.code)
    elif not user.is_active:
        return fail("Compte désactivé.", status=403, code="ACCOUNT_DISABLED")

    referral_code = get_or_create_referral_code(user)
    db.session.commit()
    tokens = _issue_tokens(user)
    return ok(
        data={
            **tokens,
            "isNewUser": is_new_user,
            "referralCode": referral_code.code,
            "user": user.to_dict(include_driver=True),
        },
        message="Connexion réussie.",
    )


@auth_bp.post("/register")
@limiter.limit("5 per hour")
def register_email():
    data = request.get_json(silent=True) or {}
    email = (data.get("email") or "").strip().lower()
    password = data.get("password") or ""
    fullname = (data.get("fullname") or "").strip()
    first_name = (data.get("firstName") or "").strip()
    last_name = (data.get("lastName") or "").strip()
    phone = normalize_phone_number(data.get("phoneNumber") or data.get("phone") or "")

    if not email or "@" not in email:
        return fail("Adresse email invalide.", status=422, code="INVALID_EMAIL")
    if len(password) < 6:
        return fail(
            "Le mot de passe doit contenir au moins 6 caractères.",
            status=422,
            code="WEAK_PASSWORD",
        )
    if not first_name and fullname:
        parts = fullname.split(None, 1)
        first_name = parts[0]
        last_name = parts[1] if len(parts) > 1 else last_name

    if User.query.filter_by(email=email).first():
        return fail("Un compte existe déjà avec cet email.", status=409, code="EMAIL_EXISTS")
    if phone:
        # Un numéro n'est rattaché à un compte qu'après preuve de possession
        # (code OTP) : sinon on pourrait préempter le compte d'un tiers.
        return fail(
            "Le numéro de téléphone s'ajoute par vérification OTP (/api/auth/otp/send).",
            status=422,
            code="PHONE_REQUIRES_OTP",
        )

    user = User(
        email=email,
        phone_number=None,
        password_hash=hash_secret(password),
        first_name=first_name,
        last_name=last_name,
        role="passenger",
    )
    db.session.add(user)
    db.session.flush()
    try:
        attach_referral(user, data.get("referralCode"))
    except BenefitError as exc:
        db.session.rollback()
        return fail(str(exc), status=exc.status, code=exc.code)
    referral_code = get_or_create_referral_code(user)
    db.session.commit()

    tokens = _issue_tokens(user)
    return ok(
        data={
            **tokens,
            "referralCode": referral_code.code,
            "user": user.to_dict(include_driver=True),
        },
        message="Compte créé avec succès.",
        status=201,
    )


@auth_bp.post("/login")
@limiter.limit("10 per minute")
def login_email():
    data = request.get_json(silent=True) or {}
    identifier = (
        data.get("email") or data.get("phoneNumber") or data.get("identifier") or ""
    ).strip()
    password = data.get("password") or ""

    if not identifier or not password:
        return fail(
            "Identifiant et mot de passe requis.", status=422, code="MISSING_CREDENTIALS"
        )

    if "@" in identifier:
        user = User.query.filter_by(email=identifier.lower()).first()
    else:
        phone = normalize_phone_number(identifier)
        user = User.query.filter_by(phone_number=phone).first()

    if not user or not verify_secret(user.password_hash, password):
        return fail("Identifiants incorrects.", status=401, code="INVALID_CREDENTIALS")
    if not user.is_active:
        return fail("Compte désactivé.", status=403, code="ACCOUNT_DISABLED")

    tokens = _issue_tokens(user)
    return ok(
        data={**tokens, "user": user.to_dict(include_driver=True)},
        message="Connexion réussie.",
    )


@auth_bp.post("/password/forgot")
@limiter.limit("5 per hour")
def request_password_reset():
    return fail(
        "La réinitialisation par email sera disponible après configuration du fournisseur d'envoi.",
        status=503,
        code="PASSWORD_RESET_UNAVAILABLE",
    )


@auth_bp.post("/password/reset")
@limiter.limit("5 per hour")
def reset_password():
    return fail(
        "La réinitialisation par email sera disponible après configuration du fournisseur d'envoi.",
        status=503,
        code="PASSWORD_RESET_UNAVAILABLE",
    )


@auth_bp.post("/refresh")
@jwt_required(refresh=True)
def refresh_token():
    user_id = get_jwt_identity()
    user = db.session.get(User, user_id)
    if not user or not user.is_active:
        return fail("Utilisateur introuvable.", status=401, code="UNAUTHORIZED")
    access_token = create_access_token(
        identity=user.id, additional_claims={"role": user.role}
    )
    return ok(data={"accessToken": access_token, "tokenType": "Bearer"})


@auth_bp.post("/logout")
@auth_required
def logout():
    revoke_current_jwt(user_id=g.current_user.id)
    data = request.get_json(silent=True) or {}
    revoke_refresh_token(data.get("refreshToken"), g.current_user.id)
    from app.views.realtime import disconnect_user_sessions

    disconnect_user_sessions(g.current_user.id)
    return ok(message="Déconnexion effectuée.")


@auth_bp.get("/me")
@auth_required
def auth_me():
    return ok(data=g.current_user.to_dict(include_driver=True))
