"""Création idempotente de données fictives pour le développement local."""

from datetime import timedelta

from sqlalchemy import or_

from app.extensions import db
from app.models import Driver, Ride, RideOffer, User, Vehicle
from app.models.user import utcnow

_PASSENGER_EMAIL = "passager.demo@moovi.local"
_PASSENGER_PHONE = "+24107000001"
_DRIVER_FIXTURES = (
    ("chauffeur.demo01@moovi.local", "+24107000011", "Toyota", "Corolla", "voiture", "Blanc"),
    ("chauffeur.demo02@moovi.local", "+24107000012", "Hyundai", "Accent", "voiture", "Gris"),
    ("chauffeur.demo03@moovi.local", "+24107000013", "Toyota", "RAV4", "confort", "Noir"),
    ("chauffeur.demo04@moovi.local", "+24107000014", "Suzuki", "Swift", "voiture", "Bleu"),
    ("chauffeur.demo05@moovi.local", "+24107000015", "Bajaj", "Boxer", "moto", "Rouge"),
)
_RIDE_IDS = {
    status: f"demo-0000-0000-0000-{suffix:012d}"
    for status, suffix in (
        ("searching", 1),
        ("accepted", 2),
        ("completed", 3),
        ("cancelled", 4),
    )
}


def _find_or_create_user(email: str, phone: str, first_name: str, last_name: str, role: str):
    user = User.query.filter(
        or_(User.email == email, User.phone_number == phone)
    ).first()
    if user:
        if user.email != email or user.phone_number != phone:
            raise ValueError(
                f"Conflit de données pour le compte de démonstration {email}."
            )
        return user, False

    user = User(
        email=email,
        phone_number=phone,
        first_name=first_name,
        last_name=last_name,
        role=role,
    )
    db.session.add(user)
    db.session.flush()
    return user, True


def seed_demo_data() -> dict[str, int]:
    """Ajoute un passager, cinq chauffeurs et quatre courses sans supprimer de données."""
    now = utcnow()
    passenger, passenger_created = _find_or_create_user(
        _PASSENGER_EMAIL, _PASSENGER_PHONE, "Passager", "Démo", "passenger"
    )

    drivers = []
    created_drivers = 0
    for index, fixture in enumerate(_DRIVER_FIXTURES, start=1):
        email, phone, brand, model, vehicle_type, color = fixture
        user, _ = _find_or_create_user(
            email, phone, "Chauffeur", f"Démo {index:02d}", "driver"
        )
        driver = Driver.query.filter_by(user_id=user.id).first()
        if driver is None:
            driver = Driver(
                user_id=user.id,
                vehicle_type=vehicle_type,
                brand=brand,
                model=model,
                color=color,
                plate=f"DEMO-{index:03d}",
                verification_status="approved",
                is_available=True,
                is_test=True,
                latitude=0.4162 + (index * 0.001),
                longitude=9.4673 + (index * 0.001),
                city="Libreville",
                wallet_balance=5000.0,
                last_location_at=now,
            )
            db.session.add(driver)
            db.session.flush()
            db.session.add(
                Vehicle(
                    driver_id=driver.id,
                    vehicle_type=vehicle_type,
                    brand=brand,
                    model=model,
                    color=color,
                    plate=f"DEMO-{index:03d}",
                    is_active=True,
                    verification_status="approved",
                )
            )
            created_drivers += 1
        drivers.append(driver)

    created_rides = 0
    ride_specs = (
        ("searching", None, 2000, 0),
        ("accepted", drivers[0], 2500, 0),
        ("completed", drivers[1], 3000, 2),
        ("cancelled", None, 1500, 1),
    )
    for status, driver, price, age_days in ride_specs:
        ride_id = _RIDE_IDS[status]
        ride = db.session.get(Ride, ride_id)
        if ride:
            continue

        created_at = now - timedelta(days=age_days)
        ride = Ride(
            id=ride_id,
            client_id=passenger.id,
            driver_id=driver.id if driver else None,
            departure_lat=0.4162,
            departure_lng=9.4673,
            departure_address="Gare routière, Libreville (démo)",
            destination_lat=0.4580,
            destination_lng=9.4120,
            destination_address="Aéroport Léon-Mba (démo)",
            ride_type=driver.vehicle_type if driver else "voiture",
            price=price,
            agreed_price=price if driver else None,
            currency="XAF",
            distance_meters=8200,
            distance_text="8,2 km",
            duration_seconds=1200,
            duration_text="20 min",
            status=status,
            created_at=created_at,
        )
        if driver:
            ride.driver_name = driver.user.fullname
            ride.driver_car = driver.vehicle_label
            ride.driver_plate = driver.plate
            ride.driver_phone = driver.user.phone_number
            ride.accepted_at = created_at
        if status == "completed":
            ride.started_at = created_at + timedelta(minutes=5)
            ride.completed_at = created_at + timedelta(minutes=25)
            ride.is_paid = True
            ride.payment_method = "cash"
            ride.payment_provider = "cash"
            ride.payment_transaction_id = f"demo-cash-{ride.id}"
            ride.paid_amount = price
            ride.platform_commission = round(price * 0.15, 2)
            ride.commission_rate = 0.15
            ride.commission_deducted = True
            ride.paid_at = ride.completed_at
        elif status == "cancelled":
            ride.cancelled_by = "passenger"
            ride.cancel_reason = "Course de démonstration"
            ride.cancelled_at = created_at + timedelta(minutes=2)

        db.session.add(ride)
        db.session.flush()
        created_rides += 1

        if driver and status == "accepted":
            db.session.add(
                RideOffer(
                    ride_id=ride.id,
                    driver_id=driver.id,
                    driver_name=driver.user.fullname,
                    rating=driver.rating,
                    level=driver.level,
                    car=driver.vehicle_label,
                    plate=driver.plate,
                    price=price,
                    arrival_minutes=5,
                    status="accepted",
                )
            )
        elif status == "searching":
            available_driver = drivers[0]
            db.session.add(
                RideOffer(
                    ride_id=ride.id,
                    driver_id=available_driver.id,
                    driver_name=available_driver.user.fullname,
                    rating=available_driver.rating,
                    level=available_driver.level,
                    car=available_driver.vehicle_label,
                    plate=available_driver.plate,
                    price=price,
                    arrival_minutes=5,
                    status="pending",
                )
            )

    db.session.commit()
    return {
        "passengersCreated": int(passenger_created),
        "driversCreated": created_drivers,
        "ridesCreated": created_rides,
    }
