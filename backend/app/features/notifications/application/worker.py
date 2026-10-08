from __future__ import annotations

import time
from datetime import UTC, datetime, timedelta
from uuid import UUID

from cryptography.fernet import Fernet
from sqlalchemy import and_, delete, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from structlog import get_logger

from app.core.config import Settings, get_settings
from app.features.notifications.infrastructure.fcm import FcmSender, PushResult
from app.features.notifications.infrastructure.repository import INACTIVITY_THRESHOLD
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)
MAX_ATTEMPTS = 4
RETRY_DELAYS = (60, 300, 1800)
LEASE_TIME = timedelta(minutes=2)
POLL_SECONDS = 30

PUSH_COPY = {
    "en": {
        "comment": ("New comment", "Someone commented on your post."),
        "reply": ("New reply", "Someone replied to your comment."),
        "nearby_lost_pet": ("Lost pet nearby", "A lost pet was reported near your alert point."),
        "lost_pet_followup": ("Lost pet follow-up", "Please check your lost pet follow-up."),
        "adoption_followup": ("New home follow-up", "Please check your new home follow-up."),
        "inactivity": ("We miss you", "See what is new in Mushukistan."),
    },
    "ru": {
        "comment": ("Новый комментарий", "Кто-то прокомментировал вашу публикацию."),
        "reply": ("Новый ответ", "Кто-то ответил на ваш комментарий."),
        "nearby_lost_pet": ("Рядом пропал питомец", "Рядом с выбранной точкой ищут питомца."),
        "lost_pet_followup": ("Напоминание о питомце", "Проверьте вопрос о пропавшем питомце."),
        "adoption_followup": (
            "Напоминание о новом доме",
            "Проверьте вопрос о новом доме для питомца.",
        ),
        "inactivity": ("Мы скучаем", "Посмотрите, что нового в Mushukistan."),
    },
    "uz": {
        "comment": ("Yangi izoh", "Kimdir postingizga izoh qoldirdi."),
        "reply": ("Yangi javob", "Kimdir izohingizga javob berdi."),
        "nearby_lost_pet": (
            "Yaqinda jonivor yo‘qoldi",
            "Tanlangan joy yaqinida jonivor yo‘qolgani e’lon qilindi.",
        ),
        "lost_pet_followup": (
            "Yo‘qolgan jonivor haqida eslatma",
            "Yo‘qolgan jonivor haqidagi savolni tekshiring.",
        ),
        "adoption_followup": (
            "Yangi uy haqida eslatma",
            "Jonivorning yangi uyi haqidagi savolni tekshiring.",
        ),
        "inactivity": ("Sizni sog‘indik", "Mushukistandagi yangiliklarni ko‘ring."),
    },
}


class NotificationWorker:
    def __init__(
        self, manager: DatabaseSessionManager, settings: Settings, sender: FcmSender
    ) -> None:
        self.manager = manager
        self.settings = settings
        self.sender = sender
        self.cipher = Fernet(settings.push_token_encryption_key.encode())

    def enqueue_due_followups(self, now: datetime) -> int:
        count = 0
        with self.manager.session_scope() as session:
            for followup_model, post_model, post_id_field, kind in (
                (
                    schema.LostPetFollowUp,
                    schema.LostPet,
                    schema.LostPetFollowUp.lost_pet_id,
                    "lost_pet_followup",
                ),
                (
                    schema.AdoptionFollowUp,
                    schema.AdoptionPost,
                    schema.AdoptionFollowUp.adoption_post_id,
                    "adoption_followup",
                ),
            ):
                rows = session.execute(
                    select(followup_model.id, followup_model.owner_id, schema.NotificationDevice.id)
                    .join(post_model, post_model.id == post_id_field)
                    .join(schema.User, schema.User.id == followup_model.owner_id)
                    .join(
                        schema.NotificationDevice,
                        schema.NotificationDevice.user_id == schema.User.id,
                    )
                    .outerjoin(
                        schema.NotificationPreference,
                        schema.NotificationPreference.user_id == schema.User.id,
                    )
                    .where(
                        followup_model.due_at <= now,
                        followup_model.completed_at.is_(None),
                        post_model.deleted_at.is_(None),
                        post_model.is_resolved.is_(False),
                        schema.User.is_active.is_(True),
                        or_(
                            schema.NotificationPreference.user_id.is_(None),
                            schema.NotificationPreference.push_followups.is_(True),
                        ),
                    )
                ).all()
                if rows:
                    values = [
                        {
                            "recipient_id": owner_id,
                            "device_id": device_id,
                            "event_key": f"{kind}:{followup_id}",
                            "kind": kind,
                            "target_kind": kind,
                            "target_id": followup_id,
                        }
                        for followup_id, owner_id, device_id in rows
                    ]
                    result = session.execute(
                        insert(schema.NotificationPushJob)
                        .values(values)
                        .on_conflict_do_nothing(constraint="uq_notification_push_event_device")
                        .returning(schema.NotificationPushJob.id)
                    )
                    count += len(result.all())
        return count

    def enqueue_inactivity(self, now: datetime) -> int:
        count = 0
        with self.manager.session_scope() as session:
            candidates = session.execute(
                select(schema.User.id, schema.User.last_active_at, schema.NotificationPreference)
                .join(
                    schema.NotificationPreference,
                    schema.NotificationPreference.user_id == schema.User.id,
                )
                .where(
                    schema.User.is_active.is_(True),
                    schema.User.last_active_at.is_not(None),
                    schema.User.last_active_at <= now - INACTIVITY_THRESHOLD,
                    schema.NotificationPreference.inactivity_enabled.is_(True),
                    or_(
                        schema.NotificationPreference.last_inactivity_cycle_at.is_(None),
                        schema.NotificationPreference.last_inactivity_cycle_at
                        != schema.User.last_active_at,
                    ),
                )
                .with_for_update(of=schema.NotificationPreference, skip_locked=True)
            ).all()
            for user_id, last_active_at, preference in candidates:
                devices = session.scalars(
                    select(schema.NotificationDevice.id).where(
                        schema.NotificationDevice.user_id == user_id
                    )
                ).all()
                if not devices:
                    preference.last_inactivity_cycle_at = last_active_at
                    continue
                event_key = f"inactivity:{user_id}:{last_active_at.isoformat()}"
                result = session.execute(
                    insert(schema.NotificationPushJob)
                    .values(
                        [
                            {
                                "recipient_id": user_id,
                                "device_id": device_id,
                                "event_key": event_key,
                                "kind": "inactivity",
                                "activity_cycle_at": last_active_at,
                            }
                            for device_id in devices
                        ]
                    )
                    .on_conflict_do_nothing(constraint="uq_notification_push_event_device")
                    .returning(schema.NotificationPushJob.id)
                )
                count += len(result.all())
                preference.last_inactivity_cycle_at = last_active_at
        return count

    def _claim(self, now: datetime, batch_size: int = 50) -> list[UUID]:
        with self.manager.session_scope() as session:
            session.execute(
                update(schema.NotificationPushJob)
                .where(
                    schema.NotificationPushJob.status == "sending",
                    schema.NotificationPushJob.lease_until <= now,
                    schema.NotificationPushJob.attempts >= MAX_ATTEMPTS,
                )
                .values(status="failed", lease_until=None, last_error_code="LEASE_EXPIRED")
            )
            jobs = session.scalars(
                select(schema.NotificationPushJob)
                .where(
                    schema.NotificationPushJob.attempts < MAX_ATTEMPTS,
                    or_(
                        and_(
                            schema.NotificationPushJob.status == "pending",
                            schema.NotificationPushJob.next_attempt_at <= now,
                        ),
                        and_(
                            schema.NotificationPushJob.status == "sending",
                            schema.NotificationPushJob.lease_until <= now,
                        ),
                    ),
                )
                .order_by(schema.NotificationPushJob.next_attempt_at, schema.NotificationPushJob.id)
                .limit(batch_size)
                .with_for_update(skip_locked=True)
            ).all()
            for job in jobs:
                job.status = "sending"
                job.lease_until = now + LEASE_TIME
                job.attempts += 1
            return [job.id for job in jobs]

    def _eligible(self, session, job: schema.NotificationPushJob, now: datetime) -> bool:
        user = session.get(schema.User, job.recipient_id)
        device = session.get(schema.NotificationDevice, job.device_id)
        if (
            user is None
            or not user.is_active
            or device is None
            or device.user_id != job.recipient_id
        ):
            return False
        pref = session.get(schema.NotificationPreference, job.recipient_id)
        if job.kind == "inactivity":
            return bool(
                pref
                and pref.inactivity_enabled
                and user.last_active_at == job.activity_cycle_at
                and user.last_active_at <= now - INACTIVITY_THRESHOLD
            )
        if job.kind in ("comment", "reply"):
            if pref and not getattr(
                pref, f"push_{'comments' if job.kind == 'comment' else 'replies'}"
            ):
                return False
            if (
                job.notification_id is None
                or session.get(schema.Notification, job.notification_id) is None
            ):
                return False
            target_model = {
                "post": schema.Post,
                "lost_pet": schema.LostPet,
                "adoption_post": schema.AdoptionPost,
            }.get(job.target_kind)
            target = session.get(target_model, job.target_id) if target_model else None
            return bool(target and not target.deleted_at)
        if job.kind == "nearby_lost_pet":
            pet = session.get(schema.LostPet, job.target_id)
            return bool(
                pref
                and pref.nearby_enabled
                and pet
                and pet.is_public
                and not pet.deleted_at
                and not pet.is_resolved
            )
        followup_model, post_model, post_id_name = (
            (schema.LostPetFollowUp, schema.LostPet, "lost_pet_id")
            if job.kind == "lost_pet_followup"
            else (schema.AdoptionFollowUp, schema.AdoptionPost, "adoption_post_id")
        )
        followup = session.get(followup_model, job.target_id)
        post = session.get(post_model, getattr(followup, post_id_name)) if followup else None
        return bool(
            (not pref or pref.push_followups)
            and followup
            and followup.owner_id == job.recipient_id
            and followup.completed_at is None
            and followup.due_at <= now
            and post
            and not post.deleted_at
            and not post.is_resolved
        )

    def deliver(self, now: datetime) -> int:
        delivered = 0
        for job_id in self._claim(now):
            with self.manager.session_scope() as session:
                job = session.get(schema.NotificationPushJob, job_id)
                if job is None or job.status != "sending":
                    continue
                if not self._eligible(session, job, now):
                    job.status = "cancelled"
                    job.lease_until = None
                    continue
                user = session.get(schema.User, job.recipient_id)
                device = session.get(schema.NotificationDevice, job.device_id)
                token = self.cipher.decrypt(device.token_encrypted.encode()).decode()
                title, body = PUSH_COPY.get(user.preferred_language, PUSH_COPY["en"])[job.kind]
                data = {"kind": job.kind}
                if job.notification_id:
                    data["notification_id"] = str(job.notification_id)
                if job.target_kind and job.target_id:
                    data["target_kind"] = job.target_kind
                    data["target_id"] = str(job.target_id)
            result: PushResult = self.sender.send(token, title, body, data)
            with self.manager.session_scope() as session:
                job = session.get(schema.NotificationPushJob, job_id)
                if job is None:
                    continue
                job.lease_until = None
                if result.success:
                    job.status = "sent"
                    job.sent_at = datetime.now(UTC)
                    delivered += 1
                elif result.invalid_token:
                    device_id = job.device_id
                    session.expunge(job)
                    session.execute(
                        delete(schema.NotificationDevice).where(
                            schema.NotificationDevice.id == device_id
                        )
                    )
                    logger.info("notification_token_retired", device_id=str(device_id))
                elif job.attempts >= MAX_ATTEMPTS:
                    job.status = "failed"
                    job.last_error_code = result.error_code
                else:
                    job.status = "pending"
                    job.next_attempt_at = datetime.now(UTC) + timedelta(
                        seconds=RETRY_DELAYS[job.attempts - 1]
                    )
                    job.last_error_code = result.error_code
        return delivered

    def run_forever(self) -> None:
        last_scheduled = datetime.min.replace(tzinfo=UTC)
        while True:
            now = datetime.now(UTC)
            try:
                if now - last_scheduled >= timedelta(minutes=1):
                    self.enqueue_due_followups(now)
                    self.enqueue_inactivity(now)
                    last_scheduled = now
                self.deliver(now)
            except Exception:
                logger.exception("notification_worker_pass_failed")
            time.sleep(POLL_SECONDS)


def main() -> None:
    settings = get_settings()
    if not settings.push_token_encryption_key:
        raise RuntimeError("PUSH_TOKEN_ENCRYPTION_KEY is required for notification worker")
    sender = FcmSender(settings.firebase_credentials_file, settings.firebase_project_id)
    manager = DatabaseSessionManager(settings.database_url)
    NotificationWorker(manager, settings, sender).run_forever()


if __name__ == "__main__":
    main()
