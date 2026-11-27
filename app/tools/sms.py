"""Service d'envoi de SMS OTP (console en dev, extensible en production)."""

from flask import current_app

from app.tools.waha import OtpDeliveryError, send_whatsapp_text


def send_otp_sms(phone_number: str, code: str) -> dict:
    provider = current_app.config.get("SMS_PROVIDER", "console")
    if provider == "console":
        current_app.logger.info(
            "[MOOVI OTP] Envoi du code %s vers %s", code, phone_number
        )
        return {"delivered": True, "provider": "console"}

    if provider == "waha":
        message = f"Votre code de vérification Moovi est : {code}. Il expire dans 5 minutes."
        return send_whatsapp_text(phone_number, message)

    raise OtpDeliveryError(f"Fournisseur OTP non pris en charge : {provider}.")
