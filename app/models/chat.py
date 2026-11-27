"""Modèles messagerie temps réel en course et notifications utilisateur."""

from app.extensions import db
from app.models.user import utcnow


class RideMessage(db.Model):
    __tablename__ = "ride_messages"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    ride_id = db.Column(
        db.String(36),
        db.ForeignKey("rides.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    sender_user_id = db.Column(
        db.String(36), db.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    sender_role = db.Column(db.String(16), nullable=False)  # passenger | driver
    content = db.Column(db.Text, nullable=False)
    is_read = db.Column(db.Boolean, nullable=False, default=False)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)

    ride = db.relationship("Ride", back_populates="messages")
    sender = db.relationship("User")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "rideId": self.ride_id,
            "senderUserId": self.sender_user_id,
            "senderRole": self.sender_role,
            "senderName": self.sender.fullname if self.sender else "Utilisateur",
            "content": self.content,
            "isRead": self.is_read,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
        }


class Notification(db.Model):
    __tablename__ = "notifications"

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_id = db.Column(
        db.String(36),
        db.ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title = db.Column(db.String(140), nullable=False)
    body = db.Column(db.String(500), nullable=False)
    type = db.Column(db.String(40), nullable=False, default="general", index=True)
    payload = db.Column(db.JSON, nullable=True)
    is_read = db.Column(db.Boolean, nullable=False, default=False, index=True)
    created_at = db.Column(db.DateTime, nullable=False, default=utcnow, index=True)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "userId": self.user_id,
            "title": self.title,
            "body": self.body,
            "type": self.type,
            "payload": self.payload or {},
            "isRead": self.is_read,
            "createdAt": self.created_at.isoformat() if self.created_at else None,
        }
