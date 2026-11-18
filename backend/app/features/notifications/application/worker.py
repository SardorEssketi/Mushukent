from __future__ import annotations

import signal
import threading
from datetime import UTC, datetime, timedelta
from uuid import UUID

from cryptography.fernet import Fernet
from geoalchemy2 import Geography
from sqlalchemy import and_, cast, delete, func, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from structlog import get_logger

from app.core.config import Settings, get_settings
from app.features.notifications.infrastructure.fcm import FcmSender, PushResult
from app.features.notifications.infrastructure.repository import (
    INACTIVITY_THRESHOLD,
    NEARBY_RADIUS_METERS,
    NotificationRepository,
)
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.repositories.blocking import users_are_blocked

logger = get_logger(__name__)
MAX_ATTEMPTS = 4
RETRY_DELAYS = (60, 300, 1800)
LEASE_TIME = timedelta(minutes=2)
POLL_SECONDS = 30
CLAIM_BATCH_SIZE = 50

PUSH_COPY = {
    "en": {
        "comment": ("New comment", "Someone commented on your post."),
        "reply": ("New reply", "Someone replied to your comment."),
        "nearby_lost_pet": (
            "Lost pet nearby",
            "A lost pet was reported near your last authorized location.",
        ),
        "lost_pet_followup": ("Lost pet follow-up", "Please check your lost pet follow-up."),
        "adoption_followup": ("New home follow-up", "Please check your new home follow-up."),
        "inactivity": ("We miss you", "See what is new in Mushukistan."),
        "publication_removed": (
            "Publication removed",
            "A moderator removed one of your publications.",
        ),
    },
    "ru": {
        "comment": ("Новый комментарий", "Кто-то прокомментировал вашу публикацию."),
        "reply": ("Новый ответ", "Кто-то ответил на ваш комментарий."),
        "nearby_lost_pet": (
            "Рядом пропал питомец",
            "Рядом с вашим последним разрешённым местоположением ищут питомца.",
        ),
        "lost_pet_followup": ("Напоминание о питомце", "Проверьте вопрос о пропавшем питомце."),
        "adoption_followup": (
            "Напоминание о новом доме",
            "Проверьте вопрос о новом доме для питомца.",
        ),
        "inactivity": ("Мы скучаем", "Посмотрите, что нового в Mushukistan."),
        "publication_removed": (
            "Публикация удалена",
            "Модератор удалил одну из ваших публикаций.",
        ),
    },
    "uz": {
        "comment": ("Yangi izoh", "Kimdir postingizga izoh qoldirdi."),
        "reply": ("Yangi javob", "Kimdir izohingizga javob berdi."),
        "nearby_lost_pet": (
            "Yaqinda jonivor yo‘qoldi",
            "Oxirgi ruxsat berilgan joylashuvingiz yaqinida jonivor yo‘qolgani e’lon qilindi.",
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
        "publication_removed": (
            "Post olib tashlandi",
            "Moderator postlaringizdan birini olib tashladi.",
        ),
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
        # Set by SIGTERM/SIGINT (`docker stop`). The worker finishes the job it is sending, puts
        # the claimed jobs it has not started back to pending, and exits within seconds instead of
        # being killed at the stop timeout (as PID 1 it would ignore SIGTERM without a handler).
        self.stop_event = threading.Event()

    def request_stop(self, signum: int | None = None, _frame: object = None) -> None:
        if not self.stop_event.is_set():
            logger.info("notification_worker_stop_requested", signal=signum)
        self.stop_event.set()

    def install_signal_handlers(self) -> None:
        for sig in (signal.SIGTERM, signal.SIGINT):
            signal.signal(sig, self.request_stop)

    def enqueue_due_followups(self, now: datetime) -> int:
        count = 0
        with self.manager.session_scope() as session:
            NotificationRepository(session).normalize_defaults()
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
            NotificationRepository(session).normalize_defaults()
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

    def _claim(self, now: datetime, batch_size: int = CLAIM_BATCH_SIZE) -> list[UUID]:
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
        pref = NotificationRepository(session).preferences(job.recipient_id)
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
            notification = (
                session.get(schema.Notification, job.notification_id)
                if job.notification_id is not None
                else None
            )
            if notification is None:
                return False
            # Re-check at delivery time: a block created after the event was queued cancels it.
            if users_are_blocked(session, notification.actor_id, job.recipient_id):
                return False
            target_model = {
                "post": schema.Post,
                "lost_pet": schema.LostPet,
                "adoption_post": schema.AdoptionPost,
            }.get(job.target_kind)
            target = session.get(target_model, job.target_id) if target_model else None
            return bool(target and not target.deleted_at)
        if job.kind == "publication_removed":
            notification = (
                session.get(schema.Notification, job.notification_id)
                if job.notification_id is not None
                else None
            )
            target_model = {
                "post": schema.Post,
                "lost_pet": schema.LostPet,
                "adoption_post": schema.AdoptionPost,
            }.get(job.target_kind)
            target = session.get(target_model, job.target_id) if target_model else None
            # Only while the publication is still removed (no restore exists today).
            return bool(notification and target and target.deleted_at)
        if job.kind == "nearby_lost_pet":
            pet = session.get(schema.LostPet, job.target_id)
            return bool(
                pref
                and pref.nearby_enabled
                and pet
                and not users_are_blocked(session, pet.user_id, job.recipient_id)
                and pet.is_public
                and not pet.deleted_at
                and not pet.is_resolved
                and session.scalar(
                    select(
                        func.ST_DWithin(
                            cast(schema.NotificationPreference.alert_location, Geography),
                            cast(schema.LostPet.last_seen_location, Geography),
                            NEARBY_RADIUS_METERS,
                        )
                    )
                    .select_from(schema.NotificationPreference)
                    .join(schema.LostPet, schema.LostPet.id == job.target_id)
                    .where(schema.NotificationPreference.user_id == job.recipient_id)
                )
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
        """Deliver one claimed batch; returns the number of pushes sent."""
        return self._deliver_batch(now)[1]

    def drain(self, now: datetime, *, max_batches: int = 40) -> int:
        """Deliver claimed batches until a batch comes back short (backlog empty), so a backlog
        larger than one claim drains in one pass instead of 50 jobs per poll (LT-13)."""
        delivered = 0
        for _ in range(max_batches):
            if self.stop_event.is_set():
                break
            claimed, sent = self._deliver_batch(now)
            delivered += sent
            if claimed < CLAIM_BATCH_SIZE:
                break
            now = datetime.now(UTC)
        return delivered

    def _deliver_batch(self, now: datetime) -> tuple[int, int]:
        job_ids = self._claim(now, CLAIM_BATCH_SIZE)
        delivered = 0
        for index, job_id in enumerate(job_ids):
            if self.stop_event.is_set():
                self._release_unstarted(job_ids[index:])
                break
            # One bad job (undecryptable token, missing row, transport error) must fail only
            # itself; before, the first exception aborted the pass and every other claimed job
            # ran out of attempts unsent (load audit LT-12).
            try:
                delivered += self._deliver_one(job_id, now)
            except Exception as exc:
                logger.warning(
                    "notification_job_failed", job_id=str(job_id), error_type=type(exc).__name__
                )
                try:
                    self._fail_job(job_id, type(exc).__name__, retry=False)
                except Exception:
                    logger.exception("notification_job_fail_record_failed", job_id=str(job_id))
        return len(job_ids), delivered

    def _deliver_one(self, job_id: UUID, now: datetime) -> int:
        with self.manager.session_scope() as session:
            job = session.get(schema.NotificationPushJob, job_id)
            if job is None or job.status != "sending":
                return 0
            if not self._eligible(session, job, now):
                job.status = "cancelled"
                job.lease_until = None
                return 0
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
        try:
            result: PushResult = self.sender.send(token, title, body, data)
        except Exception as exc:  # transport failure: retry with backoff like a failed send
            result = PushResult(success=False, error_code=type(exc).__name__)
        with self.manager.session_scope() as session:
            job = session.get(schema.NotificationPushJob, job_id)
            if job is None:
                return 0
            job.lease_until = None
            if result.success:
                job.status = "sent"
                job.sent_at = datetime.now(UTC)
                return 1
            if result.invalid_token:
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
        return 0

    def _release_unstarted(self, job_ids: list[UUID]) -> None:
        """On stop: claimed jobs that were not started go back to pending, due now, and the claim's
        attempt is refunded, so a deploy never costs a retry or delays a push by the lease time."""
        if not job_ids:
            return
        with self.manager.session_scope() as session:
            result = session.execute(
                update(schema.NotificationPushJob)
                .where(
                    schema.NotificationPushJob.id.in_(job_ids),
                    schema.NotificationPushJob.status == "sending",
                )
                .values(
                    status="pending",
                    lease_until=None,
                    next_attempt_at=datetime.now(UTC),
                    attempts=func.greatest(schema.NotificationPushJob.attempts - 1, 0),
                )
            )
        logger.info("notification_jobs_released_on_stop", count=result.rowcount)

    def _fail_job(self, job_id: UUID, error_code: str, *, retry: bool) -> None:
        with self.manager.session_scope() as session:
            job = session.get(schema.NotificationPushJob, job_id)
            if job is None:
                return
            job.lease_until = None
            job.last_error_code = error_code
            if retry and job.attempts < MAX_ATTEMPTS:
                job.status = "pending"
                job.next_attempt_at = datetime.now(UTC) + timedelta(
                    seconds=RETRY_DELAYS[job.attempts - 1]
                )
            else:
                job.status = "failed"

    def run_forever(self) -> None:
        last_scheduled = datetime.min.replace(tzinfo=UTC)
        while not self.stop_event.is_set():
            now = datetime.now(UTC)
            try:
                if now - last_scheduled >= timedelta(minutes=1):
                    self.enqueue_due_followups(now)
                    self.enqueue_inactivity(now)
                    last_scheduled = now
                self.drain(now)
            except Exception:
                logger.exception("notification_worker_pass_failed")
            self.stop_event.wait(POLL_SECONDS)  # wakes at once on SIGTERM
        logger.info("notification_worker_stopped")


def main() -> None:
    settings = get_settings()
    if not settings.push_token_encryption_key:
        raise RuntimeError("PUSH_TOKEN_ENCRYPTION_KEY is required for notification worker")
    sender = FcmSender(settings.firebase_credentials_file, settings.firebase_project_id)
    manager = DatabaseSessionManager(settings.database_url)
    worker = NotificationWorker(manager, settings, sender)
    worker.install_signal_handlers()
    worker.run_forever()


if __name__ == "__main__":
    main()
