"""Blueprint portefeuille chauffeur et rechargement Mobile Money PawaPay."""

import math
import uuid
from flask import Blueprint, current_app, g, request
from sqlalchemy import desc

from app.extensions import db, limiter
from app.models import Driver, WalletTransaction
from app.models.user import utcnow
from app.tools.auth_helpers import driver_profile_required
from app.tools.pawapay import (
    PawaPayRejected,
    PAWAPAY_COUNTRIES,
    check_deposit_status,
    find_operator,
    get_country_config,
    initiate_deposit,
)
from app.tools.realtime import create_and_emit_notification, emit_to_rooms
from app.tools.responses import fail, ok

wallet_bp = Blueprint("wallet", __name__, url_prefix="/api/wallet")


def apply_completed_deposit(tx: WalletTransaction) -> bool:
    """Crédite le portefeuille chauffeur de façon atomique et idempotente. Retourne True si crédit appliqué maintenant."""
    if tx.status == "completed":
        return False

    driver = (
        db.session.query(Driver)
        .filter(Driver.id == tx.driver_id)
        .with_for_update()
        .first()
    )
    if not driver:
        return False

    now = utcnow()
    tx.status = "completed"
    tx.updated_at = now

    driver.wallet_balance = round(float(driver.wallet_balance or 0) + float(tx.amount), 2)
    driver.last_recharge_at = now
    if driver.wallet_balance >= 0:
        # Débloque seulement : la mise en ligne reste un choix du chauffeur
        # (et exige un dossier validé).
        driver.is_wallet_blocked = False

    create_and_emit_notification(
        user_id=driver.user_id,
        title="Portefeuille rechargé",
        body=f"+{int(tx.amount)} {tx.currency} crédités via {tx.operator_name or tx.operator_code}.",
        notif_type="wallet_recharged",
        payload={
            "transactionId": tx.id,
            "amount": tx.amount,
            "walletBalance": driver.wallet_balance,
        },
    )
    db.session.commit()

    wallet_payload = {
        "driverId": driver.id,
        "walletBalance": driver.wallet_balance,
        "isWalletBlocked": driver.is_wallet_blocked,
        "isAvailable": driver.is_available,
        "transaction": tx.to_dict(),
    }
    emit_to_rooms("wallet:updated", wallet_payload, user_ids=[driver.user_id], driver_ids=[driver.id])
    return True


@wallet_bp.get("/countries")
@driver_profile_required
def list_supported_countries():
    if current_app.config.get("PAWAPAY_SIMULATE", True):
        environment = "simulation"
    elif current_app.config.get("PAWAPAY_PRODUCTION"):
        environment = "production"
    else:
        environment = "sandbox"
    return ok(data={"countries": PAWAPAY_COUNTRIES, "environment": environment})


@wallet_bp.get("")
@driver_profile_required
def get_wallet():
    driver: Driver = g.current_driver
    page = max(1, request.args.get("page", default=1, type=int))
    per_page = min(50, max(1, request.args.get("perPage", default=20, type=int)))

    pagination = (
        WalletTransaction.query.filter_by(driver_id=driver.id)
        .order_by(desc(WalletTransaction.created_at))
        .paginate(page=page, per_page=per_page, error_out=False)
    )
    return ok(
        data={
            "driverId": driver.id,
            "walletBalance": round(float(driver.wallet_balance or 0), 2),
            "isWalletBlocked": driver.is_wallet_blocked,
            "isAvailable": driver.is_available,
            "lastRechargeAt": (
                driver.last_recharge_at.isoformat() if driver.last_recharge_at else None
            ),
            "transactions": [t.to_dict() for t in pagination.items],
            "pagination": {
                "page": pagination.page,
                "perPage": pagination.per_page,
                "total": pagination.total,
                "pages": pagination.pages,
            },
        }
    )


@wallet_bp.post("/recharge")
@driver_profile_required
@limiter.limit("5 per 10 minutes")
def recharge_wallet():
    driver: Driver = g.current_driver
    data = request.get_json(silent=True) or {}

    country_code = str(data.get("country") or "GAB").upper()
    operator_code = str(data.get("operatorCode") or "").strip().upper()
    phone_number = str(data.get("phoneNumber") or "").strip()

    try:
        amount = float(data.get("amount"))
    except (TypeError, ValueError):
        return fail("Montant de recharge invalide.", status=422, code="INVALID_AMOUNT")

    if not math.isfinite(amount) or amount < 100 or amount > 1_000_000:
        return fail(
            "Le montant doit être compris entre 100 et 1 000 000 XAF.",
            status=422,
            code="INVALID_AMOUNT",
        )
    amount = int(round(amount))  # PawaPay n'accepte pas de décimales en XAF

    country_cfg = get_country_config(country_code)
    if not country_cfg:
        return fail("Pays non supporté par PawaPay.", status=422, code="UNSUPPORTED_COUNTRY")

    operator = find_operator(country_code, operator_code)
    if not operator:
        return fail(
            "Opérateur Mobile Money invalide pour ce pays.",
            status=422,
            code="INVALID_OPERATOR",
        )
    if not phone_number:
        return fail("Numéro Mobile Money requis.", status=422, code="MISSING_PHONE")

    deposit_id = str(uuid.uuid4())
    try:
        gateway_resp = initiate_deposit(
            amount=amount,
            currency=country_cfg["currency"],
            country_code=country_cfg["code"],
            correspondent=operator["code"],
            phone_number=phone_number,
            description=f"Recharge Moovi {driver.id[:6]}",
            deposit_id=deposit_id,
        )
    except PawaPayRejected as exc:
        return fail(
            f"Recharge refusée par l'opérateur : {exc.reason}",
            status=422,
            code="PAYMENT_REJECTED",
        )
    except Exception:
        current_app.logger.exception("Échec de la recharge PawaPay du chauffeur %s", driver.id)
        return fail(
            "Le service de paiement est momentanément indisponible. Réessayez plus tard.",
            status=502,
            code="PAWAPAY_ERROR",
        )

    tx = WalletTransaction(
        id=gateway_resp["depositId"],
        driver_id=driver.id,
        type="deposit",
        amount=amount,
        currency=country_cfg["currency"],
        country=country_cfg["code"],
        operator_code=operator["code"],
        operator_name=f"{operator['name']} ({country_cfg['name']})",
        phone_number=gateway_resp["msisdn"],
        gateway="pawapay",
        external_reference=gateway_resp["depositId"],
        status="pending",
        description=f"Rechargement Mobile Money ({operator['name']})",
    )
    db.session.add(tx)
    db.session.commit()

    return ok(
        data={
            "depositId": tx.id,
            "gatewayStatus": gateway_resp.get("status", "SUBMITTED"),
            "simulated": gateway_resp.get("simulated", False),
            "transaction": tx.to_dict(),
        },
        message="Demande de paiement envoyée. Confirmez sur votre téléphone.",
        status=201,
    )


@wallet_bp.get("/recharge/<string:deposit_id>/status")
@driver_profile_required
def check_recharge_status(deposit_id: str):
    driver: Driver = g.current_driver
    tx = (
        db.session.query(WalletTransaction)
        .filter_by(id=deposit_id, driver_id=driver.id)
        .with_for_update()
        .first()
    )
    if not tx:
        return fail("Transaction introuvable.", status=404, code="TRANSACTION_NOT_FOUND")

    if tx.status == "completed":
        return ok(
            data={
                "depositId": tx.id,
                "status": "COMPLETED",
                "walletBalance": driver.wallet_balance,
                "isWalletBlocked": driver.is_wallet_blocked,
                "transaction": tx.to_dict(),
            }
        )

    try:
        gw = check_deposit_status(tx.id)
    except Exception:
        current_app.logger.exception("Vérification PawaPay impossible pour %s", tx.id)
        return fail(
            "Vérification du paiement momentanément impossible.",
            status=502,
            code="PAWAPAY_ERROR",
        )

    gw_status = str(gw.get("status", "SUBMITTED")).upper()
    if gw_status == "COMPLETED":
        apply_completed_deposit(tx)
        db.session.refresh(driver)
    elif gw_status in {"FAILED", "REJECTED", "CANCELLED", "NOT_FOUND"}:
        tx.status = "failed"
        db.session.commit()

    return ok(
        data={
            "depositId": tx.id,
            "status": gw_status,
            "simulated": gw.get("simulated", False),
            "walletBalance": driver.wallet_balance,
            "isWalletBlocked": driver.is_wallet_blocked,
            "transaction": tx.to_dict(),
        }
    )
