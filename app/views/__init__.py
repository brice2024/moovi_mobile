"""Enregistrement centralisé des blueprints et gestionnaires temps réel."""

from flask import Flask

from .admin import admin_bp
from . import admin_platform  # noqa: F401  (routes ajoutées à admin_bp)
from .auth import auth_bp
from .chat import chat_bp
from .drivers import drivers_bp
from .files import files_bp
from .health import health_bp
from .maps import maps_bp
from .notifications import notifications_bp
from .payments import payments_bp
from .rides import rides_bp
from .users import users_bp
from .wallet import wallet_bp
from . import realtime


def register_blueprints(app: Flask) -> None:
    app.register_blueprint(health_bp)
    app.register_blueprint(auth_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(drivers_bp)
    app.register_blueprint(rides_bp)
    app.register_blueprint(wallet_bp)
    app.register_blueprint(payments_bp)
    app.register_blueprint(maps_bp)
    app.register_blueprint(chat_bp)
    app.register_blueprint(notifications_bp)
    app.register_blueprint(admin_bp)
    app.register_blueprint(files_bp)
    realtime.register_socketio_handlers()
