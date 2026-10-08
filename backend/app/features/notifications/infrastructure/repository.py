from __future__ import annotations

import base64
import binascii
import json
from datetime import UTC, datetime, timedelta
from hashlib import sha256
from uuid import UUID

from cryptography.fernet import Fernet
from geoalchemy2 import Geography
from geoalchemy2.elements import WKTElement
from sqlalchemy import and_, cast, func, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.infrastructure.db.models import schema

NEARBY_RADIUS_METERS = 500
ACTIVITY_WRITE_INTERVAL = timedelta(minutes=15)
# A throttled activity write can lag the real event by up to 15 minutes.
# Grace ensures the reminder is never earlier than seven full inactive days.
INACTIVITY_THRESHOLD = timedelta(days=7) + ACTIVITY_WRITE_INTERVAL


class NotificationRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def preferences(self, user_id: UUID) -> schema.NotificationPreference:
        self.session.execute(
            insert(schema.NotificationPreference)
            .values(user_id=user_id)
            .on_conflict_do_nothing(index_elements=["user_id"])
        )
        return self.session.get(schema.NotificationPreference, user_id)

    def create_event(
        self,
        *,
        recipient_id: UUID,
        actor_id: UUID | None,
        kind: str,
        target_kind: str,
        target_id: UUID,
        event_key: str,
        comment_id: UUID | None = None,
        push_enabled: bool,
    ) -> UUID | None:
        user = self.session.get(schema.User, recipient_id)
        if user is None or not user.is_active or recipient_id == actor_id:
            return None
        notification_id = self.session.execute(
            insert(schema.Notification)
            .values(
                recipient_id=recipient_id,
                actor_id=actor_id,
                kind=kind,
                target_kind=target_kind,
                target_id=target_id,
                comment_id=comment_id,
                event_key=event_key,
            )
            .on_conflict_do_nothing(index_elements=["event_key"])
            .returning(schema.Notification.id)
        ).scalar_one_or_none()
        if notification_id is not None and push_enabled:
            self.enqueue_for_devices(
                recipient_id=recipient_id,
                event_key=event_key,
                kind=kind,
                target_kind=target_kind,
                target_id=target_id,
                notification_id=notification_id,
            )
        return notification_id

    def enqueue_for_devices(
        self,
        *,
        recipient_id: UUID,
        event_key: str,
        kind: str,
        target_kind: str | None,
        target_id: UUID | None,
        notification_id: UUID | None = None,
    ) -> None:
        device_ids = self.session.scalars(
            select(schema.NotificationDevice.id).where(
                schema.NotificationDevice.user_id == recipient_id
            )
        ).all()
        for device_id in device_ids:
            self.session.execute(
                insert(schema.NotificationPushJob)
                .values(
                    recipient_id=recipient_id,
                    device_id=device_id,
                    notification_id=notification_id,
                    event_key=event_key,
                    kind=kind,
                    target_kind=target_kind,
                    target_id=target_id,
                )
                .on_conflict_do_nothing(constraint="uq_notification_push_event_device")
            )

    def nearby_recipients(self, *, latitude: float, longitude: float, owner_id: UUID) -> list[UUID]:
        point = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
        return list(
            self.session.scalars(
                select(schema.NotificationPreference.user_id)
                .join(schema.User, schema.User.id == schema.NotificationPreference.user_id)
                .where(
                    schema.NotificationPreference.nearby_enabled.is_(True),
                    schema.NotificationPreference.alert_location.is_not(None),
                    schema.User.is_active.is_(True),
                    schema.User.id != owner_id,
                    func.ST_DWithin(
                        cast(schema.NotificationPreference.alert_location, Geography),
                        cast(point, Geography),
                        NEARBY_RADIUS_METERS,
                    ),
                )
            ).all()
        )

    def create_nearby_events(self, *, lost_pet_id: UUID, recipient_ids: list[UUID]) -> int:
        if not recipient_ids:
            return 0
        rows = self.session.execute(
            insert(schema.Notification)
            .values(
                [
                    {
                        "recipient_id": recipient_id,
                        "actor_id": None,
                        "kind": "nearby_lost_pet",
                        "target_kind": "lost_pet",
                        "target_id": lost_pet_id,
                        "event_key": f"nearby:{recipient_id}:{lost_pet_id}",
                    }
                    for recipient_id in recipient_ids
                ]
            )
            .on_conflict_do_nothing(index_elements=["event_key"])
            .returning(
                schema.Notification.id,
                schema.Notification.recipient_id,
                schema.Notification.event_key,
            )
        ).all()
        if not rows:
            return 0
        by_recipient: dict[UUID, list[UUID]] = {}
        for device_id, user_id in self.session.execute(
            select(schema.NotificationDevice.id, schema.NotificationDevice.user_id).where(
                schema.NotificationDevice.user_id.in_([row.recipient_id for row in rows])
            )
        ):
            by_recipient.setdefault(user_id, []).append(device_id)
        jobs = [
            {
                "recipient_id": row.recipient_id,
                "device_id": device_id,
                "notification_id": row.id,
                "event_key": row.event_key,
                "kind": "nearby_lost_pet",
                "target_kind": "lost_pet",
                "target_id": lost_pet_id,
            }
            for row in rows
            for device_id in by_recipient.get(row.recipient_id, [])
        ]
        if jobs:
            self.session.execute(
                insert(schema.NotificationPushJob)
                .values(jobs)
                .on_conflict_do_nothing(constraint="uq_notification_push_event_device")
            )
        return len(rows)

    def list_page(
        self, user_id: UUID, limit: int, cursor: str | None
    ) -> tuple[list[tuple], str | None]:
        statement = (
            select(schema.Notification, schema.User.name)
            .outerjoin(schema.User, schema.User.id == schema.Notification.actor_id)
            .where(schema.Notification.recipient_id == user_id)
            .order_by(schema.Notification.created_at.desc(), schema.Notification.id.desc())
        )
        if cursor:
            try:
                data = json.loads(
                    base64.urlsafe_b64decode(cursor.encode() + b"=" * (-len(cursor) % 4))
                )
            except (binascii.Error, UnicodeDecodeError) as exc:
                raise ValueError("Invalid notification cursor") from exc
            created_at = datetime.fromisoformat(data["created_at"])
            item_id = UUID(data["id"])
            statement = statement.where(
                or_(
                    schema.Notification.created_at < created_at,
                    and_(
                        schema.Notification.created_at == created_at,
                        schema.Notification.id < item_id,
                    ),
                )
            )
        rows = self.session.execute(statement.limit(limit + 1)).all()
        next_cursor = None
        if len(rows) > limit:
            last = rows[limit - 1][0]
            next_cursor = (
                base64.urlsafe_b64encode(
                    json.dumps(
                        {"created_at": last.created_at.isoformat(), "id": str(last.id)}
                    ).encode()
                )
                .decode()
                .rstrip("=")
            )
            rows = rows[:limit]
        return rows, next_cursor

    def unread_count(self, user_id: UUID) -> int:
        return int(
            self.session.scalar(
                select(func.count(schema.Notification.id)).where(
                    schema.Notification.recipient_id == user_id,
                    schema.Notification.read_at.is_(None),
                )
            )
            or 0
        )

    def mark_read(self, user_id: UUID, notification_id: UUID, now: datetime) -> bool:
        notification = self.session.scalar(
            select(schema.Notification)
            .where(
                schema.Notification.id == notification_id,
                schema.Notification.recipient_id == user_id,
            )
            .with_for_update()
        )
        if notification is None:
            return False
        notification.read_at = notification.read_at or now
        return True

    def mark_all_read(self, user_id: UUID, now: datetime) -> int:
        result = self.session.execute(
            update(schema.Notification)
            .where(
                schema.Notification.recipient_id == user_id, schema.Notification.read_at.is_(None)
            )
            .values(read_at=now)
        )
        return result.rowcount or 0

    def record_activity(self, user_id: UUID, now: datetime) -> bool:
        result = self.session.execute(
            update(schema.User)
            .where(
                schema.User.id == user_id,
                schema.User.is_active.is_(True),
                or_(
                    schema.User.last_active_at.is_(None),
                    schema.User.last_active_at <= now - ACTIVITY_WRITE_INTERVAL,
                ),
            )
            .values(last_active_at=now)
        )
        return bool(result.rowcount)

    def set_alert_location(
        self, preference: schema.NotificationPreference, latitude: float, longitude: float
    ) -> None:
        preference.alert_location = WKTElement(f"POINT({longitude} {latitude})", srid=4326)

    def get_alert_location(self, user_id: UUID) -> tuple[float, float] | None:
        row = self.session.execute(
            select(
                func.ST_Y(schema.NotificationPreference.alert_location),
                func.ST_X(schema.NotificationPreference.alert_location),
            ).where(schema.NotificationPreference.user_id == user_id)
        ).first()
        return (float(row[0]), float(row[1])) if row and row[0] is not None else None

    def upsert_device(self, user_id: UUID, token: str, encryption_key: str) -> None:
        from sqlalchemy import delete

        token_hash = sha256(token.encode()).hexdigest()
        encrypted = Fernet(encryption_key.encode()).encrypt(token.encode()).decode()
        previous = self.session.scalar(
            select(schema.NotificationDevice)
            .where(schema.NotificationDevice.token_hash == token_hash)
            .with_for_update()
        )
        if previous is not None and previous.user_id != user_id:
            self.session.execute(
                delete(schema.NotificationPushJob).where(
                    schema.NotificationPushJob.device_id == previous.id
                )
            )
        statement = insert(schema.NotificationDevice).values(
            user_id=user_id,
            platform="android",
            token_hash=token_hash,
            token_encrypted=encrypted,
            last_seen_at=datetime.now(UTC),
        )
        self.session.execute(
            statement.on_conflict_do_update(
                index_elements=["token_hash"],
                set_={
                    "user_id": user_id,
                    "token_encrypted": encrypted,
                    "last_seen_at": datetime.now(UTC),
                },
            )
        )

    def delete_device(self, user_id: UUID, token: str) -> None:
        from sqlalchemy import delete

        self.session.execute(
            delete(schema.NotificationDevice).where(
                schema.NotificationDevice.user_id == user_id,
                schema.NotificationDevice.token_hash == sha256(token.encode()).hexdigest(),
            )
        )
