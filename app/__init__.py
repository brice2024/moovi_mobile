"""Factory principale de l'application Flask Moovi VTC."""

import os
from pathlib import Path
import click
from flask import Flask

from app.configs import CONFIG_MAP
from app.extensions import cors, db, jwt, limiter, migrate, socketio
from app.tools.auth_helpers import configure_jwt_callbacks, hash_secret
from app.tools.responses import register_error_handlers


def create_app(config_name: str | None = None) -> Flask:
    env_name = config_name or os.getenv("APP_ENV", "development")
    config_cls = CONFIG_MAP.get(env_name, CONFIG_MAP["development"])
    app = Flask(__name__)
    app.config.from_object(config_cls)

    if env_name != "testing":
        if len(app.config.get("SECRET_KEY") or "") < 32 or len(app.config.get("JWT_SECRET_KEY") or "") < 32:
            raise RuntimeError(
                "SECRET_KEY et JWT_SECRET_KEY (32 caractères minimum) sont requis dans le .env."
            )
    if env_name == "production" and app.config.get("PAWAPAY_SIMULATE"):
        raise RuntimeError(
            "PAWAPAY_SIMULATE=true est interdit en production : tout paiement serait validé sans débit."
        )
    if app.config.get("TRUST_PROXY"):
        from werkzeug.middleware.proxy_fix import ProxyFix

        app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)

    @app.after_request
    def _security_headers(response):
        response.headers.setdefault("X-Content-Type-Options", "nosniff")
        response.headers.setdefault("Referrer-Policy", "no-referrer")
        return response

    Path(app.config["UPLOAD_FOLDER"]).mkdir(parents=True, exist_ok=True)

    # Initialisation des extensions
    db.init_app(app)
    migrate.init_app(app, db)
    jwt.init_app(app)
    limiter.init_app(app)
    cors.init_app(
        app,
        resources={r"/*": {"origins": [
            o.strip() for o in app.config.get("CORS_ORIGINS", "*").split(",") if o.strip()
        ]}},
        supports_credentials=True,
    )
    cors_origins = app.config.get("CORS_ORIGINS", "*")
    socketio.init_app(
        app,
        cors_allowed_origins=(
            cors_origins if cors_origins == "*"
            else [o.strip() for o in cors_origins.split(",") if o.strip()]
        ),
        async_mode="threading",
        message_queue=app.config.get("SOCKETIO_MESSAGE_QUEUE"),
    )
    _configure_logging(app)

    configure_jwt_callbacks(jwt)
    register_error_handlers(app)

    # Importer les modèles pour SQLAlchemy / Flask-Migrate puis les blueprints
    with app.app_context():
        from app import models  # noqa: F401
        from app.views import register_blueprints

        register_blueprints(app)

    from app.openapi import register_openapi

    register_openapi(app)

    if app.config.get("BACKGROUND_JOBS_ENABLED", True):
        from app.tools.background_jobs import start_background_jobs

        start_background_jobs(app)

    _register_cli_commands(app)
    return app


def _configure_logging(app: Flask) -> None:
    """Journaux applicatifs en console et, hors tests, dans un fichier tournant."""
    import logging
    from logging.handlers import RotatingFileHandler

    level = getattr(logging, app.config.get("LOG_LEVEL", "INFO"), logging.INFO)
    app.logger.setLevel(level)
    folder = app.config.get("LOG_FOLDER")
    if app.testing or not folder:
        return
    log_dir = Path(folder)
    if not log_dir.is_absolute():
        log_dir = Path(__file__).resolve().parent.parent / log_dir
    log_dir.mkdir(parents=True, exist_ok=True)
    target = str(log_dir / "moovi-api.log")
    if any(getattr(h, "baseFilename", None) == target for h in app.logger.handlers):
        return
    handler = RotatingFileHandler(target, maxBytes=5 * 1024 * 1024, backupCount=5, encoding="utf-8")
    handler.setLevel(level)
    handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s [%(name)s] %(message)s"))
    app.logger.addHandler(handler)


def _register_cli_commands(app: Flask) -> None:
    @app.cli.command("init-db")
    def init_db_command():
        """Crée toutes les tables dans MySQL."""
        db.create_all()
        click.echo("Tables créées avec succès.")

    @app.cli.command("create-admin")
    @click.option("--email", required=True)
    @click.option("--password", required=True)
    @click.option("--phone", default=None)
    def create_admin_command(email: str, password: str, phone: str | None):
        """Crée un compte administrateur pour le back-office."""
        from app.models import User

        existing = User.query.filter_by(email=email.strip().lower()).first()
        if existing:
            existing.role = "admin"
            existing.password_hash = hash_secret(password)
            db.session.commit()
            click.echo(f"Administrateur mis à jour: {email}")
            return

        admin = User(
            email=email.strip().lower(),
            phone_number=phone,
            password_hash=hash_secret(password),
            first_name="Admin",
            last_name="Moovi",
            role="admin",
        )
        db.session.add(admin)
        db.session.commit()
        click.echo(f"Administrateur créé: {email}")

    @app.cli.command("seed-test-drivers")
    @click.option("--count", default=15, type=int)
    def seed_test_drivers_command(count: int):
        """Peuple la base avec des chauffeurs de démonstration autour de Libreville."""
        from app.views.admin import seed_test_drivers_in_libreville

        created = seed_test_drivers_in_libreville(count=count)
        click.echo(f"{created} chauffeurs de test créés à Libreville.")

    @app.cli.command("seed-demo-data")
    def seed_demo_data_command():
        """Ajoute des comptes et courses fictifs; refuse l'environnement production."""
        if app.config.get("APP_ENV") == "production":
            raise click.ClickException(
                "Les données de démonstration ne peuvent pas être ajoutées en production."
            )
        from app.tools.demo_data import seed_demo_data

        db.create_all()
        try:
            result = seed_demo_data()
        except ValueError as exc:
            db.session.rollback()
            raise click.ClickException(str(exc)) from exc
        click.echo(
            "Données démo ajoutées — "
            f"passagers: {result['passengersCreated']}, "
            f"chauffeurs: {result['driversCreated']}, "
            f"courses: {result['ridesCreated']}."
        )
