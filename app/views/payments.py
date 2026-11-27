"""Blueprint paiements : espèces, Mobile Money PawaPay, commission et webhooks."""

import hashlib
import hmac
import uuid
from datetime import timedelta

from flask import Blueprint, current_app, g, request

from app.extensions import db, limiter
from app.models import Driver, Referral, Ride, RidePayment, User, WalletTransaction
from app.models.user import utcnow
from app.tools.auth_helpers import auth_required, driver_required
from app.tools.benefits import (
    redeem_ride_benefit,
    reward_completed_referral,
    ride_amount_due,
)
from app.tools.commission import (
    announce_wallet_change,
    charge_ride_commission,
    credit_driver,
    ride_gross_amount,
    wallet_payload,
)
from app.tools.pawapay import (
    PAWAPAY_COUNTRIES,
    PawaPayRejected,
    check_deposit_status,
    detect_gabon_operator,
    find_operator,
    get_country_config,
    initiate_deposit,
)
from app.tools.realtime import create_and_emit_notification, emit_to_rooms
from app.tools.responses import fail, ok
from app.views.wallet import apply_completed_deposit

payments_bp = Blueprint("payments", __name__, url_prefix="/api")

# Une demande de paiement reste « en cours » tant que le passager peut encore
# la valider sur son téléphone : pas de relance ni d'espèces pendant ce délai.
PENDING_PAYMENT_WINDOW = timedelta(minutes=10)
FAILED_STATUSES = {"FAILED", "REJECTED", "CANCELLED", "NOT_FOUND"}

mobile_money_limit = limiter.limit(
    "5 per 10 minutes",
    key_func=lambda: f"momo:{getattr(g, 'current_user', None) and g.current_user.id or request.remote_addr}",
)


def _valid_webhook_signature(header_name: str, secret: str) -> bool:
    signature = request.headers.get(header_name, "").strip()
    if signature.lower().startswith("sha256="):
        signature = signature[7:]
    if len(signature) != 64 or any(
        character not in "0123456789abcdefABCDEF" for character in signature
    ):
        return False
    expected = hmac.new(
        secret.encode("utf-8"), request.get_data(cache=True), hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(signature.lower(), expected)


def _pending_payment(ride: Ride) -> RidePayment | None:
    return (
        RidePayment.query.filter(
            RidePayment.ride_id == ride.id,
            RidePayment.status == "pending",
            RidePayment.created_at >= utcnow() - PENDING_PAYMENT_WINDOW,
        )
        .order_by(RidePayment.created_at.desc())
        .first()
    )


def _settle_ride_payment(
    ride: Ride,
    payment_method: str,
    amount: float,
    provider: str,
    transaction_id: str | None = None,
) -> dict:
    """Marque la course (terminée) payée, applique remise, reversement et commission."""
    now = utcnow()
    driver = (
        db.session.query(Driver)
        .filter(Driver.id == ride.driver_id)
        .with_for_update()
        .first()
    )
    client = db.session.get(User, ride.client_id)

    gross_amount = ride_gross_amount(ride)
    # La remise ne peut jamais dépasser le prix convenu.
    discount_amount = min(redeem_ride_benefit(ride), gross_amount)

    ride.is_paid = True
    ride.payment_method = payment_method
    ride.payment_provider = provider
    ride.payment_transaction_id = transaction_id
    ride.paid_amount = amount
    ride.paid_at = now

    went_offline = False
    if driver:
        driver.rides_count += 1
        driver.total_revenue = round(float(driver.total_revenue or 0) + gross_amount, 2)
        label = "Course espèces" if payment_method == "cash" else "Course Mobile Money"
        went_offline = charge_ride_commission(ride, driver, label)
        if payment_method == "mobile_money":
            # Le passager a payé Moovi : le prix encaissé revient au chauffeur.
            credit_driver(
                driver, ride, amount, "ride_payout",
                f"Course réglée par Mobile Money ({int(amount)} XAF)",
            )
        if discount_amount:
            credit_driver(
                driver, ride, discount_amount, "promo_subsidy",
                f"Subvention Moovi pour la réduction de la course {ride.id[:8]}",
            )
        driver.recompute_level()

    if client:
        client.rides_count += 1

    referral_rewarded = reward_completed_referral(ride)
    if referral_rewarded:
        referral = Referral.query.filter_by(
            referred_user_id=ride.client_id, status="rewarded"
        ).first()
        if referral:
            for recipient_id, role in (
                (referral.referrer_id, "parrain"),
                (referral.referred_user_id, "filleul"),
            ):
                create_and_emit_notification(
                    user_id=recipient_id,
                    title="Bonus de parrainage reçu",
                    body=f"Votre bonus de parrainage de {referral.reward_amount} XAF est disponible.",
                    notif_type="referral_reward",
                    payload={"amount": referral.reward_amount, "role": role},
                )

    create_and_emit_notification(
        user_id=ride.client_id,
        title="Paiement confirmé",
        body=f"Règlement de {int(amount)} XAF confirmé pour votre course.",
        notif_type="ride_paid",
        payload={"rideId": ride.id, "amount": amount, "paymentMethod": payment_method},
    )
    if driver:
        create_and_emit_notification(
            user_id=driver.user_id,
            title="Course réglée",
            body=(
                f"Course réglée ({int(amount)} XAF"
                f"{' par Mobile Money, reversés sur votre portefeuille' if payment_method == 'mobile_money' else ''})."
            ),
            notif_type="ride_paid",
            payload={"rideId": ride.id, "commission": ride.platform_commission},
        )

    db.session.commit()

    ride_payload = ride.to_dict()
    emit_to_rooms(
        "ride:paid",
        ride_payload,
        ride_id=ride.id,
        user_ids=[ride.client_id],
        driver_ids=[driver.id] if driver else [],
        admins=True,
    )
    if driver:
        announce_wallet_change(driver, went_offline)

    return {
        "ride": ride_payload,
        "wallet": wallet_payload(driver) if driver else None,
        "amountDue": amount,
        "grossAmount": gross_amount,
        "discountAmount": int(discount_amount),
        "referralRewarded": referral_rewarded,
    }


def finalize_ride_payment(payment: RidePayment, gateway_status: str, reason: str | None = None) -> str:
    """Applique le statut final d'un dépôt PawaPay (polling, webhook ou rapprochement).

    Idempotent. Retourne le statut local : completed, failed, duplicate ou pending.
    """
    gateway_status = (gateway_status or "").upper()
    if payment.status != "pending":
        return payment.status
    ride = db.session.query(Ride).filter(Ride.id == payment.ride_id).with_for_update().first()
    if gateway_status == "COMPLETED":
        if ride is None or ride.is_paid or ride.status != "completed":
            # Débit reçu alors que la course est déjà réglée (ou plus réglable) :
            # conservé pour remboursement manuel, jamais compté deux fois.
            payment.status = "duplicate"
            payment.failure_reason = "Course déjà réglée : à rembourser."
            db.session.commit()
            current_app.logger.warning(
                "Paiement PawaPay %s reçu pour la course %s déjà réglée : remboursement à prévoir.",
                payment.id, payment.ride_id,
            )
            if ride is not None:
                create_and_emit_notification(
                    user_id=ride.client_id,
                    title="Paiement reçu en double",
                    body=f"{int(payment.amount)} XAF reçus alors que la course était déjà réglée. "
                         "Le support Moovi va vous rembourser.",
                    notif_type="payment_duplicate",
                    payload={"rideId": ride.id, "depositId": payment.id},
                    commit=True,
                )
            return "duplicate"
        payment.status = "completed"
        _settle_ride_payment(
            ride=ride,
            payment_method="mobile_money",
            amount=payment.amount,
            provider=payment.operator_code or "pawapay",
            transaction_id=payment.id,
        )
        return "completed"
    if gateway_status in FAILED_STATUSES:
        payment.status = "failed"
        payment.failure_reason = (reason or gateway_status)[:255]
        db.session.commit()
        if ride is not None:
            emit_to_rooms(
                "ride:payment_failed",
                {"rideId": ride.id, "depositId": payment.id, "reason": payment.failure_reason},
                ride_id=ride.id,
                user_ids=[ride.client_id],
                driver_ids=[ride.driver_id] if ride.driver_id else [],
            )
        return "failed"
    return "pending"


@payments_bp.post("/rides/<string:ride_id>/pay/cash")
@driver_required()
def confirm_cash_payment(ride_id: str):
    """Le chauffeur confirme avoir encaissé la course en espèces."""
    driver: Driver = g.current_driver
    ride = (
        db.session.query(Ride)
        .filter(Ride.id == ride_id)
        .with_for_update()
        .first()
    )
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    if ride.driver_id != driver.id:
        return fail("Accès refusé.", status=403, code="FORBIDDEN")
    if ride.status != "completed":
        return fail(
            "La course doit être terminée avant d'encaisser.",
            status=409,
            code="RIDE_NOT_COMPLETED",
        )
    if ride.is_paid:
        return fail("Cette course a déjà été réglée.", status=409, code="ALREADY_PAID")
    if _pending_payment(ride):
        return fail(
            "Le passager est en train de payer par Mobile Money. Attendez sa confirmation.",
            status=409,
            code="PAYMENT_PENDING",
        )

    amount = ride_amount_due(ride)
    result = _settle_ride_payment(
        ride=ride,
        payment_method="cash",
        amount=amount,
        provider="cash",
        transaction_id=f"cash_{ride.id[:12]}",
    )
    return ok(data=result, message="Encaissement en espèces confirmé.")


@payments_bp.get("/payments/mobile-money/countries")
@auth_required
def list_mobile_money_countries():
    """Pays et opérateurs PawaPay disponibles pour régler une course."""
    if current_app.config.get("PAWAPAY_SIMULATE", True):
        environment = "simulation"
    elif current_app.config.get("PAWAPAY_PRODUCTION"):
        environment = "production"
    else:
        environment = "sandbox"
    return ok(data={"countries": PAWAPAY_COUNTRIES, "environment": environment})


@payments_bp.post("/rides/<string:ride_id>/pay/mobile-money")
@auth_required
@mobile_money_limit
def initiate_mobile_money_ride_payment(ride_id: str):
    """Le passager règle sa course terminée par Mobile Money (dépôt PawaPay)."""
    ride = (
        db.session.query(Ride).filter(Ride.id == ride_id).with_for_update().first()
    )
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    if ride.client_id != g.current_user.id:
        return fail(
            "Seul le passager peut initier le paiement Mobile Money.",
            status=403,
            code="FORBIDDEN",
        )
    if ride.is_paid:
        return fail("Cette course est déjà payée.", status=409, code="ALREADY_PAID")
    if ride.status != "completed":
        return fail(
            "Le paiement se fait à l'arrivée, une fois la course terminée.",
            status=409,
            code="RIDE_NOT_COMPLETED",
        )

    pending = _pending_payment(ride)
    if pending:
        return fail(
            "Une demande de paiement est déjà en attente sur votre téléphone.",
            status=409,
            code="PAYMENT_PENDING",
            details={"depositId": pending.id, "payment": pending.to_dict()},
        )

    amount = ride_amount_due(ride)
    if amount <= 0:
        settlement = _settle_ride_payment(
            ride=ride,
            payment_method="moovi_promo",
            amount=0,
            provider="moovi",
            transaction_id=f"moovi_{ride.id}",
        )
        return ok(data=settlement, message="Course prise en charge par Moovi.")

    data = request.get_json(silent=True) or {}
    phone_number = str(
        data.get("phoneNumber") or g.current_user.phone_number or ""
    ).strip()
    if not phone_number:
        return fail("Numéro Mobile Money requis.", status=422, code="MISSING_PHONE")

    country_code = str(data.get("country") or "GAB").upper()
    country_cfg = get_country_config(country_code)
    if not country_cfg:
        return fail("Pays non supporté pour le paiement.", status=422, code="UNSUPPORTED_COUNTRY")
    operator_code = str(data.get("operatorCode") or "").strip().upper()
    if not operator_code and country_cfg["code"] == "GAB":
        operator_code = detect_gabon_operator(phone_number)
    operator = find_operator(country_cfg["code"], operator_code)
    if not operator:
        return fail(
            "Opérateur Mobile Money invalide pour ce pays.",
            status=422,
            code="INVALID_OPERATOR",
        )

    amount = int(round(amount))  # PawaPay n'accepte pas de décimales en XAF
    deposit_id = str(uuid.uuid4())
    try:
        gw = initiate_deposit(
            amount=amount,
            currency=country_cfg["currency"],
            country_code=country_cfg["code"],
            correspondent=operator["code"],
            phone_number=phone_number,
            description="Course Moovi",
            deposit_id=deposit_id,
        )
    except PawaPayRejected as exc:
        return fail(
            f"Paiement refusé par l'opérateur : {exc.reason}",
            status=422,
            code="PAYMENT_REJECTED",
        )
    except Exception:
        current_app.logger.exception("Échec du dépôt PawaPay pour la course %s", ride.id)
        return fail(
            "Le service de paiement est momentanément indisponible. Réessayez ou payez en espèces.",
            status=502,
            code="PAWAPAY_ERROR",
        )

    payment = RidePayment(
        id=gw["depositId"],
        ride_id=ride.id,
        payer_user_id=g.current_user.id,
        amount=amount,
        currency=country_cfg["currency"],
        country=country_cfg["code"],
        operator_code=operator["code"],
        msisdn=gw.get("msisdn"),
        status="pending",
    )
    db.session.add(payment)
    ride.payment_transaction_id = payment.id
    ride.payment_provider = operator["code"]
    db.session.commit()

    return ok(
        data={
            "depositId": payment.id,
            "status": gw.get("status", "SUBMITTED"),
            "simulated": gw.get("simulated", False),
            "amount": amount,
            "currency": payment.currency,
            "operator": operator,
            "msisdn": payment.msisdn,
        },
        message="Demande de paiement envoyée. Confirmez sur votre téléphone.",
        status=201,
    )


@payments_bp.get("/payments/mobile-money/<string:deposit_id>/status")
@auth_required
def check_mobile_money_ride_payment(deposit_id: str):
    payment = db.session.get(RidePayment, deposit_id)
    if not payment:
        return fail("Paiement introuvable.", status=404, code="TX_NOT_FOUND")
    ride = db.session.get(Ride, payment.ride_id)
    me = g.current_user
    if payment.payer_user_id != me.id and not (
        ride and me.driver_profile and ride.driver_id == me.driver_profile.id
    ):
        return fail("Accès refusé.", status=403, code="FORBIDDEN")

    gw = {"simulated": False}
    if payment.status == "pending":
        try:
            gw = check_deposit_status(deposit_id)
        except Exception:
            current_app.logger.exception("Vérification PawaPay impossible pour %s", deposit_id)
            return fail(
                "Vérification du paiement momentanément impossible.",
                status=502,
                code="PAWAPAY_ERROR",
            )
        finalize_ride_payment(payment, gw.get("status"), gw.get("failureReason"))

    status = {
        "completed": "COMPLETED",
        "failed": "FAILED",
        "duplicate": "DUPLICATE",
    }.get(payment.status, str(gw.get("status") or "SUBMITTED").upper())
    ride = db.session.get(Ride, payment.ride_id)
    return ok(
        data={
            "depositId": deposit_id,
            "status": status,
            "simulated": gw.get("simulated", False),
            "payment": payment.to_dict(),
            "ride": ride.to_dict() if ride else None,
            "message": payment.failure_reason,
        }
    )


@payments_bp.post("/webhooks/pawapay")
def pawapay_webhook():
    """Webhook serveur-à-serveur PawaPay : recharges chauffeur et paiements de course."""
    data = request.get_json(silent=True)
    if not isinstance(data, dict):
        return fail("Corps webhook invalide.", status=400, code="INVALID_WEBHOOK")
    deposit_id = data.get("depositId")
    status = str(data.get("status", "")).upper()
    if not isinstance(deposit_id, str) or not deposit_id.strip():
        return fail("depositId manquant.", status=400, code="INVALID_WEBHOOK")

    simulated = current_app.config.get("PAWAPAY_SIMULATE", True)
    webhook_secret = current_app.config.get("PAWAPAY_WEBHOOK_SECRET", "")
    if not simulated and webhook_secret:
        if not _valid_webhook_signature("X-PawaPay-Signature", webhook_secret):
            return fail(
                "Signature webhook invalide.", status=401, code="INVALID_SIGNATURE"
            )
    elif not simulated and not current_app.config.get("PAWAPAY_TOKEN"):
        return fail(
            "Secret webhook ou jeton PawaPay requis.",
            status=503,
            code="WEBHOOK_NOT_CONFIGURED",
        )

    tx = (
        db.session.query(WalletTransaction)
        .filter_by(id=deposit_id)
        .with_for_update()
        .first()
    )
    payment = None if tx else db.session.get(RidePayment, deposit_id)
    if not tx and not payment:
        return ok(message="Transaction inconnue ignorée.")

    reason = data.get("failureReason")
    if not simulated and not webhook_secret:
        # Sans signature, le statut annoncé n'est jamais cru sur parole.
        try:
            verified = check_deposit_status(deposit_id)
        except Exception:
            current_app.logger.exception("Vérification PawaPay impossible pour %s", deposit_id)
            return fail(
                "Échec de vérification auprès de PawaPay.",
                status=502,
                code="PAWAPAY_ERROR",
            )
        status = str(verified.get("status", "")).upper()
        reason = verified.get("failureReason")

    if payment is not None:
        finalize_ride_payment(payment, status, reason)
        return ok(message="Webhook PawaPay traité.")

    if status == "COMPLETED":
        apply_completed_deposit(tx)
    elif status in FAILED_STATUSES and tx.status == "pending":
        tx.status = "failed"
        db.session.commit()

    return ok(message="Webhook PawaPay traité.")
