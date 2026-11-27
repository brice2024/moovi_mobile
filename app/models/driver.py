"""Modèles chauffeurs, véhicules et documents de vérification."""

import uuid
from app.tools.storage import public_file_url
from app.extensions import db
from app.models.user import utcnow

REQUIRED_DOCS_BY_VEHICLE = {
    "voiture": [
        "license",
        "registration",
        "front",
        "left",
        "right",
        "back",
        "interior",
        "plate",
    ],
    "confort": [
        "license",
        "registration",
        "front",
        "left",
        "right",
        "back",
        "interior",
        "plate",
    ],
    "moto": [
        "license",
        "registration",
        "front",
        "left",
        "right",
        "back",
        "plate",
    ],
}


class Driver(db.Model):
    __tablename__ = "drivers"

    id = db.Column(db.String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    user_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        unique=True,
        nullable=False,
        index=True,
    )

    # Véhicule actif (voiture | confort | moto)
    vehicle_type = db.Column(db.String(20), nullable=False, default="voiture", index=True)
    brand = db.Column(db.String(80), nullable=False, default="")
    model = db.Column(db.String(80), nullable=False, default="")
    color = db.Column(db.String(50), nullable=False, default="")
    plate = db.Column(db.String(32), nullable=False, default="")

    verification_status = db.Column(
        db.String(24), nullable=False, default="pending", index=True
    )
    is_available = db.Column(db.Boolean, nullable=False, default=False, index=True)
    is_test = db.Column(db.Boolean, nullable=False, default=False, index=True)

    latitude = db.Column(db.Float, nullable=True, index=True)
    longitude = db.Column(db.Float, nullable=True, index=True)
    heading = db.Column(db.Float, nullable=True, default=0.0)
    city = db.Column(db.String(80), nullable=True, default="Libreville")
    last_location_at = db.Column(db.DateTime, nullable=True)

    # Portefeuille & métriques
    wallet_balance = db.Column(db.Float, nullable=False, default=5000.0)
    is_wallet_blocked = db.Column(db.Boolean, nullable=False, default=False)
    last_recharge_at = db.Column(db.DateTime, nullable=True)

    rating = db.Column(db.Float, nullable=False, default=4.8)
    rating_count = db.Column(db.Integer, nullable=False, default=0)
    level = db.Column(db.String(24), nullable=False, default="Or")
    rides_count = db.Column(db.Integer, nullable=False, default=0)
    total_revenue = db.Column(db.Float, nullable=False, default=0.0)

    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    user = db.relationship("User", back_populates="driver_profile")
    documents = db.relationship(
        "DriverDocument", back_populates="driver", cascade="all, delete-orphan"
    )
    vehicles = db.relationship(
        "Vehicle",
        back_populates="driver",
        cascade="all, delete-orphan",
        order_by="Vehicle.created_at",
    )
    wallet_transactions = db.relationship(
        "WalletTransaction", back_populates="driver", cascade="all, delete-orphan"
    )

    @property
    def vehicle_label(self) -> str:
        label = f"{self.brand} {self.model}".strip()
        return label or ("Moto" if self.vehicle_type == "moto" else "Véhicule")

    def to_public_dict(self) -> dict:
        """Vue « carte passager » : ni téléphone, ni portefeuille, ni revenus."""
        return {
            "id": self.id,
            "driverId": self.id,
            "vehicleType": self.vehicle_type,
            "vehicleLabel": self.vehicle_label,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "heading": self.heading,
            "city": self.city,
            "rating": round(float(self.rating or 0), 2),
            "level": self.level,
            "isTest": self.is_test,
        }

    def recompute_level(self) -> str:
        """Niveau affiché aux passagers : Or, puis Platine et Diamant selon
        l'expérience (courses réglées) et la note moyenne."""
        rides = int(self.rides_count or 0)
        rating = float(self.rating or 0)
        if rides >= 200 and rating >= 4.8:
            self.level = "Diamant"
        elif rides >= 50 and rating >= 4.5:
            self.level = "Platine"
        else:
            self.level = "Or"
        return self.level

    def required_document_types(self) -> list[str]:
        return REQUIRED_DOCS_BY_VEHICLE.get(
            self.vehicle_type, REQUIRED_DOCS_BY_VEHICLE["voiture"]
        )

    def documents_summary(self) -> dict:
        required = self.required_document_types()
        docs_by_type = {doc.doc_type: doc for doc in self.documents}
        items = {}
        uploaded_count = 0
        verified_count = 0
        for doc_type in required:
            doc = docs_by_type.get(doc_type)
            if doc:
                uploaded_count += 1
                if doc.status == "verified":
                    verified_count += 1
                items[doc_type] = doc.to_dict()
            else:
                items[doc_type] = {
                    "docType": doc_type,
                    "status": "missing",
                    "url": None,
                    "path": None,
                }
        total = len(required)
        return {
            "total": total,
            "uploaded": uploaded_count,
            "verified": verified_count,
            "progressPercent": round((uploaded_count / total) * 100) if total else 0,
            "items": items,
        }

    def to_dict(self, include_user: bool = True, include_documents: bool = False) -> dict:
        vehicle_payload = {
            "type": self.vehicle_type,
            "brand": self.brand,
            "model": self.model,
            "color": self.color,
            "plate": self.plate,
        }
        data = {
            "id": self.id,
            "driverId": self.id,
            "userId": self.user_id,
            "vehicleType": self.vehicle_type,
            "vehicle": vehicle_payload,
            "car": vehicle_payload if self.vehicle_type in {"voiture", "confort"} else None,
            "moto": vehicle_payload if self.vehicle_type == "moto" else None,
            "vehicleLabel": self.vehicle_label,
            "plate": self.plate,
            "verificationStatus": self.verification_status,
            "isAvailable": self.is_available,
            "isTest": self.is_test,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "heading": self.heading,
            "city": self.city,
            "lastLocationAt": (
                self.last_location_at.isoformat() if self.last_location_at else None
            ),
            "walletBalance": round(float(self.wallet_balance or 0), 2),
            "isWalletBlocked": self.is_wallet_blocked,
            "rating": round(float(self.rating or 0), 2),
            "ratingCount": self.rating_count,
            "level": self.level,
            "ridesCount": self.rides_count,
            "totalRevenue": round(float(self.total_revenue or 0), 2),
            "lastRechargeAt": (
                self.last_recharge_at.isoformat() if self.last_recharge_at else None
            ),
            "createdAt": self.created_at.isoformat() if self.created_at else None,
            "updatedAt": self.updated_at.isoformat() if self.updated_at else None,
            "vehicles": [vehicle.to_dict() for vehicle in self.vehicles],
        }
        if include_user and self.user is not None:
            data["driverName"] = self.user.fullname
            data["phoneNumber"] = self.user.phone_number
            data["email"] = self.user.email
            data["isAccountActive"] = self.user.is_active
            data["photoUrl"] = public_file_url(self.user.photo_url)
        if include_documents:
            data["documents"] = self.documents_summary()
        return data


class DriverDocument(db.Model):
    __tablename__ = "driver_documents"
    __table_args__ = (
        db.UniqueConstraint("driver_id", "doc_type", name="uq_driver_doc_type"),
    )

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    driver_id = db.Column(
        db.String(36),
        db.ForeignKey("drivers.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    doc_type = db.Column(db.String(32), nullable=False)
    file_path = db.Column(db.String(255), nullable=False)
    file_url = db.Column(db.String(512), nullable=False)
    status = db.Column(db.String(24), nullable=False, default="pending", index=True)
    rejection_reason = db.Column(db.String(255), nullable=True)
    reviewed_by = db.Column(db.String(36), nullable=True)
    reviewed_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow)
    updated_at = db.Column(
        db.DateTime, nullable=False, default=utcnow, onupdate=utcnow
    )

    driver = db.relationship("Driver", back_populates="documents")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "docType": self.doc_type,
            "path": self.file_path,
            "url": public_file_url(self.file_url),
            "status": self.status,
            "rejectionReason": self.rejection_reason,
            "reviewedAt": self.reviewed_at.isoformat() if self.reviewed_at else None,
            "updatedAt": self.updated_at.isoformat() if self.updated_at else None,
        }
