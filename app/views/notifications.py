"""Blueprint notifications utilisateur."""

from flask import Blueprint, g, request
from sqlalchemy import desc

from app.extensions import db
from app.models import Notification
from app.tools.auth_helpers import auth_required
from app.tools.responses import fail, ok

notifications_bp = Blueprint(
    "notifications", __name__, url_prefix="/api/notifications"
)


@notifications_bp.get("")
@auth_required
def list_notifications():
    page = max(1, request.args.get("page", default=1, type=int))
    per_page = min(50, max(1, request.args.get("perPage", default=20, type=int)))
    unread_only = request.args.get("unreadOnly", default="false").lower() == "true"

    query = Notification.query.filter_by(user_id=g.current_user.id)
    if unread_only:
        query = query.filter_by(is_read=False)

    pagination = query.order_by(desc(Notification.created_at)).paginate(
        page=page, per_page=per_page, error_out=False
    )
    unread_count = Notification.query.filter_by(
        user_id=g.current_user.id, is_read=False
    ).count()
    return ok(
        data={
            "notifications": [n.to_dict() for n in pagination.items],
            "unreadCount": unread_count,
            "pagination": {
                "page": pagination.page,
                "perPage": pagination.per_page,
                "total": pagination.total,
                "pages": pagination.pages,
            },
        }
    )


@notifications_bp.post("/<int:notification_id>/read")
@auth_required
def mark_read(notification_id: int):
    notif = Notification.query.filter_by(
        id=notification_id, user_id=g.current_user.id
    ).first()
    if not notif:
        return fail("Notification introuvable.", status=404, code="NOT_FOUND")
    notif.is_read = True
    db.session.commit()
    return ok(data=notif.to_dict())


@notifications_bp.post("/read-all")
@auth_required
def mark_all_read():
    Notification.query.filter_by(user_id=g.current_user.id, is_read=False).update(
        {"is_read": True}
    )
    db.session.commit()
    return ok(message="Toutes les notifications ont été marquées comme lues.")
