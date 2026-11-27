"""Export centralisé de tous les modèles SQLAlchemy."""

from .chat import Notification, RideMessage
from .benefits import (
    PromoCode,
    Referral,
    ReferralCode,
    RideBenefit,
    UserCreditTransaction,
)
from .driver import Driver, DriverDocument, REQUIRED_DOCS_BY_VEHICLE
from .ride import (
    ACTIVE_RIDE_STATUSES,
    RIDE_ALLOWED_TRANSITIONS,
    Ride,
    RideOffer,
    RidePayment,
    RideRating,
)
from .user import DeviceToken, OtpCode, TokenBlocklist, User
from .vehicle import Vehicle
from .wallet import WalletTransaction

__all__ = [
    "ACTIVE_RIDE_STATUSES",
    "DeviceToken",
    "Driver",
    "DriverDocument",
    "Notification",
    "OtpCode",
    "PromoCode",
    "REQUIRED_DOCS_BY_VEHICLE",
    "Referral",
    "ReferralCode",
    "RIDE_ALLOWED_TRANSITIONS",
    "Ride",
    "RideBenefit",
    "RideMessage",
    "RideOffer",
    "RidePayment",
    "RideRating",
    "TokenBlocklist",
    "User",
    "UserCreditTransaction",
    "Vehicle",
    "WalletTransaction",
]
