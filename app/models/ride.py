"""Modèles courses, offres chauffeurs et évaluations."""

import uuid
from app.tools.storage import public_file_url
from app.extensions import db
from app.models.user import utcnow

RIDE_ALLOWED_TRANSITIONS = {
    "searching": {"accepted", "cancelled", "expired"},
    "accepted": {"driver_arrived", "cancelled"},
    "driver_arrived": {"in_progress", "cancelled"},
    "in_progress": {"completed"},
    "completed": set(),
    "cancelled": set(),
    "expired": set(),
}

ACTIVE_RIDE_STATUSES = {"searching", "accepted", "driver_arrived", "in_progress"}


class Ride(db.Model):
    __tablename__ = "rides"

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    client_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    driver_id = db.Column(
        db.String(36),
        db.ForeignKey("drivers.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )

    departure_lat = db.Column(db.Float, nullable=False)
    departure_lng = db.Column(db.Float, nullable=False)
    departure_address = db.Column(db.String(255), nullable=False)

    destination_lat = db.Column(db.Float, nullable=False)
    destination_lng = db.Column(db.Float, nullable=False)
    destination_address = db.Column(db.String(255), nullable=False)

    ride_type = db.Column(db.String(20), nullable=False, default="voiture", index=True)
    price = db.Column(db.Float, nullable=False)
    agreed_price = db.Column(db.Float, nullable=True)
    currency = db.Column(db.String(8), nullable=False, default="XAF")

    distance_meters = db.Column(db.Integer, nullable=True)
    distance_text = db.Column(db.String(64), nullable=True)
    duration_seconds = db.Column(db.Integer, nullable=True)
    duration_text = db.Column(db.String(64), nullable=True)
    polyline = db.Column(db.Text, nullable=True)

    status = db.Column(db.String(24), nullable=False, default="searching", index=True)
    cancelled_by = db.Column(db.String(24), nullable=True)
    cancel_reason = db.Column(db.String(255), nullable=True)

    # Snapshot chauffeur lors de l'acceptation
    driver_name = db.Column(db.String(120), nullable=True)
    driver_car = db.Column(db.String(120), nullable=True)
    driver_plate = db.Column(db.String(32), nullable=True)
    driver_photo_url = db.Column(db.String(512), nullable=True)
    driver_phone = db.Column(db.String(32), nullable=True)

    # Paiement & commission 15%
    is_paid = db.Column(db.Boolean, nullable=False, default=False, index=True)
    payment_method = db.Column(db.String(32), nullable=True)
    payment_provider = db.Column(db.String(64), nullable=True)
    payment_transaction_id = db.Column(db.String(128), nullable=True, index=True)
    paid_amount = db.Column(db.Float, nullable=True)
    platform_commission = db.Column(db.Float, nullable=True)
    commission_rate = db.Column(db.Float, nullable=True)
    commission_deducted = db.Column(db.Boolean, nullable=False, default=False)

    # Timestamps cycle de vie
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)
    accepted_at = db.Column(db.DateTime, nullable=True)
    driver_arrived_at = db.Column(db.DateTime, nullable=True)
    started_at = db.Column(db.DateTime, nullable=True)
    completed_at = db.Column(db.DateTime, nullable=True)
    cancelled_at = db.Column(db.DateTime, nullable=True)
    paid_at = db.Column(db.DateTime, nullable=True)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    client = db.relationship("User", foreign_keys=[client_id])
    driver = db.relationship("Driver", foreign_keys=[driver_id])
    offers = db.relationship(
        "RideOffer", back_populates="ride", cascade="all, delete-orphan"
    )
    messages = db.relationship(
        "RideMessage", back_populates="ride", cascade="all, delete-orphan"
    )
    ratings = db.relationship(
        "RideRating", back_populates="ride", cascade="all, delete-orphan"
    )
    benefit = db.relationship(
        "RideBenefit", back_populates="ride", uselist=False, cascade="all, delete-orphan"
    )

    PRIVATE_FIELDS = (
        "clientPhone", "driverPhone", "driverLocation", "paymentTransactionId",
        "paymentProvider", "promoCode", "discountAmount",
    )

    def to_dict(self, include_offers: bool = False, private: bool = True) -> dict:
        """`private=False` : vue diffusée aux chauffeurs non attribués (sans
        téléphone, position ni données de paiement)."""
        benefit_discount = (
            self.benefit.promo_discount + self.benefit.credit_discount
            if self.benefit and self.benefit.status in {"reserved", "redeemed"}
            else 0
        )
        data = {
            "id": self.id,
            "rideId": self.id,
            "clientId": self.client_id,
            "driverId": self.driver_id,
            "departure": {
                "latitude": self.departure_lat,
                "longitude": self.departure_lng,
            },
            "destination": {
                "latitude": self.destination_lat,
                "longitude": self.destination_lng,
            },
            "departureAddress": self.departure_address,
            "destinationAddress": self.destination_address,
            "rideType": self.ride_type,
            "price": self.price,
            "agreedPrice": self.agreed_price,
            "finalPrice": self.agreed_price if self.agreed_price is not None else self.price,
            "currency": self.currency,
            "distanceMeters": self.distance_meters,
            "distance": self.distance_text,
            "durationSeconds": self.duration_seconds,
            "duration": self.duration_text,
            "polyline": self.polyline,
            "status": self.status,
            "cancelledBy": self.cancelled_by,
            "cancelReason": self.cancel_reason,
            "driverName": self.driver_name,
            "driverCar": self.driver_car,
            "driverPlate": self.driver_plate,
            "driverPhotoUrl": public_file_url(self.driver_photo_url),
            "driverPhone": self.driver_phone,
            "driverRating": (
                round(float(self.driver.rating or 0), 2) if self.driver else None
            ),
            "driverRatingCount": self.driver.rating_count if self.driver else None,
            "driverLevel": self.driver.level if self.driver else None,
            "clientName": self.client.fullname if self.client else None,
            "clientPhone": self.client.phone_number if self.client else None,
            "clientPhotoUrl": public_file_url(self.client.photo_url) if self.client else None,
            "isPaid": self.is_paid,
            "paymentMethod": self.payment_method,
            "paymentProvider": self.payment_provider,
            "paymentTransactionId": self.payment_transaction_id,
            "paidAmount": self.paid_amount,
            "platformCommission": self.platform_commission,
            "commissionRate": self.commission_rate,
            "commissionDeducted": self.commission_deducted,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
            "acceptedAt": self.accepted_at.isoformat() if self.accepted_at else None,
            "driverArrivedAt": (
                self.driver_arrived_at.isoformat() if self.driver_arrived_at else None
            ),
            "startedAt": self.started_at.isoformat() if self.started_at else None,
            "completedAt": self.completed_at.isoformat() if self.completed_at else None,
            "cancelledAt": self.cancelled_at.isoformat() if self.cancelled_at else None,
            "paidAt": self.paid_at.isoformat() if self.paid_at else None,
            "promoCode": (
                self.benefit.promo_code.code
                if self.benefit
                and self.benefit.status in {"reserved", "redeemed"}
                and self.benefit.promo_code
                else None
            ),
            "discountAmount": benefit_discount,
            "amountDue": max(
                0,
                (self.agreed_price if self.agreed_price is not None else self.price)
                - benefit_discount,
            ),
        }
        if self.driver is not None:
            data["driverLocation"] = (
                {
                    "latitude": self.driver.latitude,
                    "longitude": self.driver.longitude,
                    "heading": self.driver.heading,
                }
                if self.driver.latitude is not None and self.driver.longitude is not None
                else None
            )
        if include_offers:
            data["offers"] = [o.to_dict() for o in self.offers]
        if not private:
            for key in self.PRIVATE_FIELDS:
                data.pop(key, None)
        return data


class RideOffer(db.Model):
    __tablename__ = "ride_offers"
    __table_args__ = (
        db.UniqueConstraint("ride_id", "driver_id", name="uq_ride_driver_offer"),
    )

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    ride_id = db.Column(
        db.String(36),
        db.ForeignKey("rides.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    driver_id = db.Column(
        db.String(36),
        db.ForeignKey("drivers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    driver_name = db.Column(db.String(120), nullable=False)
    rating = db.Column(db.Float, nullable=False, default=4.8)
    level = db.Column(db.String(24), nullable=False, default="Or")
    car = db.Column(db.String(120), nullable=False)
    plate = db.Column(db.String(32), nullable=False, default="")
    price = db.Column(db.Float, nullable=False)
    arrival_minutes = db.Column(db.Integer, nullable=False, default=5)
    photo_url = db.Column(db.String(512), nullable=True)
    message = db.Column(db.String(255), nullable=True)
    status = db.Column(db.String(24), nullable=False, default="pending", index=True)

    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    ride = db.relationship("Ride", back_populates="offers")
    driver = db.relationship("Driver")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "offerId": self.id,
            "rideId": self.ride_id,
            "driverId": self.driver_id,
            "driverName": self.driver_name,
            "rating": round(float(self.rating or 0), 2),
            "level": self.level,
            "car": self.car,
            "plate": self.plate,
            "price": self.price,
            "arrivalMinutes": self.arrival_minutes,
            "photoUrl": public_file_url(self.photo_url),
            "message": self.message,
            "status": self.status,
            "timestamp": self.updated_at.isoformat() if self.updated_at else None,
        }


class RideRating(db.Model):
    __tablename__ = "ride_ratings"
    __table_args__ = (
        db.UniqueConstraint("ride_id", "rater_user_id", name="uq_ride_rater"),
    )

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    ride_id = db.Column(
        db.String(36),
        db.ForeignKey("rides.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    rater_user_id = db.Column(
        db.String(36), db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    target_user_id = db.Column(
        db.String(36), db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    target_role = db.Column(db.String(16), nullable=False)  # driver | passenger
    score = db.Column(db.Integer, nullable=False)
    comment = db.Column(db.String(500), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)

    ride = db.relationship("Ride", back_populates="ratings")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "rideId": self.ride_id,
            "raterUserId": self.rater_user_id,
            "targetUserId": self.target_user_id,
            "targetRole": self.target_role,
            "score": self.score,
            "comment": self.comment,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
        }


class RidePayment(db.Model):
    """Une tentative de paiement Mobile Money (dépôt PawaPay) pour une course.

    Chaque dépôt est conservé : un paiement relancé, ou confirmé après un
    règlement en espèces, n'est jamais perdu et peut être rapproché.
    """

    __tablename__ = "ride_payments"

    id = db.Column(db.String(64), primary_key=True)  # depositId PawaPay
    ride_id = db.Column(
        db.String(36), db.ForeignKey("rides.id", ondelete="CASCADE"), nullable=False, index=True
    )
    payer_user_id = db.Column(db.String(36), nullable=False, index=True)
    amount = db.Column(db.Float, nullable=False)
    currency = db.Column(db.String(8), nullable=False, default="XAF")
    country = db.Column(db.String(8), nullable=True)
    operator_code = db.Column(db.String(40), nullable=True)
    msisdn = db.Column(db.String(32), nullable=True)
    # pending | completed | failed | duplicate (payé alors que la course l'était déjà)
    status = db.Column(db.String(16), nullable=False, default="pending", index=True)
    failure_reason = db.Column(db.String(255), nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)
    updated_at = db.Column(db.DateTime, nullable=False, default=utcnow, onupdate=utcnow)

    ride = db.relationship("Ride")

    def to_dict(self) -> dict:
        return {
            "depositId": self.id,
            "rideId": self.ride_id,
            "amount": self.amount,
            "currency": self.currency,
            "operatorCode": self.operator_code,
            "status": self.status,
            "failureReason": self.failure_reason,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
        }
