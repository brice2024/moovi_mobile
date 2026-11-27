"""Règles de tarification VTC, bornes et calcul de commission Moovi (15 %)."""

from flask import current_app

RIDE_TARIFFS = {
    "moto": {"base": 500, "per_km": 200, "min_price": 500, "default_price": 1000},
    "voiture": {"base": 1000, "per_km": 350, "min_price": 1000, "default_price": 2000},
    "confort": {"base": 1500, "per_km": 500, "min_price": 1500, "default_price": 3500},
}


def round_to_step(amount: float, step: int = 250) -> int:
    if step <= 0:
        return int(round(amount))
    return int(round(amount / step) * step)


def clamp_ride_price(amount: float) -> int:
    min_price = current_app.config.get("MIN_RIDE_PRICE", 500)
    max_price = current_app.config.get("MAX_RIDE_PRICE", 50000)
    step = current_app.config.get("PRICE_STEP", 250)
    rounded = round_to_step(amount, step)
    return max(min_price, min(max_price, rounded))


def estimate_ride_prices(distance_km: float | None = None) -> dict:
    """Calcule les prix recommandés pour chaque catégorie de véhicule."""
    step = current_app.config.get("PRICE_STEP", 250)
    max_price = current_app.config.get("MAX_RIDE_PRICE", 50000)
    estimates = {}
    for ride_type, rules in RIDE_TARIFFS.items():
        if distance_km is None or distance_km <= 0:
            suggested = rules["default_price"]
        else:
            raw = rules["base"] + (distance_km * rules["per_km"])
            suggested = max(rules["min_price"], min(max_price, round_to_step(raw, step)))
        estimates[ride_type] = {
            "rideType": ride_type,
            "recommendedPrice": suggested,
            "minPrice": rules["min_price"],
            "maxPrice": max_price,
            "step": step,
            "currency": "XAF",
        }
    return estimates


def calculate_commission(ride_price: float, rate: float | None = None) -> tuple[float, float]:
    effective_rate = (
        rate if rate is not None else float(current_app.config.get("COMMISSION_RATE", 0.15))
    )
    commission = round(float(ride_price) * effective_rate, 2)
    return commission, effective_rate
