"""Modèle des transactions du portefeuille chauffeur."""

import uuid
from app.extensions import db
from app.models.user import utcnow


class WalletTransaction(db.Model):
    __tablename__ = "wallet_transactions"

    id = db.Column(db.String(64), primary_key=True, default=lambda: str(uuid.uuid4()))
    driver_id = db.Column(
        db.String(36),
        db.ForeignKey("drivers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    type = db.Column(db.String(24), nullable=False, index=True)  # deposit | commission | adjustment
    amount = db.Column(db.Float, nullable=False)
    currency = db.Column(db.String(8), nullable=False, default="XAF")

    country = db.Column(db.String(8), nullable=True)
    operator_code = db.Column(db.String(40), nullable=True)
    operator_name = db.Column(db.String(120), nullable=True)
    phone_number = db.Column(db.String(32), nullable=True)
    gateway = db.Column(db.String(32), nullable=True, default="pawapay")
    external_reference = db.Column(db.String(128), nullable=True, index=True)
    status = db.Column(db.String(24), nullable=False, default="pending", index=True)
    description = db.Column(db.String(255), nullable=False, default="")

    ride_id = db.Column(
        db.String(36),
        db.ForeignKey("rides.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    ride_price = db.Column(db.Float, nullable=True)
    commission_rate = db.Column(db.Float, nullable=True)

    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    driver = db.relationship("Driver", back_populates="wallet_transactions")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "driverId": self.driver_id,
            "type": self.type,
            "amount": self.amount,
            "currency": self.currency,
            "country": self.country,
            "operatorCode": self.operator_code,
            "operatorName": self.operator_name,
            "phoneNumber": self.phone_number,
            "gateway": self.gateway,
            "externalReference": self.external_reference,
            "status": self.status,
            "description": self.description,
            "rideId": self.ride_id,
            "ridePrice": self.ride_price,
            "commissionRate": self.commission_rate,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
        }
