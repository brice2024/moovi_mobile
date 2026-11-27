"""Modèles utilisateurs, OTP, révocation JWT et tokens push."""

import uuid
from datetime import datetime, timezone
from app.tools.storage import public_file_url
from app.extensions import db


def utcnow() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    phone_number = db.Column(db.String(32), unique=True, nullable=True, index=True)
    email = db.Column(db.String(160), unique=True, nullable=True, index=True)
    password_hash = db.Column(db.String(255), nullable=True)

    first_name = db.Column(db.String(80), nullable=False, default="")
    last_name = db.Column(db.String(80), nullable=False, default="")
    photo_path = db.Column(db.String(255), nullable=True)
    photo_url = db.Column(db.String(512), nullable=True)

    role = db.Column(db.String(24), nullable=False, default="passenger", index=True)
    rating = db.Column(db.Float, nullable=False, default=5.0)
    rating_count = db.Column(db.Integer, nullable=False, default=0)
    rides_count = db.Column(db.Integer, nullable=False, default=0)

    language = db.Column(db.String(10), nullable=False, default="fr")
    notifications_enabled = db.Column(db.Boolean, nullable=False, default=True)
    is_active = db.Column(db.Boolean, nullable=False, default=True)

    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    driver_profile = db.relationship(
        "Driver", back_populates="user", uselist=False, cascade="all, delete-orphan"
    )
    device_tokens = db.relationship(
        "DeviceToken", back_populates="user", cascade="all, delete-orphan"
    )

    @property
    def fullname(self) -> str:
        full = f"{self.first_name} {self.last_name}".strip()
        return full or "Utilisateur"

    def to_dict(self, include_driver: bool = False) -> dict:
        data = {
            "id": self.id,
            "uid": self.id,
            "phoneNumber": self.phone_number,
            "phone": self.phone_number,
            "email": self.email or "",
            "firstName": self.first_name,
            "lastName": self.last_name,
            "fullname": self.fullname,
            "photoPath": self.photo_path,
            "photoUrl": public_file_url(self.photo_url),
            "role": self.role,
            "rating": round(float(self.rating or 0), 2),
            "ratingCount": self.rating_count,
            "ridesCount": self.rides_count,
            "language": self.language,
            "notificationsEnabled": self.notifications_enabled,
            "isActive": self.is_active,
            "isDriver": self.driver_profile is not None,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
            "updatedAt": self.updated_at.isoformat() if self.updated_at else None,
        }
        if include_driver and self.driver_profile is not None:
            data["driver"] = self.driver_profile.to_dict(include_user=False)
        return data


class OtpCode(db.Model):
    __tablename__ = "otp_codes"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    phone_number = db.Column(db.String(32), nullable=False, index=True)
    code_hash = db.Column(db.String(255), nullable=False)
    attempts = db.Column(db.Integer, nullable=False, default=0)
    is_used = db.Column(db.Boolean, nullable=False, default=False)
    expires_at = db.Column(db.DateTime, nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class TokenBlocklist(db.Model):
    __tablename__ = "token_blocklist"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    jti = db.Column(db.String(64), unique=True, nullable=False, index=True)
    token_type = db.Column(db.String(16), nullable=False, default="access")
    user_id = db.Column(db.String(36), nullable=True, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)


class DeviceToken(db.Model):
    __tablename__ = "device_tokens"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.String(36), db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token = db.Column(db.String(512), unique=True, nullable=False)
    platform = db.Column(db.String(16), nullable=False, default="android")
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    user = db.relationship("User", back_populates="device_tokens")
