"""Client proxy pour Google Places (legacy) et Google Routes v2 (computeRoutes)."""

import requests
from flask import current_app
from app.tools.geo import format_distance_text, format_duration_text


def _parse_google_duration(duration_str: str | None) -> int:
    if not duration_str:
        return 0
    cleaned = str(duration_str).strip().rstrip("s")
    try:
        return int(float(cleaned))
    except ValueError:
        return 0


def places_autocomplete(
    input_text: str,
    language: str = "fr",
    country: str = "ga",
    lat: float | None = None,
    lng: float | None = None,
    session_token: str | None = None,
) -> dict:
    api_key = current_app.config.get("GOOGLE_MAPS_API_KEY", "")
    if not api_key:
        raise RuntimeError("GOOGLE_MAPS_API_KEY non configurée côté serveur.")

    params = {
        "input": input_text,
        "language": language,
        "components": f"country:{country}",
        "key": api_key,
    }
    if session_token:
        params["sessiontoken"] = session_token
    if lat is not None and lng is not None:
        params["location"] = f"{lat},{lng}"
        params["radius"] = 30000

    resp = requests.get(
        "https://maps.googleapis.com/maps/api/place/autocomplete/json",
        params=params,
        timeout=8,
    )
    resp.raise_for_status()
    data = resp.json()
    status = data.get("status")
    if status not in {"OK", "ZERO_RESULTS"}:
        raise RuntimeError(
            data.get("error_message") or f"Erreur Google Places: {status}"
        )
    predictions = [
        {
            "placeId": item.get("place_id"),
            "description": item.get("description"),
            "mainText": item.get("structured_formatting", {}).get("main_text"),
            "secondaryText": item.get("structured_formatting", {}).get(
                "secondary_text"
            ),
        }
        for item in data.get("predictions", [])
    ]
    return {"status": status, "predictions": predictions}


def place_details(place_id: str, session_token: str | None = None) -> dict:
    api_key = current_app.config.get("GOOGLE_MAPS_API_KEY", "")
    if not api_key:
        raise RuntimeError("GOOGLE_MAPS_API_KEY non configurée côté serveur.")

    params = {
        "place_id": place_id,
        "fields": "geometry,formatted_address,name",
        "language": "fr",
        "key": api_key,
    }
    if session_token:
        params["sessiontoken"] = session_token

    resp = requests.get(
        "https://maps.googleapis.com/maps/api/place/details/json",
        params=params,
        timeout=8,
    )
    resp.raise_for_status()
    data = resp.json()
    if data.get("status") != "OK":
        raise RuntimeError(
            data.get("error_message") or f"Erreur Place Details: {data.get('status')}"
        )
    result = data.get("result", {})
    loc = result.get("geometry", {}).get("location", {})
    return {
        "placeId": place_id,
        "name": result.get("name"),
        "address": result.get("formatted_address"),
        "latitude": loc.get("lat"),
        "longitude": loc.get("lng"),
    }


def compute_route(
    origin_lat: float,
    origin_lng: float,
    dest_lat: float,
    dest_lng: float,
    travel_mode: str = "DRIVE",
) -> dict:
    api_key = current_app.config.get("GOOGLE_MAPS_API_KEY", "")
    if not api_key:
        raise RuntimeError("GOOGLE_MAPS_API_KEY non configurée côté serveur.")

    headers = {
        "Content-Type": "application/json",
        "X-Goog-Api-Key": api_key,
        "X-Goog-FieldMask": "routes.polyline.encodedPolyline,routes.distanceMeters,routes.duration",
    }
    body = {
        "origin": {
            "location": {"latLng": {"latitude": origin_lat, "longitude": origin_lng}}
        },
        "destination": {
            "location": {"latLng": {"latitude": dest_lat, "longitude": dest_lng}}
        },
        "travelMode": travel_mode,
        "routingPreference": "TRAFFIC_AWARE",
        "polylineQuality": "HIGH_QUALITY",
        "languageCode": "fr",
    }
    resp = requests.post(
        "https://routes.googleapis.com/directions/v2:computeRoutes",
        json=body,
        headers=headers,
        timeout=10,
    )
    resp.raise_for_status()
    payload = resp.json()
    routes = payload.get("routes", [])
    if not routes:
        raise RuntimeError("Aucun itinéraire trouvé.")

    route = routes[0]
    distance_meters = int(route.get("distanceMeters", 0))
    duration_seconds = _parse_google_duration(route.get("duration"))
    encoded = route.get("polyline", {}).get("encodedPolyline", "")
    return {
        "encodedPolyline": encoded,
        "distanceMeters": distance_meters,
        "distanceKm": round(distance_meters / 1000.0, 2),
        "distanceText": format_distance_text(distance_meters),
        "durationSeconds": duration_seconds,
        "durationText": format_duration_text(duration_seconds),
    }
