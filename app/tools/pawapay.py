"""Client PawaPay Mobile Money (seul prestataire de paiement de Moovi).

Seuls les opérateurs dont les dépôts sont activés sur le compte PawaPay sont
listés. Les courses passager se règlent au Gabon (AIRTEL_GAB, MOOV_GAB).
"""

import re
import uuid
from datetime import datetime, timezone
import requests
from flask import current_app


class PawaPayRejected(Exception):
    """Dépôt refusé par PawaPay dès sa création (montant, numéro, opérateur…)."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason

# Opérateurs activés pour les dépôts sur le compte PawaPay (vérifié via
# /active-conf), limités aux pays en franc CFA (XAF) : portefeuilles et courses
# sont tenus en XAF, un dépôt dans une autre devise serait crédité au mauvais taux.
PAWAPAY_COUNTRIES = [
    {
        "code": "GAB",
        "name": "Gabon",
        "dialCode": "+241",
        "currency": "XAF",
        "suggestedAmounts": [
            2000,
            5000,
            10000,
            20000
        ],
        "operators": [
            {
                "code": "AIRTEL_GAB",
                "name": "Airtel Money Gabon"
            },
            {
                "code": "MOOV_GAB",
                "name": "Moov Money Gabon"
            }
        ]
    },
    {
        "code": "CMR",
        "name": "Cameroun",
        "dialCode": "+237",
        "currency": "XAF",
        "suggestedAmounts": [
            2000,
            5000,
            10000,
            25000
        ],
        "operators": [
            {
                "code": "MTN_MOMO_CMR",
                "name": "MTN Mobile Money Cameroun"
            }
        ]
    },
    {
        "code": "COG",
        "name": "Congo-Brazzaville",
        "dialCode": "+242",
        "currency": "XAF",
        "suggestedAmounts": [
            2000,
            5000,
            10000,
            20000
        ],
        "operators": [
            {
                "code": "MTN_MOMO_COG",
                "name": "MTN MoMo Congo"
            },
            {
                "code": "AIRTEL_COG",
                "name": "Airtel Money Congo"
            }
        ]
    }
]

_COUNTRY_MAP = {c["code"]: c for c in PAWAPAY_COUNTRIES}


def get_country_config(country_code: str) -> dict | None:
    return _COUNTRY_MAP.get((country_code or "").upper())


def find_operator(country_code: str, operator_code: str) -> dict | None:
    country = get_country_config(country_code)
    if not country:
        return None
    for op in country["operators"]:
        if op["code"] == operator_code:
            return op
    return None


def detect_gabon_operator(phone_number: str) -> str:
    """Airtel (07x / 077…) ou Moov (06x / 066…) d'après le numéro gabonais."""
    digits = re.sub(r"\D", "", phone_number or "")
    if digits.startswith("241"):
        digits = digits[3:]
    digits = digits.lstrip("0")
    return "MOOV_GAB" if digits.startswith("6") else "AIRTEL_GAB"


def normalize_msisdn(phone_number: str, dial_code: str = "+241") -> str:
    digits = re.sub(r"\D", "", phone_number or "")
    dial_digits = re.sub(r"\D", "", dial_code or "")
    if not digits:
        return ""
    if digits.startswith(dial_digits):
        return digits
    if digits.startswith("0"):
        digits = digits.lstrip("0")
    return f"{dial_digits}{digits}"


def _base_url() -> str:
    if current_app.config.get("PAWAPAY_PRODUCTION"):
        return "https://api.pawapay.io"
    return "https://api.sandbox.pawapay.io"


def initiate_deposit(
    amount: float,
    currency: str,
    country_code: str,
    correspondent: str,
    phone_number: str,
    description: str = "Recharge Moovi",
    deposit_id: str | None = None,
) -> dict:
    deposit_id = deposit_id or str(uuid.uuid4())
    country_cfg = get_country_config(country_code)
    dial_code = country_cfg["dialCode"] if country_cfg else "+241"
    msisdn = normalize_msisdn(phone_number, dial_code)

    if current_app.config.get("PAWAPAY_SIMULATE", True):
        return {
            "depositId": deposit_id,
            "status": "SUBMITTED",
            "simulated": True,
            "msisdn": msisdn,
        }

    token = current_app.config.get("PAWAPAY_TOKEN")
    if not token:
        raise RuntimeError("PAWAPAY_TOKEN est requis hors simulation.")

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    payload = {
        "depositId": deposit_id,
        "amount": str(int(round(amount)) if float(amount).is_integer() else amount),
        "currency": currency,
        "country": country_code.upper(),
        "correspondent": correspondent,
        "payer": {
            "type": "MSISDN",
            "address": {"value": msisdn},
        },
        "customerTimestamp": datetime.now(timezone.utc).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "statementDescription": description[:22],
    }
    resp = requests.post(
        f"{_base_url()}/deposits", json=payload, headers=headers, timeout=15
    )
    resp.raise_for_status()
    data = resp.json()
    if str(data.get("status", "")).upper() in {"REJECTED", "DUPLICATE_IGNORED"}:
        rejection = data.get("rejectionReason") or {}
        raise PawaPayRejected(
            str(rejection.get("rejectionMessage") or rejection.get("rejectionCode") or data.get("status"))
        )
    return {
        "depositId": data.get("depositId", deposit_id),
        "status": data.get("status", "SUBMITTED"),
        "simulated": False,
        "msisdn": msisdn,
        "raw": data,
    }


def check_deposit_status(deposit_id: str) -> dict:
    if current_app.config.get("PAWAPAY_SIMULATE", True):
        return {
            "depositId": deposit_id,
            "status": "COMPLETED",
            "simulated": True,
        }

    token = current_app.config.get("PAWAPAY_TOKEN")
    if not token:
        raise RuntimeError("PAWAPAY_TOKEN est requis hors simulation.")

    headers = {
        "Authorization": f"Bearer {token}",
    }
    resp = requests.get(
        f"{_base_url()}/deposits/{deposit_id}", headers=headers, timeout=12
    )
    resp.raise_for_status()
    data = resp.json()
    record = data[0] if isinstance(data, list) and data else data
    if not isinstance(record, dict) or not record:
        # Dépôt inconnu de PawaPay (jamais créé) : statut final.
        return {"depositId": deposit_id, "status": "NOT_FOUND", "simulated": False, "raw": data}
    failure = record.get("failureReason") or {}
    return {
        "failureReason": failure.get("failureMessage") or failure.get("failureCode")
        if isinstance(failure, dict) else None,
        "depositId": record.get("depositId", deposit_id),
        "status": record.get("status", "SUBMITTED"),
        "simulated": False,
        "raw": record,
    }
