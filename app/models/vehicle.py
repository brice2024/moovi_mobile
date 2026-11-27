"""Véhicules enregistrés par un chauffeur."""

import uuid

from app.extensions import db
from app.models.user import utcnow


class Vehicle(db.Model):
    __tablename__ = "vehicles"
    __table_args__ = (
        db.UniqueConstraint("driver_id", "plate", name="uq_driver_vehicle_plate"),
    )

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    driver_id = db.Column(
        db.String(36),
        db.ForeignKey("drivers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    vehicle_type = db.Column(db.String(20), nullable=False)
    brand = db.Column(db.String(80), nullable=False)
    model = db.Column(db.String(80), nullable=False)
    color = db.Column(db.String(50), nullable=False)
    plate = db.Column(db.String(32), nullable=False)
    is_active = db.Column(db.Boolean, nullable=False, default=False, index=True)
    verification_status = db.Column(db.String(24), nullable=False, default="pending")
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    driver = db.relationship("Driver", back_populates="vehicles")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "driverId": self.driver_id,
            "vehicleType": self.vehicle_type,
            "brand": self.brand,
            "model": self.model,
            "color": self.color,
            "plate": self.plate,
            "isActive": self.is_active,
            "verificationStatus": self.verification_status,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
            "updatedAt": self.updated_at.isoformat() if self.updated_at else None,
        }
