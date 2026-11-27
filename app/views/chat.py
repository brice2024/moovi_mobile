"""Blueprint messagerie temps réel en course entre passager et chauffeur."""

from flask import Blueprint, g, request

from app.extensions import db, limiter
from app.models import Ride, RideMessage
from app.tools.auth_helpers import auth_required
from app.tools.realtime import create_and_emit_notification, emit_to_rooms
from app.tools.responses import fail, ok

chat_bp = Blueprint("chat", __name__, url_prefix="/api/rides")


def _resolve_participant(ride: Ride, user) -> str | None:
    if ride.client_id == user.id:
        return "passenger"
    if user.driver_profile and ride.driver_id == user.driver_profile.id:
        return "driver"
    return None


@chat_bp.get("/<string:ride_id>/messages")
@auth_required
def list_ride_messages(ride_id: str):
    ride = db.session.get(Ride, ride_id)
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")
    if not _resolve_participant(ride, g.current_user):
        return fail("Accès refusé.", status=403, code="FORBIDDEN")

    messages = (
        RideMessage.query.filter_by(ride_id=ride.id)
        .order_by(RideMessage.created_at.asc())
        .all()
    )
    return ok(data={"messages": [m.to_dict() for m in messages]})


@chat_bp.post("/<string:ride_id>/messages")
@auth_required
@limiter.limit("30 per minute")
def send_ride_message(ride_id: str):
    ride = db.session.get(Ride, ride_id)
    if not ride:
        return fail("Course introuvable.", status=404, code="RIDE_NOT_FOUND")

    sender_role = _resolve_participant(ride, g.current_user)
    if not sender_role:
        return fail(
            "Seuls le passager et le chauffeur assigné peuvent échanger.",
            status=403,
            code="FORBIDDEN",
        )
    if ride.status in {"cancelled", "expired"}:
        return fail("La course est fermée.", status=409, code="RIDE_CLOSED")

    data = request.get_json(silent=True) or {}
    content = str(data.get("content") or data.get("message") or "").strip()
    if not content:
        return fail("Message vide.", status=422, code="EMPTY_MESSAGE")

    msg = RideMessage(
        ride_id=ride.id,
        sender_user_id=g.current_user.id,
        sender_role=sender_role,
        content=content[:2000],
    )
    db.session.add(msg)

    if sender_role == "passenger":
        recipient_user_id = ride.driver.user_id if ride.driver else None
    else:
        recipient_user_id = ride.client_id
    if recipient_user_id:
        create_and_emit_notification(
            user_id=recipient_user_id,
            title=f"Message de {g.current_user.fullname}",
            body=content[:120],
            notif_type="ride_message",
            payload={"rideId": ride.id},
        )

    db.session.commit()
    payload = msg.to_dict()
    emit_to_rooms("ride:message", payload, ride_id=ride.id, user_ids=[recipient_user_id])
    return ok(data=payload, status=201)
