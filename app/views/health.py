"""Blueprint de santé et point d'entrée API."""

from pathlib import Path

from flask import Blueprint, current_app, send_from_directory
from sqlalchemy import text
from app.extensions import db
from app.tools.responses import fail, ok

health_bp = Blueprint("health", __name__)


@health_bp.get("/")
def index():
    return ok(
        data={
            "service": "Moovi VTC API",
            "version": "1.0.0",
            "realtime": "socket.io",
        },
        message="Bienvenue sur l'API Flask Moovi!",
    )


@health_bp.get("/api/health")
def health_check():
    try:
        db.session.execute(text("SELECT 1"))
        db_status = "up"
    except Exception:
        return fail(
            "Base de données indisponible.",
            status=503,
            code="DATABASE_UNAVAILABLE",
        )
    return ok(
        data={
            "status": "healthy",
            "database": db_status,
            "websocket": "ready",
        }
    )


_ADMIN_DIR = Path(__file__).resolve().parent.parent / "static" / "admin"


@health_bp.get("/admin")
@health_bp.get("/admin/")
@health_bp.get("/admin/<path:path>")
def admin_console(path: str = ""):
    """Back-office Vue (dossier Moovi, `npm run build:api`) servi sur /admin.

    Les fichiers existants (JS, CSS, images) sont servis tels quels ; toute
    autre adresse renvoie index.html (navigation gérée par l'application).
    """
    target = (_ADMIN_DIR / path).resolve() if path else None
    if target and target.is_file() and target.is_relative_to(_ADMIN_DIR.resolve()):
        response = send_from_directory(_ADMIN_DIR, path)
        if path.startswith("assets/") and "-" in Path(path).stem:
            response.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        return response
    response = send_from_directory(_ADMIN_DIR, "index.html")
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Frame-Options"] = "DENY"
    return response


@health_bp.get("/api/support")
def support_contacts():
    """Contacts du service client (écran Assistance de l'application)."""
    cfg = current_app.config
    return ok(data={
        "phone": cfg.get("SUPPORT_PHONE") or None,
        "whatsapp": cfg.get("SUPPORT_WHATSAPP") or None,
        "email": cfg.get("SUPPORT_EMAIL") or None,
    })
