"""Helpers d'authentification, OTP, mots de passe et décorateurs JWT."""

import secrets
from functools import wraps
from flask import current_app, g
from flask_jwt_extended import get_jwt, get_jwt_identity, verify_jwt_in_request
from werkzeug.security import check_password_hash, generate_password_hash

from app.extensions import db
from app.models import Driver, TokenBlocklist, User
from app.tools.responses import fail


def generate_otp_code(length: int = 6) -> str:
    return "".join(str(secrets.randbelow(10)) for _ in range(length))


def hash_secret(raw_value: str) -> str:
    return generate_password_hash(raw_value)


def verify_secret(hashed_value: str | None, raw_value: str) -> bool:
    if not hashed_value:
        return False
    return check_password_hash(hashed_value, raw_value)


def get_current_user() -> User | None:
    user_id = get_jwt_identity()
    if not user_id:
        return None
    return db.session.get(User, user_id)


def auth_required(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        verify_jwt_in_request()
        user = get_current_user()
        if not user or not user.is_active:
            return fail(
                "Utilisateur introuvable ou désactivé.",
                status=401,
                code="UNAUTHORIZED",
            )
        g.current_user = user
        return fn(*args, **kwargs)

    return wrapper


def driver_required(require_verified: bool = False):
    def decorator(fn):
        @wraps(fn)
        @auth_required
        def wrapper(*args, **kwargs):
            driver = g.current_user.driver_profile
            if driver is None:
                return fail(
                    "Profil chauffeur non enregistré.",
                    status=403,
                    code="DRIVER_NOT_REGISTERED",
                )
            must_verify = require_verified or current_app.config.get(
                "REQUIRE_DRIVER_VERIFICATION", False
            )
            if must_verify and driver.verification_status != "approved":
                return fail(
                    "Votre compte chauffeur doit être vérifié avant d'effectuer cette action.",
                    status=403,
                    code="DRIVER_NOT_VERIFIED",
                    details={"verificationStatus": driver.verification_status},
                )
            g.current_driver = driver
            return fn(*args, **kwargs)

        return wrapper

    return decorator


def driver_profile_required(fn):
    """Authentifie un chauffeur sans imposer l'approbation de son dossier."""

    @wraps(fn)
    @auth_required
    def wrapper(*args, **kwargs):
        driver = g.current_user.driver_profile
        if driver is None:
            return fail(
                "Profil chauffeur non enregistré.",
                status=403,
                code="DRIVER_NOT_REGISTERED",
            )
        g.current_driver = driver
        return fn(*args, **kwargs)

    return wrapper


def admin_required(fn):
    @wraps(fn)
    @auth_required
    def wrapper(*args, **kwargs):
        if g.current_user.role != "admin":
            return fail(
                "Accès réservé aux administrateurs.",
                status=403,
                code="FORBIDDEN",
            )
        return fn(*args, **kwargs)

    return wrapper


def configure_jwt_callbacks(jwt_manager) -> None:
    @jwt_manager.token_in_blocklist_loader
    def check_if_token_revoked(_jwt_header, jwt_payload: dict) -> bool:
        jti = jwt_payload.get("jti")
        if not jti:
            return True
        return (
            db.session.query(TokenBlocklist.id).filter_by(jti=jti).first() is not None
        )

    @jwt_manager.revoked_token_loader
    def revoked_token_response(_jwt_header, _jwt_payload):
        return fail("Session expirée ou déconnectée.", status=401, code="TOKEN_REVOKED")

    @jwt_manager.expired_token_loader
    def expired_token_response(_jwt_header, _jwt_payload):
        return fail("Jeton d'authentification expiré.", status=401, code="TOKEN_EXPIRED")

    @jwt_manager.invalid_token_loader
    def invalid_token_response(reason):
        return fail("Jeton invalide.", status=401, code="INVALID_TOKEN")

    @jwt_manager.unauthorized_loader
    def missing_token_response(reason):
        return fail(
            "Authentification requise.", status=401, code="MISSING_TOKEN"
        )


def revoke_refresh_token(raw_token: str | None, user_id: str) -> None:
    """Révoque aussi le jeton de rafraîchissement transmis à la déconnexion."""
    if not raw_token:
        return
    from flask_jwt_extended import decode_token

    try:
        payload = decode_token(raw_token, allow_expired=True)
    except Exception:
        return
    jti = payload.get("jti")
    if payload.get("type") != "refresh" or payload.get("sub") != user_id or not jti:
        return
    if db.session.query(TokenBlocklist.id).filter_by(jti=jti).first() is None:
        db.session.add(TokenBlocklist(jti=jti, token_type="refresh", user_id=user_id))
        db.session.commit()


def revoke_current_jwt(user_id: str | None = None) -> None:
    payload = get_jwt()
    jti = payload.get("jti")
    if not jti:
        return
    if db.session.query(TokenBlocklist.id).filter_by(jti=jti).first() is None:
        db.session.add(
            TokenBlocklist(
                jti=jti,
                token_type=payload.get("type", "access"),
                user_id=user_id,
            )
        )
        db.session.commit()
