"""Blueprint de service des fichiers locaux (remplace Firebase Storage)."""

from pathlib import Path

from flask import Blueprint, current_app, g, send_from_directory

from app.extensions import db
from app.models import Driver
from app.tools.auth_helpers import auth_required
from app.tools.responses import fail

files_bp = Blueprint("files", __name__, url_prefix="/api/files")


def _serve_file(subpath: str, allowed_root: str | None = None):
    upload_root = Path(current_app.config["UPLOAD_FOLDER"]).resolve()
    base = (upload_root / allowed_root).resolve() if allowed_root else upload_root
    candidate = (base / subpath).resolve()
    if (
        not candidate.is_relative_to(upload_root)
        or not candidate.is_relative_to(base)
        or not candidate.is_file()
    ):
        return fail("Fichier introuvable.", status=404, code="FILE_NOT_FOUND")
    return send_from_directory(
        str(upload_root), candidate.relative_to(upload_root).as_posix()
    )


@files_bp.get("/drivers/<string:driver_id>/<path:subpath>")
@auth_required
def serve_driver_file(driver_id: str, subpath: str):
    driver = db.session.get(Driver, driver_id)
    if not driver:
        return fail("Fichier introuvable.", status=404, code="FILE_NOT_FOUND")
    if (
        g.current_user.role != "admin"
        and (
            not g.current_user.driver_profile
            or g.current_user.driver_profile.id != driver.id
        )
    ):
        return fail("Accès refusé.", status=403, code="FORBIDDEN")
    return _serve_file(subpath, allowed_root=f"drivers/{driver.id}")


@files_bp.get("/<path:subpath>")
def serve_file(subpath: str):
    upload_root = Path(current_app.config["UPLOAD_FOLDER"]).resolve()
    candidate = (upload_root / subpath).resolve()
    drivers_root = (upload_root / "drivers").resolve()
    if candidate.is_relative_to(drivers_root):
        return fail("Fichier introuvable.", status=404, code="FILE_NOT_FOUND")
    return _serve_file(subpath)
