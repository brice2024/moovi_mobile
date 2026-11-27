"""Tâches périodiques de fin de recherche et de présence chauffeur."""

from datetime import timedelta

from sqlalchemy import or_

from app.extensions import db, socketio
from app.models import Driver, Ride, RideOffer
from app.models.user import utcnow
from app.tools.benefits import release_ride_benefit
from app.tools.realtime import (
    create_and_emit_notification,
    emit_to_rooms,
    emit_to_driver,
    emit_to_online_drivers,
    emit_to_passengers_map,
)


def expire_searching_rides(app) -> int:
    with app.app_context():
        cutoff = utcnow() - timedelta(
            seconds=app.config["RIDE_SEARCH_TIMEOUT_SECONDS"]
        )
        rides = (
            db.session.query(Ride)
            .filter(Ride.status == "searching", Ride.created_at <= cutoff)
            .with_for_update()
            .all()
        )
        expired = []
        for ride in rides:
            if ride.status != "searching":
                continue
            ride.status = "expired"
            RideOffer.query.filter_by(ride_id=ride.id, status="pending").update(
                {"status": "rejected"}
            )
            release_ride_benefit(ride)
            create_and_emit_notification(
                user_id=ride.client_id,
                title="Recherche terminée",
                body="Aucun chauffeur n'a répondu à temps. Vous pouvez relancer une course.",
                notif_type="ride_expired",
                payload={"rideId": ride.id, "status": "expired"},
            )
            expired.append(ride)
        db.session.commit()
        for ride in expired:
            payload = ride.to_dict(include_offers=True)
            emit_to_rooms(
                "ride:expired",
                payload,
                ride_id=ride.id,
                user_ids=[ride.client_id],
                driver_ids=[ride.driver_id],
            )
            emit_to_online_drivers(
                "ride:expired",
                {"rideId": ride.id, "status": "expired"},
                vehicle_type=ride.ride_type,
            )
        return len(expired)


def set_stale_drivers_offline(app) -> int:
    with app.app_context():
        cutoff = utcnow() - timedelta(
            seconds=app.config["DRIVER_DISCONNECT_GRACE_SECONDS"]
        )
        drivers = (
            db.session.query(Driver)
            .filter(
                Driver.is_available.is_(True),
                or_(
                    Driver.last_location_at.is_(None),
                    Driver.last_location_at <= cutoff,
                ),
            )
            .with_for_update()
            .all()
        )
        offline = []
        for driver in drivers:
            if not driver.is_available:
                continue
            driver.is_available = False
            offline.append(driver)
        db.session.commit()
        for driver in offline:
            payload = {
                "driverId": driver.id,
                "isAvailable": False,
                "vehicleType": driver.vehicle_type,
            }
            emit_to_driver(driver.id, "driver:offline", payload)
            from app.views.realtime import sync_driver_rooms

            sync_driver_rooms(driver)
            emit_to_passengers_map("driver:availability_changed", payload)
        return len(offline)


RECONCILE_EVERY_SECONDS = 60
PENDING_GIVE_UP_AFTER = timedelta(hours=48)


def reconcile_pending_deposits(app, limit: int = 20) -> int:
    """Rapproche les dépôts PawaPay restés en attente (recharges et courses).

    Indispensable quand le webhook ne peut pas joindre le serveur et que
    l'application a cessé d'interroger le statut : sans cela, un passager
    débité ou une recharge payée resteraient « en attente » pour toujours.
    """
    from app.models import RidePayment, WalletTransaction
    from app.tools.pawapay import check_deposit_status
    from app.views.payments import FAILED_STATUSES, finalize_ride_payment
    from app.views.wallet import apply_completed_deposit

    with app.app_context():
        now = utcnow()
        settled = 0
        fresh = now - timedelta(seconds=60)
        ride_payments = (
            RidePayment.query.filter(RidePayment.status == "pending", RidePayment.created_at <= fresh)
            .order_by(RidePayment.updated_at)
            .limit(limit)
            .all()
        )
        recharges = (
            WalletTransaction.query.filter(
                WalletTransaction.status == "pending",
                WalletTransaction.gateway == "pawapay",
                WalletTransaction.created_at <= fresh,
            )
            .order_by(WalletTransaction.updated_at)
            .limit(limit)
            .all()
        )
        for payment in ride_payments:
            try:
                gw = check_deposit_status(payment.id)
            except Exception:
                app.logger.warning("Rapprochement PawaPay impossible pour %s", payment.id)
                continue
            status = str(gw.get("status", "")).upper()
            if status not in FAILED_STATUSES and status != "COMPLETED":
                if now - payment.created_at > PENDING_GIVE_UP_AFTER:
                    status = "FAILED"
                else:
                    payment.updated_at = now  # passe en fin de file
                    db.session.commit()
                    continue
            if finalize_ride_payment(payment, status, gw.get("failureReason")) != "pending":
                settled += 1
        for tx in recharges:
            locked = (
                db.session.query(WalletTransaction).filter_by(id=tx.id).with_for_update().first()
            )
            if not locked or locked.status != "pending":
                continue
            try:
                gw = check_deposit_status(locked.id)
            except Exception:
                app.logger.warning("Rapprochement PawaPay impossible pour %s", locked.id)
                db.session.rollback()
                continue
            status = str(gw.get("status", "")).upper()
            if status == "COMPLETED":
                apply_completed_deposit(locked)
                settled += 1
            elif status in FAILED_STATUSES or now - locked.created_at > PENDING_GIVE_UP_AFTER:
                locked.status = "failed"
                db.session.commit()
                settled += 1
            else:
                locked.updated_at = now
                db.session.commit()
        return settled


def _periodic_jobs(app) -> None:
    last_reconcile = 0.0
    while True:
        try:
            expire_searching_rides(app)
            set_stale_drivers_offline(app)
            import time

            if time.monotonic() - last_reconcile >= RECONCILE_EVERY_SECONDS:
                last_reconcile = time.monotonic()
                reconcile_pending_deposits(app)
        except Exception:
            app.logger.exception("Échec des tâches périodiques Moovi.")
            with app.app_context():
                db.session.rollback()
                db.session.remove()
        socketio.sleep(app.config["BACKGROUND_TASK_INTERVAL_SECONDS"])


def start_background_jobs(app) -> None:
    if app.extensions.get("moovi_background_jobs_started"):
        return
    app.extensions["moovi_background_jobs_started"] = True
    socketio.start_background_task(_periodic_jobs, app)
