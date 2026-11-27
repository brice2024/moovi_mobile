"""Extensions Flask partagées (SQLAlchemy, Migrate, JWT, CORS, SocketIO)."""

from flask_cors import CORS
from flask_limiter import Limiter
from flask_limiter.util import get_remote_address
from flask_jwt_extended import JWTManager
from flask_migrate import Migrate
from flask_socketio import SocketIO
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
migrate = Migrate()
jwt = JWTManager()
cors = CORS()
# async_mode='threading' + simple-websocket est 100% compatible Python 3.14 / Windows
socketio = SocketIO(cors_allowed_origins="*", async_mode="threading")
limiter = Limiter(key_func=get_remote_address, default_limits=[])
