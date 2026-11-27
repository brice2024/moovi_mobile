"""Commission Moovi et mouvements du portefeuille chauffeur liés aux courses."""

from flask import current_app

from app.extensions import db
from app.models import Driver, Ride, WalletTransaction
from app.tools.pricing import calculate_commission
from app.tools.realtime import emit_to_passengers_map, emit_to_rooms


def ride_gross_amount(ride: Ride) -> float:
    return float(ride.agreed_price if ride.agreed_price is not None else ride.price)


def charge_ride_commission(ride: Ride, driver: Driver, label: str = "Course") -> bool:
    """Prélève (une seule fois) la commission de la course sur le portefeuille.

    Appelée dès que la course est terminée, quel que soit le mode de règlement :
    un chauffeur qui n'enregistre pas l'encaissement en espèces paie quand même
    la commission. Retourne True si le chauffeur vient d'être bloqué (solde < 0).
    Le commit et les émissions temps réel restent à la charge de l'appelant
    (voir :func:`announce_wallet_change`).
    """
    if ride.commission_deducted:
        return False
    gross = ride_gross_amount(ride)
    commission, rate = calculate_commission(gross)
    db.session.add(
        WalletTransaction(
            driver_id=driver.id,
            type="commission",
            amount=-commission,
            currency="XAF",
            gateway="internal",
            status="completed",
            description=f"Commission Moovi ({int(round(rate * 100))}%) - {label}",
            ride_id=ride.id,
            ride_price=gross,
            commission_rate=rate,
        )
    )
    ride.platform_commission = commission
    ride.commission_rate = rate
    ride.commission_deducted = True
    driver.wallet_balance = round(float(driver.wallet_balance or 0) - commission, 2)
    return _block_if_negative(driver)


def credit_driver(driver: Driver, ride: Ride, amount: float, tx_type: str, description: str) -> bool:
    """Crédite le portefeuille (reversement Mobile Money, subvention promo)."""
    if amount <= 0:
        return False
    db.session.add(
        WalletTransaction(
            driver_id=driver.id,
            type=tx_type,
            amount=round(amount, 2),
            currency="XAF",
            gateway="internal",
            status="completed",
            description=description,
            ride_id=ride.id,
            ride_price=ride_gross_amount(ride),
            commission_rate=ride.commission_rate,
        )
    )
    driver.wallet_balance = round(float(driver.wallet_balance or 0) + amount, 2)
    if driver.wallet_balance >= 0 and driver.is_wallet_blocked:
        driver.is_wallet_blocked = False
    return False


def _block_if_negative(driver: Driver) -> bool:
    if float(driver.wallet_balance or 0) >= 0:
        return False
    was_available = driver.is_available
    driver.is_wallet_blocked = True
    driver.is_available = False
    return was_available


def wallet_payload(driver: Driver) -> dict:
    return {
        "driverId": driver.id,
        "walletBalance": driver.wallet_balance,
        "isWalletBlocked": driver.is_wallet_blocked,
        "isAvailable": driver.is_available,
    }


def announce_wallet_change(driver: Driver, went_offline: bool) -> None:
    """Après commit : pousse le solde et, si besoin, retire le chauffeur des rooms en ligne."""
    emit_to_rooms(
        "wallet:updated", wallet_payload(driver), user_ids=[driver.user_id], driver_ids=[driver.id]
    )
    if went_offline:
        from app.views.realtime import sync_driver_rooms

        sync_driver_rooms(driver)
        payload = {"driverId": driver.id, "isAvailable": False, "vehicleType": driver.vehicle_type}
        emit_to_rooms("driver:offline", {**payload, "reason": "wallet_blocked"}, driver_ids=[driver.id])
        emit_to_passengers_map("driver:availability_changed", payload)
        current_app.logger.info("Chauffeur %s bloqué : solde négatif.", driver.id)
