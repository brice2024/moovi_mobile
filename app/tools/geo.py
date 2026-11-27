"""Utilitaires géographiques (Haversine, ETA) et normalisation téléphonique."""

import math
import re

EARTH_RADIUS_KM = 6371.0


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Calcule la distance orthodromique en kilomètres entre deux points GPS."""
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)

    a = (
        math.sin(dphi / 2) ** 2
        + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return EARTH_RADIUS_KM * c


def bounding_box(lat: float, lng: float, radius_km: float) -> tuple[float, float, float, float]:
    """Retourne (min_lat, max_lat, min_lng, max_lng) pour pré-filtrage SQL."""
    lat_delta = radius_km / 111.0
    cos_lat = max(math.cos(math.radians(lat)), 0.01)
    lng_delta = radius_km / (111.320 * cos_lat)
    return (lat - lat_delta, lat + lat_delta, lng - lng_delta, lng + lng_delta)


def estimate_arrival_minutes(distance_km: float, speed_kmh: float = 28.0) -> int:
    """Estime le temps d'approche en minutes (minimum 1 min)."""
    if distance_km <= 0:
        return 1
    minutes = round((distance_km / speed_kmh) * 60)
    return max(1, minutes)


def normalize_phone_number(raw: str, default_country_code: str = "+241") -> str:
    """Normalise un numéro au format E.164 (par défaut Gabon +241)."""
    cleaned = re.sub(r"[\s\-\(\)\.]", "", (raw or "").strip())
    if not cleaned:
        return ""
    if cleaned.startswith("00"):
        cleaned = "+" + cleaned[2:]
    if cleaned.startswith("+"):
        digits = re.sub(r"\D", "", cleaned[1:])
        return f"+{digits}" if digits else ""

    digits = re.sub(r"\D", "", cleaned)
    if not digits:
        return ""
    # Numéro local gabonais commençant par 0 (ex: 077123456 ou 062123456)
    if digits.startswith("0") and len(digits) in {8, 9}:
        return f"{default_country_code}{digits.lstrip('0')}"
    if digits.startswith("241") and len(digits) >= 10:
        return f"+{digits}"
    if len(digits) == 8:
        return f"{default_country_code}{digits}"
    return f"+{digits}"


def is_valid_phone_number(phone: str) -> bool:
    return bool(re.fullmatch(r"\+[1-9]\d{7,14}", phone or ""))


def format_distance_text(distance_meters: int | float) -> str:
    if distance_meters < 1000:
        return f"{int(round(distance_meters))} m"
    km = distance_meters / 1000.0
    return f"{km:.1f} km".replace(".", ",")


def format_duration_text(duration_seconds: int | float) -> str:
    total_minutes = max(1, int(round(duration_seconds / 60.0)))
    hours, minutes = divmod(total_minutes, 60)
    if hours == 0:
        return f"{minutes} min"
    return f"{hours} h {minutes:02d} min"


def clean_position(lat, lng, heading=None):
    """Valide une position GPS (nombres finis, bornes terrestres).

    Retourne (lat, lng, heading) ou None si la position est invalide ;
    `heading` vaut None s'il est absent ou invalide.
    """
    import math

    try:
        lat_f, lng_f = float(lat), float(lng)
    except (TypeError, ValueError):
        return None
    if not (math.isfinite(lat_f) and math.isfinite(lng_f)):
        return None
    if not (-90 <= lat_f <= 90 and -180 <= lng_f <= 180):
        return None
    heading_f = None
    if heading is not None:
        try:
            heading_f = float(heading)
        except (TypeError, ValueError):
            heading_f = None
        if heading_f is not None and not math.isfinite(heading_f):
            heading_f = None
    return lat_f, lng_f, heading_f
