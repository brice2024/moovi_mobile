"""Utilitaires de réponses JSON standardisées et gestion globale des erreurs."""

from flask import Flask, jsonify
from werkzeug.exceptions import HTTPException


def ok(data=None, message: str | None = None, status: int = 200):
    payload = {"success": True}
    if message is not None:
        payload["message"] = message
    if data is not None:
        payload["data"] = data
    return jsonify(payload), status


def fail(message: str, status: int = 400, code: str = "BAD_REQUEST", details=None):
    payload = {
        "success": False,
        "error": {
            "code": code,
            "message": message,
        },
    }
    if details is not None:
        payload["error"]["details"] = details
    return jsonify(payload), status


def register_error_handlers(app: Flask) -> None:
    @app.errorhandler(HTTPException)
    def handle_http_exception(err: HTTPException):
        return fail(
            message=err.description or err.name,
            status=err.code or 500,
            code=err.name.upper().replace(" ", "_"),
        )

    @app.errorhandler(413)
    def handle_file_too_large(_err):
        return fail(
            message="Le fichier envoyé dépasse la taille maximale autorisée.",
            status=413,
            code="FILE_TOO_LARGE",
        )

    @app.errorhandler(Exception)
    def handle_unexpected_error(err: Exception):
        app.logger.exception("Erreur interne non gérée: %s", err)
        return fail(
            message="Une erreur interne est survenue.",
            status=500,
            code="INTERNAL_SERVER_ERROR",
        )
