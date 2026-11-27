"""Back-office : supervision complète de la plateforme (utilisateurs, courses,
paiements, portefeuilles, flotte, notifications, paramètres).

Toutes les routes exigent un compte administrateur et complètent celles de
`admin.py` (validation des chauffeurs, codes promo).
"""

import math
from datetime import timedelta

from flask import current_app, g, request
from sqlalchemy import desc, func, or_

from app.extensions import db
from app.models import (
    ACTIVE_RIDE_STATUSES,
    Driver,
    Notification,
    Ride,
    RideMessage,
    RidePayment,
    RideRating,
    User,
    Vehicle,
    WalletTransaction,
)
from app.models.user import utcnow
from app.tools.auth_helpers import admin_required
from app.tools.commission import announce_wallet_change
from app.tools.realtime import (
    create_and_emit_notification,
    emit_to_driver,
    emit_to_passengers_map,
)
from app.tools.responses import fail, ok
from app.views.admin import admin_bp
from app.views.realtime import disconnect_user_sessions, sync_driver_rooms


# ── Outils ───────────────────────────────────────────────────────────────

def _page_args(default_per_page: int = 25) -> tuple[int, int]:
    page = max(1, request.args.get("page", default=1, type=int))
    per_page = min(100, max(1, request.args.get("perPage", default=default_per_page, type=int)))
    return page, per_page


def _paginate(query, serialize, key: str, default_per_page: int = 25):
    page, per_page = _page_args(default_per_page)
    pagination = query.paginate(page=page, per_page=per_page, error_out=False)
    return ok(
        data={
            key: [serialize(item) for item in pagination.items],
            "pagination": {
                "page": pagination.page,
                "perPage": pagination.per_page,
                "total": pagination.total,
                "pages": pagination.pages,
            },
        }
    )


def _like(value: str) -> str:
    return f"%{value.strip()}%"


def _user_summary(user: User | None) -> dict | None:
    if user is None:
        return None
    return {
        "id": user.id,
        "fullname": user.fullname,
        "phoneNumber": user.phone_number,
        "email": user.email,
        "role": user.role,
        "isActive": user.is_active,
    }


def _set_driver_offline(driver: Driver, reason: str) -> None:
    """Après commit : retire le chauffeur des rooms et prévient carte et appli."""
    sync_driver_rooms(driver)
    payload = {"driverId": driver.id, "isAvailable": False, "vehicleType": driver.vehicle_type}
    emit_to_driver(driver.id, "driver:offline", {**payload, "reason": reason})
    emit_to_passengers_map("driver:availability_changed", payload)


# ── Tableau de bord ──────────────────────────────────────────────────────

@admin_bp.get("/overview")
@admin_required
def admin_overview():
    """Indicateurs, séries quotidiennes et alertes pour le tableau de bord."""
    days = min(90, max(7, request.args.get("days", default=14, type=int)))
    now = utcnow()
    start = (now - timedelta(days=days - 1)).replace(hour=0, minute=0, second=0, microsecond=0)

    def count(query) -> int:
        return int(query.count())

    paid = Ride.query.filter(Ride.is_paid.is_(True))
    volume = db.session.query(func.coalesce(func.sum(Ride.paid_amount), 0.0)).filter(
        Ride.is_paid.is_(True)
    ).scalar()
    commission = db.session.query(func.coalesce(func.sum(Ride.platform_commission), 0.0)).filter(
        Ride.commission_deducted.is_(True)
    ).scalar()
    by_method = dict(
        db.session.query(Ride.payment_method, func.count(Ride.id))
        .filter(Ride.is_paid.is_(True))
        .group_by(Ride.payment_method)
        .all()
    )
    by_status = dict(db.session.query(Ride.status, func.count(Ride.id)).group_by(Ride.status).all())
    wallet_total = db.session.query(func.coalesce(func.sum(Driver.wallet_balance), 0.0)).scalar()

    # Séries quotidiennes (agrégées en Python : compatible MySQL et SQLite).
    series = {
        (start + timedelta(days=i)).date().isoformat(): {
            "date": (start + timedelta(days=i)).date().isoformat(),
            "ridesCreated": 0,
            "ridesCompleted": 0,
            "ridesCancelled": 0,
            "volume": 0.0,
            "commission": 0.0,
        }
        for i in range(days)
    }
    for created_at, status, completed_at, paid_amount, ride_commission, is_paid in (
        db.session.query(
            Ride.created_at, Ride.status, Ride.completed_at, Ride.paid_amount,
            Ride.platform_commission, Ride.is_paid,
        ).filter(Ride.created_at >= start).all()
    ):
        day = series.get(created_at.date().isoformat())
        if day is None:
            continue
        day["ridesCreated"] += 1
        if status == "completed":
            day["ridesCompleted"] += 1
            day["commission"] += float(ride_commission or 0)
            if is_paid:
                day["volume"] += float(paid_amount or 0)
        elif status in {"cancelled", "expired"}:
            day["ridesCancelled"] += 1

    stale = now - timedelta(minutes=10)
    alerts = {
        "pendingVerifications": count(Driver.query.filter_by(verification_status="pending")),
        "pendingVehicles": count(Vehicle.query.filter_by(verification_status="pending")),
        "duplicatePayments": count(RidePayment.query.filter_by(status="duplicate")),
        "stalePendingPayments": count(
            RidePayment.query.filter(RidePayment.status == "pending", RidePayment.created_at <= stale)
        ),
        "stalePendingRecharges": count(
            WalletTransaction.query.filter(
                WalletTransaction.status == "pending",
                WalletTransaction.type == "deposit",
                WalletTransaction.created_at <= stale,
            )
        ),
        "blockedDrivers": count(Driver.query.filter_by(is_wallet_blocked=True)),
        "unpaidCompletedRides": count(
            Ride.query.filter(Ride.status == "completed", Ride.is_paid.is_(False))
        ),
    }

    recent = Ride.query.order_by(desc(Ride.created_at)).limit(8).all()
    return ok(
        data={
            "generatedAt": now.isoformat(),
            "users": {
                "total": count(User.query),
                "passengers": count(User.query.filter(User.role == "passenger")),
                "suspended": count(User.query.filter(User.is_active.is_(False))),
                "newToday": count(
                    User.query.filter(User.created_at >= now.replace(hour=0, minute=0, second=0))
                ),
            },
            "drivers": {
                "total": count(Driver.query),
                "online": count(Driver.query.filter_by(is_available=True)),
                "approved": count(Driver.query.filter_by(verification_status="approved")),
                "pending": alerts["pendingVerifications"],
                "rejected": count(Driver.query.filter_by(verification_status="rejected")),
                "blocked": alerts["blockedDrivers"],
                "walletTotal": round(float(wallet_total or 0), 2),
            },
            "rides": {
                "total": count(Ride.query),
                "active": count(Ride.query.filter(Ride.status.in_(list(ACTIVE_RIDE_STATUSES)))),
                "byStatus": by_status,
                "paid": count(paid),
            },
            "money": {
                "volume": round(float(volume or 0), 2),
                "commission": round(float(commission or 0), 2),
                "byPaymentMethod": by_method,
                "currency": "XAF",
            },
            "series": list(series.values()),
            "alerts": alerts,
            "recentRides": [r.to_dict() for r in recent],
        }
    )


# ── Utilisateurs ─────────────────────────────────────────────────────────

@admin_bp.get("/users")
@admin_required
def admin_list_users():
    query = User.query
    q = (request.args.get("q") or "").strip()
    if q:
        query = query.filter(
            or_(
                User.first_name.ilike(_like(q)),
                User.last_name.ilike(_like(q)),
                User.phone_number.ilike(_like(q)),
                User.email.ilike(_like(q)),
            )
        )
    role = request.args.get("role")
    if role == "driver":
        query = query.filter(User.driver_profile.has())
    elif role == "passenger":
        query = query.filter(~User.driver_profile.has(), User.role != "admin")
    elif role == "admin":
        query = query.filter(User.role == "admin")
    status = request.args.get("status")
    if status == "active":
        query = query.filter(User.is_active.is_(True))
    elif status == "suspended":
        query = query.filter(User.is_active.is_(False))
    return _paginate(query.order_by(desc(User.created_at)), lambda u: u.to_dict(), "users")


@admin_bp.get("/users/<string:user_id>")
@admin_required
def admin_get_user(user_id: str):
    user = db.session.get(User, user_id)
    if not user:
        return fail("Utilisateur introuvable.", status=404, code="USER_NOT_FOUND")
    rides = Ride.query.filter_by(client_id=user.id).order_by(desc(Ride.created_at)).limit(30).all()
    spent = db.session.query(func.coalesce(func.sum(Ride.paid_amount), 0.0)).filter(
        Ride.client_id == user.id, Ride.is_paid.is_(True)
    ).scalar()
    return ok(
        data={
            "user": user.to_dict(include_driver=True),
            "rides": [r.to_dict() for r in rides],
            "totalSpent": round(float(spent or 0), 2),
            "ratingsReceived": [
                r.to_dict()
                for r in RideRating.query.filter_by(target_user_id=user.id)
                .order_by(desc(RideRating.created_at))
                .limit(10)
            ],
        }
    )


@admin_bp.post("/users/<string:user_id>/status")
@admin_required
def admin_set_user_status(user_id: str):
    """Suspend (isActive=false) ou réactive un compte."""
    user = db.session.get(User, user_id)
    if not user:
        return fail("Utilisateur introuvable.", status=404, code="USER_NOT_FOUND")
    data = request.get_json(silent=True) or {}
    if "isActive" not in data:
        return fail("Le champ isActive est requis.", status=422, code="MISSING_FIELD")
    active = bool(data["isActive"])
    reason = str(data.get("reason") or "").strip()[:255]
    if not active and user.id == g.current_user.id:
        return fail("Vous ne pouvez pas suspendre votre propre compte.", status=409, code="SELF_SUSPEND")
    if not active and user.role == "admin":
        return fail("Un administrateur ne peut pas être suspendu ici.", status=409, code="ADMIN_TARGET")

    driver = user.driver_profile
    if not active:
        conditions = [Ride.client_id == user.id]
        if driver:
            conditions.append(Ride.driver_id == driver.id)
        busy = Ride.query.filter(
            Ride.status.in_(["accepted", "driver_arrived", "in_progress"]), or_(*conditions)
        ).first()
        if busy:
            return fail(
                "Ce compte a une course en cours : attendez la fin ou annulez-la d'abord.",
                status=409,
                code="RIDE_IN_PROGRESS",
                details={"rideId": busy.id},
            )
    was_online = bool(driver and driver.is_available)
    user.is_active = active
    if not active and driver:
        driver.is_available = False
    if active:
        create_and_emit_notification(
            user_id=user.id,
            title="Compte réactivé",
            body="Votre compte Moovi est de nouveau actif.",
            notif_type="account_status",
        )
    db.session.commit()
    if not active:
        current_app.logger.info("Compte %s suspendu par %s : %s", user.id, g.current_user.id, reason)
        if was_online:
            _set_driver_offline(driver, "account_suspended")
        disconnect_user_sessions(user.id)
    return ok(
        data=user.to_dict(include_driver=True),
        message="Compte réactivé." if active else "Compte suspendu.",
    )


# ── Chauffeurs : actions d'exploitation ──────────────────────────────────

@admin_bp.post("/drivers/<string:driver_id>/offline")
@admin_required
def admin_force_driver_offline(driver_id: str):
    driver = db.session.get(Driver, driver_id)
    if not driver:
        return fail("Chauffeur introuvable.", status=404, code="DRIVER_NOT_FOUND")
    driver.is_available = False
    create_and_emit_notification(
        user_id=driver.user_id,
        title="Mis hors ligne",
        body="L'équipe Moovi vous a mis hors ligne.",
        notif_type="driver_offline",
    )
    db.session.commit()
    _set_driver_offline(driver, "admin")
    return ok(data=driver.to_dict(include_user=True), message="Chauffeur mis hors ligne.")


@admin_bp.post("/drivers/<string:driver_id>/wallet-adjustment")
@admin_required
def admin_adjust_wallet(driver_id: str):
    """Crédit (+) ou débit (−) manuel du portefeuille, toujours motivé."""
    driver = db.session.query(Driver).filter(Driver.id == driver_id).with_for_update().first()
    if not driver:
        return fail("Chauffeur introuvable.", status=404, code="DRIVER_NOT_FOUND")
    data = request.get_json(silent=True) or {}
    try:
        amount = float(data.get("amount"))
    except (TypeError, ValueError):
        return fail("Montant invalide.", status=422, code="INVALID_AMOUNT")
    if not math.isfinite(amount) or amount == 0 or abs(amount) > 1_000_000:
        return fail("Montant invalide (non nul, au plus 1 000 000 XAF).", status=422, code="INVALID_AMOUNT")
    reason = str(data.get("reason") or "").strip()
    if len(reason) < 3:
        return fail("Indiquez le motif de l'ajustement.", status=422, code="MISSING_REASON")
    amount = round(amount, 2)

    db.session.add(
        WalletTransaction(
            driver_id=driver.id,
            type="adjustment",
            amount=amount,
            currency="XAF",
            gateway="admin",
            status="completed",
            description=f"Ajustement Moovi : {reason}"[:255],
            external_reference=g.current_user.id,
        )
    )
    was_available = driver.is_available
    driver.wallet_balance = round(float(driver.wallet_balance or 0) + amount, 2)
    if driver.wallet_balance < 0:
        driver.is_wallet_blocked = True
        driver.is_available = False
    else:
        driver.is_wallet_blocked = False
    create_and_emit_notification(
        user_id=driver.user_id,
        title="Portefeuille ajusté",
        body=f"{'+' if amount > 0 else ''}{int(amount)} XAF : {reason}"[:500],
        notif_type="wallet_adjustment",
        payload={"amount": amount},
    )
    db.session.commit()
    announce_wallet_change(driver, was_available and not driver.is_available)
    return ok(data=driver.to_dict(include_user=True), message="Portefeuille ajusté.")


@admin_bp.get("/drivers/<string:driver_id>/transactions")
@admin_required
def admin_driver_transactions(driver_id: str):
    query = WalletTransaction.query.filter_by(driver_id=driver_id).order_by(
        desc(WalletTransaction.created_at)
    )
    return _paginate(query, lambda t: t.to_dict(), "transactions", 20)


@admin_bp.get("/drivers/<string:driver_id>/rides")
@admin_required
def admin_driver_rides(driver_id: str):
    query = Ride.query.filter_by(driver_id=driver_id).order_by(desc(Ride.created_at))
    return _paginate(query, lambda r: r.to_dict(), "rides", 20)


# ── Flotte ───────────────────────────────────────────────────────────────

@admin_bp.get("/vehicles")
@admin_required
def admin_list_vehicles():
    query = Vehicle.query
    status = request.args.get("verificationStatus")
    if status:
        query = query.filter(Vehicle.verification_status == status)
    vehicle_type = request.args.get("vehicleType")
    if vehicle_type:
        query = query.filter(Vehicle.vehicle_type == vehicle_type)
    q = (request.args.get("q") or "").strip()
    if q:
        query = query.filter(
            or_(Vehicle.plate.ilike(_like(q)), Vehicle.brand.ilike(_like(q)), Vehicle.model.ilike(_like(q)))
        )

    def serialize(vehicle: Vehicle) -> dict:
        data = vehicle.to_dict()
        driver = db.session.get(Driver, vehicle.driver_id)
        data["driverId"] = vehicle.driver_id
        data["driverName"] = driver.user.fullname if driver and driver.user else None
        data["driverPhone"] = driver.user.phone_number if driver and driver.user else None
        return data

    return _paginate(query.order_by(desc(Vehicle.created_at)), serialize, "vehicles")


# ── Courses ──────────────────────────────────────────────────────────────

@admin_bp.get("/rides")
@admin_required
def admin_list_rides():
    query = Ride.query
    status = request.args.get("status")
    if status == "active":
        query = query.filter(Ride.status.in_(list(ACTIVE_RIDE_STATUSES)))
    elif status == "unpaid":
        query = query.filter(Ride.status == "completed", Ride.is_paid.is_(False))
    elif status:
        query = query.filter(Ride.status == status)
    payment = request.args.get("paymentMethod")
    if payment:
        query = query.filter(Ride.payment_method == payment)
    q = (request.args.get("q") or "").strip()
    if q:
        query = query.filter(
            or_(
                Ride.id.ilike(_like(q)),
                Ride.departure_address.ilike(_like(q)),
                Ride.destination_address.ilike(_like(q)),
                Ride.driver_name.ilike(_like(q)),
                Ride.driver_plate.ilike(_like(q)),
                Ride.client.has(
                    or_(User.first_name.ilike(_like(q)), User.last_name.ilike(_like(q)),
                        User.phone_number.ilike(_like(q)))
                ),
            )
        )
    for arg, column, op in (("from", Ride.created_at, "ge"), ("to", Ride.created_at, "le")):
        value = request.args.get(arg)
        if value:
            try:
                from datetime import datetime

                moment = datetime.fromisoformat(value)
                if arg == "to" and len(value) == 10:
                    moment += timedelta(days=1)
                query = query.filter(column >= moment if op == "ge" else column < moment)
            except ValueError:
                return fail("Date invalide (AAAA-MM-JJ).", status=422, code="INVALID_DATE")
    return _paginate(query.order_by(desc(Ride.created_at)), lambda r: r.to_dict(), "rides")


@admin_bp.get("/rides/<string:ride_id>")
@admin_required
def admin_get_ride(ride_id: str):
    ride = db.session.get(Ride, ride_id)
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    return ok(
        data={
            "ride": ride.to_dict(include_offers=True),
            "client": _user_summary(ride.client),
            "driver": ride.driver.to_dict(include_user=True) if ride.driver else None,
            "payments": [
                p.to_dict()
                for p in RidePayment.query.filter_by(ride_id=ride.id).order_by(RidePayment.created_at)
            ],
            "messages": [
                m.to_dict()
                for m in RideMessage.query.filter_by(ride_id=ride.id).order_by(RideMessage.created_at)
            ],
            "ratings": [r.to_dict() for r in RideRating.query.filter_by(ride_id=ride.id)],
            "walletTransactions": [
                t.to_dict() for t in WalletTransaction.query.filter_by(ride_id=ride.id)
            ],
        }
    )


# ── Paiements & portefeuilles ────────────────────────────────────────────

@admin_bp.get("/payments")
@admin_required
def admin_list_payments():
    query = RidePayment.query
    status = request.args.get("status")
    if status:
        query = query.filter(RidePayment.status == status)

    def serialize(payment: RidePayment) -> dict:
        data = payment.to_dict()
        ride = payment.ride
        payer = db.session.get(User, payment.payer_user_id)
        data.update(
            {
                "msisdn": payment.msisdn,
                "country": payment.country,
                "updatedAt": payment.updated_at.isoformat() if payment.updated_at else None,
                "payer": _user_summary(payer),
                "ride": {
                    "id": ride.id,
                    "status": ride.status,
                    "isPaid": ride.is_paid,
                    "paymentMethod": ride.payment_method,
                    "finalPrice": ride.agreed_price if ride.agreed_price is not None else ride.price,
                    "driverName": ride.driver_name,
                }
                if ride
                else None,
            }
        )
        return data

    return _paginate(query.order_by(desc(RidePayment.created_at)), serialize, "payments")


@admin_bp.post("/payments/<string:deposit_id>/refunded")
@admin_required
def admin_mark_payment_refunded(deposit_id: str):
    """Trace le remboursement manuel d'un débit en double."""
    payment = db.session.get(RidePayment, deposit_id)
    if not payment:
        return fail("Paiement introuvable.", status=404, code="TX_NOT_FOUND")
    if payment.status != "duplicate":
        return fail(
            "Seul un paiement en double peut être marqué remboursé.", status=409, code="NOT_DUPLICATE"
        )
    note = str((request.get_json(silent=True) or {}).get("note") or "").strip()
    payment.status = "refunded"
    payment.failure_reason = f"Remboursé par l'administration. {note}".strip()[:255]
    create_and_emit_notification(
        user_id=payment.payer_user_id,
        title="Remboursement effectué",
        body=f"Votre paiement en double de {int(payment.amount)} XAF a été remboursé.",
        notif_type="payment_refunded",
        payload={"depositId": payment.id, "rideId": payment.ride_id},
    )
    db.session.commit()
    return ok(data=payment.to_dict(), message="Paiement marqué remboursé.")


@admin_bp.get("/wallet-transactions")
@admin_required
def admin_list_wallet_transactions():
    query = WalletTransaction.query
    for arg, column in (("type", WalletTransaction.type), ("status", WalletTransaction.status),
                        ("driverId", WalletTransaction.driver_id)):
        value = request.args.get(arg)
        if value:
            query = query.filter(column == value)

    def serialize(tx: WalletTransaction) -> dict:
        data = tx.to_dict()
        driver = db.session.get(Driver, tx.driver_id)
        data["driverName"] = driver.user.fullname if driver and driver.user else None
        data["driverPhone"] = driver.user.phone_number if driver and driver.user else None
        return data

    return _paginate(query.order_by(desc(WalletTransaction.created_at)), serialize, "transactions")


# ── Notifications ────────────────────────────────────────────────────────

@admin_bp.post("/notifications")
@admin_required
def admin_broadcast_notification():
    data = request.get_json(silent=True) or {}
    title = str(data.get("title") or "").strip()[:140]
    body = str(data.get("body") or "").strip()[:500]
    audience = str(data.get("audience") or "").strip()
    if not title or not body:
        return fail("Titre et message sont requis.", status=422, code="MISSING_FIELDS")

    query = User.query.filter(User.is_active.is_(True), User.role != "admin")
    if audience == "drivers":
        query = query.filter(User.driver_profile.has())
    elif audience == "online_drivers":
        query = query.filter(User.driver_profile.has(Driver.is_available.is_(True)))
    elif audience == "passengers":
        query = query.filter(~User.driver_profile.has())
    elif audience == "user":
        query = query.filter(User.id == str(data.get("userId") or ""))
    elif audience != "all":
        return fail("Audience invalide.", status=422, code="INVALID_AUDIENCE")

    users = query.limit(10_000).all()
    if not users:
        return fail("Aucun destinataire.", status=404, code="NO_RECIPIENT")
    for user in users:
        create_and_emit_notification(
            user_id=user.id, title=title, body=body, notif_type="admin_message",
            payload={"from": "admin"},
        )
    db.session.commit()
    return ok(data={"sent": len(users)}, message=f"Notification envoyée à {len(users)} utilisateur(s).")


@admin_bp.get("/notifications")
@admin_required
def admin_list_sent_notifications():
    """Derniers messages envoyés par l'administration (groupés par titre)."""
    rows = (
        db.session.query(
            Notification.title, Notification.body, func.count(Notification.id),
            func.max(Notification.created_at),
        )
        .filter(Notification.type == "admin_message")
        .group_by(Notification.title, Notification.body)
        .order_by(desc(func.max(Notification.created_at)))
        .limit(30)
        .all()
    )
    return ok(
        data={
            "notifications": [
                {"title": t, "body": b, "recipients": n, "sentAt": at.isoformat() if at else None}
                for t, b, n, at in rows
            ]
        }
    )


# ── Paramètres (lecture seule : ils se changent dans le .env de l'API) ──

@admin_bp.get("/settings")
@admin_required
def admin_settings():
    cfg = current_app.config
    if cfg.get("PAWAPAY_SIMULATE"):
        pawapay = "simulation"
    elif cfg.get("PAWAPAY_PRODUCTION"):
        pawapay = "production"
    else:
        pawapay = "sandbox"
    from app.tools.pawapay import PAWAPAY_COUNTRIES

    return ok(
        data={
            "environment": cfg.get("APP_ENV"),
            "commissionRate": cfg.get("COMMISSION_RATE"),
            "minRidePrice": cfg.get("MIN_RIDE_PRICE"),
            "maxRidePrice": cfg.get("MAX_RIDE_PRICE"),
            "priceStep": cfg.get("PRICE_STEP"),
            "searchRadiusKm": cfg.get("DEFAULT_SEARCH_RADIUS_KM"),
            "rideSearchTimeoutSeconds": cfg.get("RIDE_SEARCH_TIMEOUT_SECONDS"),
            "driverDisconnectGraceSeconds": cfg.get("DRIVER_DISCONNECT_GRACE_SECONDS"),
            "defaultWalletBalance": cfg.get("DEFAULT_WALLET_BALANCE"),
            "promoDiscount": cfg.get("PROMO_DISCOUNT_XAF"),
            "referralReward": cfg.get("REFERRAL_REWARD_XAF"),
            "requireDriverVerification": cfg.get("REQUIRE_DRIVER_VERIFICATION"),
            "otpProvider": cfg.get("SMS_PROVIDER"),
            "pawapayEnvironment": pawapay,
            "pawapayWebhookSigned": bool(cfg.get("PAWAPAY_WEBHOOK_SECRET")),
            "paymentCountries": [
                {"code": c["code"], "name": c["name"], "operators": [o["name"] for o in c["operators"]]}
                for c in PAWAPAY_COUNTRIES
            ],
            "support": {
                "phone": cfg.get("SUPPORT_PHONE") or None,
                "whatsapp": cfg.get("SUPPORT_WHATSAPP") or None,
                "email": cfg.get("SUPPORT_EMAIL") or None,
            },
        }
    )


# ── Carte des chauffeurs ─────────────────────────────────────────────────

@admin_bp.get("/drivers/map")
@admin_required
def admin_drivers_map():
    """Position de chaque chauffeur pour la carte du back-office.

    `scope=online` (défaut) : chauffeurs en ligne ou en course ;
    `scope=all` : tous les chauffeurs ayant déjà transmis une position.
    """
    scope = request.args.get("scope", "online")
    busy_rides = {
        ride.driver_id: ride
        for ride in Ride.query.filter(
            Ride.driver_id.isnot(None),
            Ride.status.in_(["accepted", "driver_arrived", "in_progress"]),
        ).all()
    }
    query = Driver.query.filter(Driver.latitude.isnot(None), Driver.longitude.isnot(None))
    if scope != "all":
        query = query.filter(or_(Driver.is_available.is_(True), Driver.id.in_(list(busy_rides) or [""])))

    from app.tools.driver_map import driver_map_entry

    drivers = [
        driver_map_entry(driver, busy_rides.get(driver.id), lookup_ride=False)
        for driver in query.limit(5000).all()
    ]
    counts = {s: sum(1 for d in drivers if d["state"] == s) for s in ("available", "busy", "offline")}
    return ok(data={"drivers": drivers, "counts": counts, "generatedAt": utcnow().isoformat()})
