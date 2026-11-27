"""Point d'entrée de démarrage de l'application Flask + Socket.IO Moovi."""

import os
from app import create_app
from app.extensions import socketio

app = create_app()

if __name__ == "__main__":
    host = os.getenv("HOST", "0.0.0.0")
    port = int(os.getenv("PORT", "5000"))
    debug = app.config.get("DEBUG", False)
    if app.config.get("APP_ENV") == "production":
        raise SystemExit(
            "En production, lancer l'API avec gunicorn (voir README) et non avec app.py."
        )
    socketio.run(app, host=host, port=port, debug=debug, allow_unsafe_werkzeug=True)

