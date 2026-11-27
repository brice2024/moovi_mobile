"""Gestion du stockage local des fichiers (remplace Firebase Storage)."""

import os
import time
import uuid
from pathlib import Path
from flask import current_app, url_for
from werkzeug.datastructures import FileStorage
from werkzeug.utils import secure_filename


def is_allowed_file(filename: str) -> bool:
    if "." not in filename:
        return False
    ext = filename.rsplit(".", 1)[1].lower()
    allowed = current_app.config.get(
        "ALLOWED_IMAGE_EXTENSIONS", {"jpg", "jpeg", "png", "webp"}
    )
    return ext in allowed


def save_uploaded_file(file: FileStorage, subdir: str, prefix: str = "file") -> tuple[str, str]:
    """Sauvegarde un fichier uploadé dans UPLOAD_FOLDER/<subdir> et retourne (relative_path, public_url)."""
    if not file or not file.filename:
        raise ValueError("Aucun fichier fourni.")

    original = secure_filename(file.filename)
    if not is_allowed_file(original):
        raise ValueError("Format de fichier non autorisé (jpg, jpeg, png, webp uniquement).")

    ext = original.rsplit(".", 1)[1].lower()
    filename = f"{prefix}_{int(time.time())}_{uuid.uuid4().hex[:8]}.{ext}"

    upload_root = Path(current_app.config["UPLOAD_FOLDER"])
    target_dir = (upload_root / subdir).resolve()
    if not str(target_dir).startswith(str(upload_root.resolve())):
        raise ValueError("Chemin de stockage invalide.")

    target_dir.mkdir(parents=True, exist_ok=True)
    target_path = target_dir / filename
    file.save(str(target_path))

    rel_path = f"{subdir.strip('/')}/{filename}".replace("\\", "/")
    # Chemin seulement : l'hôte n'est jamais repris de l'en-tête Host de
    # l'envoi (sinon un client pourrait faire pointer l'URL vers son serveur).
    public_url = url_for("files.serve_file", subpath=rel_path, _external=False)
    return rel_path, public_url


def public_file_url(stored: str | None) -> str | None:
    """URL absolue d'un fichier servi par l'API, construite au moment de la réponse.

    Les anciennes valeurs absolues sont ramenées à leur chemin. La base est
    PUBLIC_BASE_URL si configurée, sinon l'hôte de la requête en cours.
    """
    if not stored:
        return None
    from urllib.parse import urlsplit

    from flask import has_request_context, request

    parts = urlsplit(stored)
    path = parts.path + (f"?{parts.query}" if parts.query else "")
    if not path.startswith("/api/files/"):
        return stored if not parts.netloc else None
    base = (current_app.config.get("PUBLIC_BASE_URL") or "").rstrip("/")
    if not base and has_request_context():
        base = request.host_url.rstrip("/")
    return f"{base}{path}"


def delete_stored_file(rel_path: str | None) -> None:
    if not rel_path:
        return
    upload_root = Path(current_app.config["UPLOAD_FOLDER"]).resolve()
    candidate = (upload_root / rel_path).resolve()
    if str(candidate).startswith(str(upload_root)) and candidate.is_file():
        try:
            os.remove(candidate)
        except OSError:
            pass
