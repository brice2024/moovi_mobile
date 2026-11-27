"""Configuration centralisée de l'application Flask Moovi."""

import os
from datetime import timedelta
from pathlib import Path
from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parent.parent.parent
load_dotenv(BASE_DIR / ".env")


def _as_bool(value: str | None, default: bool = False) -> bool:
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _build_mysql_uri() -> str:
    url = os.getenv("DATABASE_URL")
    if url:
        return url
    user = os.getenv("MYSQL_USER", "root")
    password = os.getenv("MYSQL_PASSWORD", "")
    host = os.getenv("MYSQL_HOST", "127.0.0.1")
    port = os.getenv("MYSQL_PORT", "3306")
    db = os.getenv("MYSQL_DB", "moovi_bd")
    return f"mysql+pymysql://{user}:{password}@{host}:{port}/{db}?charset=utf8mb4"


class Config:
    """Configuration de base."""

    APP_ENV = os.getenv("APP_ENV", "development")
    SECRET_KEY = os.getenv("SECRET_KEY")
    JWT_SECRET_KEY = os.getenv("JWT_SECRET_KEY")
    # Pas de clé par défaut : sans clé, quiconque connaîtrait la valeur codée
    # en dur pourrait forger un jeton administrateur (contrôlé dans create_app).
    JWT_SECRET_KEY = JWT_SECRET_KEY or SECRET_KEY
    JWT_ACCESS_TOKEN_EXPIRES = timedelta(
        hours=int(os.getenv("JWT_ACCESS_HOURS", "24"))
    )
    JWT_REFRESH_TOKEN_EXPIRES = timedelta(
        days=int(os.getenv("JWT_REFRESH_DAYS", "30"))
    )

    SQLALCHEMY_DATABASE_URI = _build_mysql_uri()
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    SQLALCHEMY_ENGINE_OPTIONS = {
        "pool_pre_ping": True,
        "pool_recycle": 280,
    }

    # Stockage fichiers locaux
    UPLOAD_FOLDER = str(
        (BASE_DIR / os.getenv("UPLOAD_FOLDER", "uploads")).resolve()
    )
    MAX_CONTENT_LENGTH = int(os.getenv("MAX_CONTENT_LENGTH_MB", "16")) * 1024 * 1024
    ALLOWED_IMAGE_EXTENSIONS = {"jpg", "jpeg", "png", "webp"}

    # CORS & Socket.IO. L'application mobile n'envoie pas d'en-tête Origin ;
    # seuls les navigateurs sont concernés (interface /admin servie par l'API).
    CORS_ORIGINS = os.getenv("CORS_ORIGINS", "*")
    # File de messages partagée (ex. redis://localhost:6379/0) : obligatoire
    # dès que l'API tourne sur plusieurs processus.
    SOCKETIO_MESSAGE_QUEUE = os.getenv("SOCKETIO_MESSAGE_QUEUE") or None

    # Journaux : fichier tournant dans LOG_FOLDER (vide = console uniquement).
    LOG_LEVEL = os.getenv("LOG_LEVEL", "INFO").upper()
    # Derrière nginx/Caddy : lit l'IP réelle dans X-Forwarded-For (limites par IP).
    TRUST_PROXY = _as_bool(os.getenv("TRUST_PROXY"), default=False)
    # Adresse publique de l'API (ex. https://api.moovi.ga) pour les URL de fichiers.
    PUBLIC_BASE_URL = os.getenv("PUBLIC_BASE_URL", "")
    LOG_FOLDER = os.getenv("LOG_FOLDER", "logs")

    # OTP & SMS
    OTP_EXPIRATION_SECONDS = int(os.getenv("OTP_EXPIRATION_SECONDS", "300"))
    OTP_RESEND_COOLDOWN_SECONDS = int(
        os.getenv("OTP_RESEND_COOLDOWN_SECONDS", "30")
    )
    OTP_MAX_ATTEMPTS = int(os.getenv("OTP_MAX_ATTEMPTS", "5"))
    # Ne renvoyer le code OTP dans la réponse que sur demande explicite (tests).
    OTP_DEBUG_RETURN_CODE = _as_bool(os.getenv("OTP_DEBUG_RETURN_CODE"), default=False)
    SMS_PROVIDER = os.getenv("SMS_PROVIDER", "waha")
    WAHA_BASE_URL = os.getenv("WAHA_BASE_URL", "http://localhost:3000")
    WAHA_API_KEY = os.getenv("WAHA_API_KEY", "")
    WAHA_SESSION = os.getenv("WAHA_SESSION", "default")
    WAHA_TIMEOUT_SECONDS = int(os.getenv("WAHA_TIMEOUT_SECONDS", "10"))

    # Règles métier VTC
    COMMISSION_RATE = float(os.getenv("COMMISSION_RATE", "0.15"))
    MIN_RIDE_PRICE = int(os.getenv("MIN_RIDE_PRICE", "500"))
    MAX_RIDE_PRICE = int(os.getenv("MAX_RIDE_PRICE", "50000"))
    PRICE_STEP = int(os.getenv("PRICE_STEP", "250"))
    DEFAULT_SEARCH_RADIUS_KM = float(os.getenv("DEFAULT_SEARCH_RADIUS_KM", "6.0"))
    DEFAULT_WALLET_BALANCE = float(os.getenv("DEFAULT_WALLET_BALANCE", "5000.0"))
    RIDE_SEARCH_TIMEOUT_SECONDS = int(os.getenv("RIDE_SEARCH_TIMEOUT_SECONDS", "300"))
    DRIVER_DISCONNECT_GRACE_SECONDS = int(
        os.getenv("DRIVER_DISCONNECT_GRACE_SECONDS", "30")
    )
    BACKGROUND_TASK_INTERVAL_SECONDS = int(
        os.getenv("BACKGROUND_TASK_INTERVAL_SECONDS", "5")
    )
    BACKGROUND_JOBS_ENABLED = _as_bool(
        os.getenv("BACKGROUND_JOBS_ENABLED"), default=(APP_ENV != "testing")
    )
    PROMO_DISCOUNT_XAF = int(os.getenv("PROMO_DISCOUNT_XAF", "500"))
    REFERRAL_REWARD_XAF = int(os.getenv("REFERRAL_REWARD_XAF", "500"))
    REQUIRE_DRIVER_VERIFICATION = _as_bool(
        os.getenv("REQUIRE_DRIVER_VERIFICATION"), default=(APP_ENV == "production")
    )

    # Limites globales par IP; utiliser un stockage partagé (ex. Redis) en multi-worker.
    RATELIMIT_STORAGE_URI = os.getenv("RATELIMIT_STORAGE_URI", "memory://")
    RATELIMIT_HEADERS_ENABLED = True

    # Contacts affichés dans l'écran « Assistance » de l'application.
    SUPPORT_PHONE = os.getenv("SUPPORT_PHONE", "")
    SUPPORT_WHATSAPP = os.getenv("SUPPORT_WHATSAPP", "")
    SUPPORT_EMAIL = os.getenv("SUPPORT_EMAIL", "")

    # Services externes
    PAWAPAY_WEBHOOK_SECRET = os.getenv("PAWAPAY_WEBHOOK_SECRET", "")
    GOOGLE_MAPS_API_KEY = os.getenv("GOOGLE_MAPS_API_KEY", "")
    PAWAPAY_TOKEN = os.getenv("PAWAPAY_TOKEN", "")
    PAWAPAY_PRODUCTION = _as_bool(os.getenv("PAWAPAY_PRODUCTION"), default=False)
    PAWAPAY_SIMULATE = _as_bool(
        os.getenv("PAWAPAY_SIMULATE"), default=not bool(PAWAPAY_TOKEN)
    )


class DevelopmentConfig(Config):
    # Le débogueur Werkzeug permet d'exécuter du code à distance : il ne doit
    # jamais être actif sur un serveur joignable depuis le réseau.
    DEBUG = _as_bool(os.getenv("FLASK_DEBUG"), default=False)


class TestingConfig(Config):
    TESTING = True
    SECRET_KEY = "moovi-test-secret-key-at-least-32-bytes-long"
    JWT_SECRET_KEY = SECRET_KEY
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = os.getenv("TEST_DATABASE_URL", "sqlite:///:memory:")
    SQLALCHEMY_ENGINE_OPTIONS = {}
    OTP_DEBUG_RETURN_CODE = True
    SMS_PROVIDER = "console"
    PAWAPAY_SIMULATE = True
    BACKGROUND_JOBS_ENABLED = False
    REQUIRE_DRIVER_VERIFICATION = False


class ProductionConfig(Config):
    DEBUG = False
    OTP_DEBUG_RETURN_CODE = False
    REQUIRE_DRIVER_VERIFICATION = True
    PAWAPAY_SIMULATE = _as_bool(os.getenv("PAWAPAY_SIMULATE"), default=False)


CONFIG_MAP = {
    "development": DevelopmentConfig,
    "testing": TestingConfig,
    "production": ProductionConfig,
}
