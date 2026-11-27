"""Blueprint proxy Google Maps (Places Autocomplete, Place Details, Routes v2 + prix)."""

from flask import Blueprint, current_app, request
from app.extensions import limiter
from app.tools.auth_helpers import auth_required
from app.tools.google_maps import compute_route, place_details, places_autocomplete
from app.tools.pricing import estimate_ride_prices
from app.tools.responses import fail, ok

maps_limit = limiter.shared_limit("60 per minute", scope="maps")
maps_bp = Blueprint("maps", __name__, url_prefix="/api/maps")


@maps_bp.get("/places/autocomplete")
@auth_required
@maps_limit
def autocomplete():
    query = (request.args.get("input") or request.args.get("q") or "").strip()
    if len(query) < 3:
        return ok(data={"status": "ZERO_RESULTS", "predictions": []})

    country = request.args.get("country", default="ga")
    language = request.args.get("language", default="fr")
    lat = request.args.get("lat", type=float)
    lng = request.args.get("lng", type=float)
    session_token = request.args.get("sessionToken")

    try:
        result = places_autocomplete(
            input_text=query,
            language=language,
            country=country,
            lat=lat,
            lng=lng,
            session_token=session_token,
        )
        return ok(data=result)
    except Exception:
        current_app.logger.exception("Erreur du service cartographique")
        return fail("Service cartographique momentanément indisponible.", status=502, code="PLACES_ERROR")


@maps_bp.get("/places/details")
@auth_required
@maps_limit
def details():
    place_id = (request.args.get("placeId") or "").strip()
    if not place_id:
        return fail("Paramètre placeId requis.", status=422, code="MISSING_PLACE_ID")

    session_token = request.args.get("sessionToken")
    try:
        result = place_details(place_id=place_id, session_token=session_token)
        return ok(data=result)
    except Exception:
        current_app.logger.exception("Erreur du service cartographique")
        return fail("Service cartographique momentanément indisponible.", status=502, code="PLACES_ERROR")


@maps_bp.post("/routes/compute")
@auth_required
@maps_limit
def route_compute():
    data = request.get_json(silent=True) or {}
    required = ["originLat", "originLng", "destinationLat", "destinationLng"]
    missing = [k for k in required if data.get(k) is None]
    if missing:
        return fail(
            f"Coordonnées manquantes: {', '.join(missing)}",
            status=422,
            code="MISSING_COORDS",
        )

    try:
        route_info = compute_route(
            origin_lat=float(data["originLat"]),
            origin_lng=float(data["originLng"]),
            dest_lat=float(data["destinationLat"]),
            dest_lng=float(data["destinationLng"]),
            travel_mode=str(data.get("travelMode") or "DRIVE").upper(),
        )
        route_info["priceEstimates"] = list(
            estimate_ride_prices(route_info["distanceKm"]).values()
        )
        return ok(data=route_info)
    except Exception:
        current_app.logger.exception("Erreur du service cartographique")
        return fail("Service cartographique momentanément indisponible.", status=502, code="ROUTES_ERROR")
