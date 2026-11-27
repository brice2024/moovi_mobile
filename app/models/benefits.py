"""Codes promotionnels, parrainages et crédits utilisateur."""

import uuid

from app.extensions import db
from app.models.user import utcnow


class PromoCode(db.Model):
    __tablename__ = "promo_codes"

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    code = db.Column(db.String(40), nullable=False, unique=True, index=True)
    discount_amount = db.Column(db.Integer, nullable=False, default=500)
    max_uses = db.Column(db.Integer, nullable=True)
    expires_at = db.Column(db.DateTime, nullable=True)
    is_active = db.Column(db.Boolean, nullable=False, default=True, index=True)
    created_by = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "code": self.code,
            "discountAmount": self.discount_amount,
            "maxUses": self.max_uses,
            "expiresAt": self.expires_at.isoformat() if self.expires_at else None,
            "isActive": self.is_active,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
        }


class RideBenefit(db.Model):
    __tablename__ = "ride_benefits"
    __table_args__ = (
        db.UniqueConstraint("promo_code_id", "user_id", name="uq_promo_user"),
    )

    ride_id = db.Column(
        db.String(36),
        db.ForeignKey("rides.id", ondelete="CASCADE"),
        primary_key=True,
    )
    user_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    promo_code_id = db.Column(
        db.String(36),
        db.ForeignKey("promo_codes.id", ondelete="SET NULL"),
        nullable=True,
    )
    promo_discount = db.Column(db.Integer, nullable=False, default=0)
    credit_discount = db.Column(db.Integer, nullable=False, default=0)
    status = db.Column(db.String(16), nullable=False, default="reserved", index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    redeemed_at = db.Column(db.DateTime, nullable=True)

    ride = db.relationship("Ride", back_populates="benefit")
    promo_code = db.relationship("PromoCode")


class ReferralCode(db.Model):
    __tablename__ = "referral_codes"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
    )
    code = db.Column(db.String(24), nullable=False, unique=True, index=True)
    is_active = db.Column(db.Boolean, nullable=False, default=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)

    user = db.relationship("User")


class Referral(db.Model):
    __tablename__ = "referrals"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    referrer_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    referred_user_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
    )
    status = db.Column(db.String(16), nullable=False, default="pending", index=True)
    reward_amount = db.Column(db.Integer, nullable=False, default=500)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    rewarded_at = db.Column(db.DateTime, nullable=True)

    referrer = db.relationship("User", foreign_keys=[referrer_id])
    referred_user = db.relationship("User", foreign_keys=[referred_user_id])


class UserCreditTransaction(db.Model):
    __tablename__ = "user_credit_transactions"
    __table_args__ = (
        db.UniqueConstraint("user_id", "reference_key", name="uq_user_credit_reference"),
    )

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    amount = db.Column(db.Integer, nullable=False)
    source = db.Column(db.String(24), nullable=False)
    reference_key = db.Column(db.String(128), nullable=False)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)

    user = db.relationship("User")
