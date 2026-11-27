"""Réservation des promotions, crédits et récompenses de parrainage."""

import secrets
import string

from flask import current_app
from sqlalchemy import func

from app.extensions import db
from app.models import (
    PromoCode,
    Referral,
    ReferralCode,
    Ride,
    RideBenefit,
    User,
    UserCreditTransaction,
)
from app.models.user import utcnow


class BenefitError(Exception):
    def __init__(self, message: str, code: str, status: int = 422):
        super().__init__(message)
        self.code = code
        self.status = status


def _available_credit(user_id: str) -> int:
    earned = (
        db.session.query(func.coalesce(func.sum(UserCreditTransaction.amount), 0))
        .filter_by(user_id=user_id)
        .scalar()
    )
    reserved = (
        db.session.query(func.coalesce(func.sum(RideBenefit.credit_discount), 0))
        .filter(
            RideBenefit.user_id == user_id,
            RideBenefit.status == "reserved",
        )
        .scalar()
    )
    return max(0, int(earned or 0) - int(reserved or 0))


def reserve_ride_benefit(
    ride: Ride, user: User, promo_code_value: str | None
) -> RideBenefit | None:
    db.session.query(User).filter_by(id=user.id).with_for_update().first()
    code = str(promo_code_value or "").strip().upper()
    promo = None
    promo_discount = 0

    if code:
        promo = (
            db.session.query(PromoCode)
            .filter_by(code=code, is_active=True)
            .with_for_update()
            .first()
        )
        if not promo or (promo.expires_at and promo.expires_at <= utcnow()):
            raise BenefitError("Code promo invalide ou expiré.", "INVALID_PROMO_CODE")
        if Ride.query.filter(
            Ride.client_id == user.id,
            Ride.is_paid.is_(True),
        ).first():
            raise BenefitError(
                "Le code promo est réservé à votre première course payée.",
                "PROMO_FIRST_RIDE_ONLY",
                status=409,
            )

        prior = RideBenefit.query.filter_by(
            promo_code_id=promo.id, user_id=user.id
        ).first()
        if prior and prior.status != "released":
            raise BenefitError(
                "Ce code promo a déjà été utilisé ou réservé.",
                "PROMO_ALREADY_USED",
                status=409,
            )
        uses = RideBenefit.query.filter(
            RideBenefit.promo_code_id == promo.id,
            RideBenefit.status.in_(["reserved", "redeemed"]),
        ).count()
        if promo.max_uses is not None and uses >= promo.max_uses:
            raise BenefitError("Ce code promo a atteint sa limite.", "PROMO_LIMIT_REACHED")
        promo_discount = min(int(promo.discount_amount), int(round(ride.price)))
    elif not Ride.query.filter(
        Ride.client_id == user.id,
        Ride.is_paid.is_(True),
    ).first():
        promo_discount = min(
            int(current_app.config.get("PROMO_DISCOUNT_XAF", 500)),
            int(round(ride.price)),
        )

    remaining_fare = max(0, int(round(ride.price)) - promo_discount)
    credit_discount = min(_available_credit(user.id), remaining_fare)
    if not promo and not promo_discount and not credit_discount:
        return None

    benefit = (
        RideBenefit.query.filter_by(promo_code_id=promo.id, user_id=user.id).first()
        if promo
        else None
    )
    if benefit:
        benefit.ride_id = ride.id
        benefit.promo_discount = promo_discount
        benefit.credit_discount = credit_discount
        benefit.status = "reserved"
        benefit.redeemed_at = None
    else:
        benefit = RideBenefit(
            ride_id=ride.id,
            user_id=user.id,
            promo_code_id=promo.id if promo else None,
            promo_discount=promo_discount,
            credit_discount=credit_discount,
            status="reserved",
        )
        db.session.add(benefit)
    return benefit


def ride_amount_due(ride: Ride, fare: float | None = None) -> float:
    full_fare = float(
        fare
        if fare is not None
        else (ride.agreed_price if ride.agreed_price is not None else ride.price)
    )
    benefit = ride.benefit
    discount = (
        benefit.promo_discount + benefit.credit_discount
        if benefit and benefit.status in {"reserved", "redeemed"}
        else 0
    )
    return round(max(0.0, full_fare - discount), 2)


def ride_discount(ride: Ride) -> int:
    benefit = ride.benefit
    if not benefit or benefit.status not in {"reserved", "redeemed"}:
        return 0
    return int(benefit.promo_discount + benefit.credit_discount)


def release_ride_benefit(ride: Ride) -> None:
    if ride.benefit and ride.benefit.status == "reserved":
        ride.benefit.status = "released"


def redeem_ride_benefit(ride: Ride) -> float:
    benefit = ride.benefit
    if not benefit or benefit.status != "reserved":
        return 0.0
    benefit.status = "redeemed"
    benefit.redeemed_at = utcnow()
    if benefit.credit_discount:
        db.session.add(
            UserCreditTransaction(
                user_id=benefit.user_id,
                amount=-benefit.credit_discount,
                source="ride_payment",
                reference_key=f"ride:{ride.id}",
            )
        )
    return float(benefit.promo_discount + benefit.credit_discount)


def get_or_create_referral_code(user: User) -> ReferralCode:
    db.session.query(User).filter_by(id=user.id).with_for_update().first()
    existing = ReferralCode.query.filter_by(user_id=user.id).first()
    if existing:
        return existing
    alphabet = string.ascii_uppercase + string.digits
    for _ in range(5):
        code = "".join(secrets.choice(alphabet) for _ in range(8))
        if not ReferralCode.query.filter_by(code=code).first():
            referral_code = ReferralCode(user_id=user.id, code=code)
            db.session.add(referral_code)
            db.session.flush()
            return referral_code
    raise RuntimeError("Impossible de générer un code de parrainage unique.")


def attach_referral(user: User, code_value: str | None) -> Referral | None:
    code = str(code_value or "").strip().upper()
    if not code:
        return None
    referral_code = ReferralCode.query.filter_by(code=code, is_active=True).first()
    if not referral_code or referral_code.user_id == user.id:
        raise BenefitError("Code de parrainage invalide.", "INVALID_REFERRAL_CODE")
    if Referral.query.filter_by(referred_user_id=user.id).first():
        raise BenefitError(
            "Un code de parrainage est déjà associé à ce compte.",
            "REFERRAL_ALREADY_SET",
            status=409,
        )
    referral = Referral(
        referrer_id=referral_code.user_id,
        referred_user_id=user.id,
        reward_amount=int(current_app.config.get("REFERRAL_REWARD_XAF", 500)),
    )
    db.session.add(referral)
    return referral


def reward_completed_referral(ride: Ride) -> bool:
    if not ride.is_paid or ride.status != "completed":
        return False
    db.session.query(User).filter_by(id=ride.client_id).with_for_update().first()
    earlier_paid_ride = Ride.query.filter(
        Ride.client_id == ride.client_id,
        Ride.id != ride.id,
        Ride.is_paid.is_(True),
        Ride.status == "completed",
    ).first()
    if earlier_paid_ride:
        return False
    referral = (
        Referral.query.filter_by(
            referred_user_id=ride.client_id, status="pending"
        )
        .with_for_update()
        .first()
    )
    if not referral:
        return False

    for recipient_id, recipient_role in (
        (referral.referrer_id, "referrer"),
        (referral.referred_user_id, "referred"),
    ):
        db.session.add(
            UserCreditTransaction(
                user_id=recipient_id,
                amount=referral.reward_amount,
                source="referral_reward",
                reference_key=f"referral:{referral.id}:{recipient_role}",
            )
        )
    referral.status = "rewarded"
    referral.rewarded_at = utcnow()
    return True
