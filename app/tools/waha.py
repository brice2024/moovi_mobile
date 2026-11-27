"""Envoi de messages WhatsApp via l'API WAHA."""

import re

import requests
from flask import current_app


class OtpDeliveryError(Exception):
    """Échec d'envoi d'un code à usage unique."""


def send_whatsapp_text(phone_number: str, text: str) -> dict:
    base_url = current_app.config.get("WAHA_BASE_URL", "").rstrip("/")
    api_key = current_app.config.get("WAHA_API_KEY", "")
    session = current_app.config.get("WAHA_SESSION", "default")
    timeout = current_app.config.get("WAHA_TIMEOUT_SECONDS", 10)

    if not base_url or not api_key or not session:
        raise OtpDeliveryError(
            "WAHA_BASE_URL, WAHA_API_KEY et WAHA_SESSION doivent être configurés."
        )

    phone_digits = re.sub(r"\D", "", phone_number)
    if not phone_digits:
        raise OtpDeliveryError("Le numéro destinataire WhatsApp est invalide.")

    try:
        response = requests.post(
            f"{base_url}/api/sendText",
            headers={"X-Api-Key": api_key},
            json={
                "chatId": f"{phone_digits}@c.us",
                "text": text,
                "session": session,
            },
            timeout=timeout,
        )
    except requests.RequestException as exc:
        raise OtpDeliveryError(
            f"WAHA injoignable sur {base_url} ({type(exc).__name__}) : le service est-il démarré ?"
        ) from exc

    if response.status_code >= 400:
        # Cause précise dans les journaux (session absente ou non connectée,
        # clé refusée…) ; l'utilisateur ne reçoit qu'un message générique.
        detail = response.text[:300]
        if response.status_code == 404 or "Session not found" in detail:
            hint = f"la session WAHA « {session} » n'existe pas (WAHA_SESSION)"
        elif response.status_code == 422 or "status" in detail.lower():
            hint = f"la session WAHA « {session} » n'est pas connectée à WhatsApp (QR code à scanner)"
        elif response.status_code in (401, 403):
            hint = "clé WAHA_API_KEY refusée"
        else:
            hint = f"réponse HTTP {response.status_code}"
        raise OtpDeliveryError(f"WAHA n'a pas accepté le message WhatsApp : {hint}. Détail : {detail}")

    return {"delivered": True, "provider": "waha"}
