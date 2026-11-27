"""Fiche « carte » d'un chauffeur pour le back-office (positions en direct)."""

from datetime import timedelta

from app.models import Driver, Ride
from app.models.user import utcnow

BUSY_STATUSES = ("accepted", "driver_arrived", "in_progress")
STALE_AFTER = timedelta(minutes=2)


def driver_map_entry(driver: Driver, ride: Ride | None = None, *, lookup_ride: bool = True) -> dict:
    """État complet d'un chauffeur sur la carte (disponible / en course / hors ligne)."""
    if ride is None and lookup_ride:
        ride = Ride.query.filter(
            Ride.driver_id == driver.id, Ride.status.in_(BUSY_STATUSES)
        ).first()
    if ride is not None:
        state = "busy"
    elif driver.is_available:
        state = "available"
    else:
        state = "offline"
    user = driver.user
    return {
        "id": driver.id,
        "name": user.fullname if user else None,
        "phoneNumber": user.phone_number if user else None,
        "vehicleType": driver.vehicle_type,
        "vehicleLabel": driver.vehicle_label,
        "plate": driver.plate,
        "latitude": driver.latitude,
        "longitude": driver.longitude,
        "heading": driver.heading,
        "state": state,
        "isAvailable": driver.is_available,
        "isWalletBlocked": driver.is_wallet_blocked,
        "verificationStatus": driver.verification_status,
        "rating": round(float(driver.rating or 0), 2),
        "lastLocationAt": driver.last_location_at.isoformat() if driver.last_location_at else None,
        "isStale": bool(driver.last_location_at and driver.last_location_at < utcnow() - STALE_AFTER),
        "ride": {"id": ride.id, "status": ride.status, "destination": ride.destination_address}
        if ride
        else None,
    }
