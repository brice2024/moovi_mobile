"""Synchronisation des véhicules actifs et des anciens champs chauffeur."""

from app.extensions import db
from app.models import Driver, Vehicle


def ensure_active_vehicle(driver: Driver) -> Vehicle | None:
    active = Vehicle.query.filter_by(driver_id=driver.id, is_active=True).first()
    if active:
        return active
    if not any((driver.brand, driver.model, driver.plate)):
        return None
    active = Vehicle(
        driver_id=driver.id,
        vehicle_type=driver.vehicle_type,
        brand=driver.brand,
        model=driver.model,
        color=driver.color,
        plate=driver.plate,
        is_active=True,
        verification_status=driver.verification_status,
    )
    db.session.add(active)
    db.session.flush()
    return active


def sync_vehicle_from_driver(driver: Driver) -> Vehicle | None:
    vehicle = ensure_active_vehicle(driver)
    if vehicle:
        vehicle.vehicle_type = driver.vehicle_type
        vehicle.brand = driver.brand
        vehicle.model = driver.model
        vehicle.color = driver.color
        vehicle.plate = driver.plate
        vehicle.verification_status = driver.verification_status
    return vehicle


def activate_vehicle(driver: Driver, vehicle: Vehicle) -> None:
    for existing in driver.vehicles:
        existing.is_active = existing.id == vehicle.id
    driver.vehicle_type = vehicle.vehicle_type
    driver.brand = vehicle.brand
    driver.model = vehicle.model
    driver.color = vehicle.color
    driver.plate = vehicle.plate
    driver.verification_status = vehicle.verification_status
