"""Durable R2 object deletion (ADR-0025).

A request that makes stored media unreferenced (account deletion) records the object keys with
``enqueue_media_deletions`` in the same database transaction and returns. The notification worker
runs ``MediaDeletionProcessor.process`` on every pass: it claims due jobs with a lease, deletes each
object, and marks the job ``done``. A failed delete is retried with backoff; after
``MAX_ATTEMPTS`` the job is marked ``failed`` and one ``media_deletion_failed`` event is logged and
sent to PostHog, and failures are summarised to the ops Telegram chat at most once an hour. A
worker that dies mid-job leaves a lease that expires, so the job is picked up
again; deleting a missing object counts as success, so a repeat is harmless.
"""

from __future__ import annotations

import threading
import time
from collections import Counter
from collections.abc import Callable, Iterable
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from botocore.config import Config
from sqlalchemy import and_, delete, or_, select, update
from sqlalchemy.dialects.postgresql import insert
from structlog import get_logger

from app.core.storage import ObjectStorage
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)

MAX_ATTEMPTS = 6
# Delay before attempts 2..6 (seconds): 1 min, 5 min, 30 min, 2 h, 6 h. About 8.5 h in total.
RETRY_DELAYS = (60, 300, 1800, 7200, 21600)
LEASE_TIME = timedelta(minutes=5)
CLAIM_BATCH_SIZE = 25
DONE_RETENTION = timedelta(days=30)

# The photo pass shares the notification worker's loop, so it is bounded: at most
# MAX_JOBS_PER_PASS deletions and PASS_TIME_BUDGET_SECONDS per pass (checked before each call), and
# each R2 call is cut short by R2_CLIENT_CONFIG (one try; the job's own retries replace botocore's).
# Worst case, a pass delays the next notification drain by about 15 s + one call (3 s + 5 s).
MAX_JOBS_PER_PASS = 100
PASS_TIME_BUDGET_SECONDS = 15.0
R2_CLIENT_CONFIG = Config(
    connect_timeout=3,
    read_timeout=5,
    # total_max_attempts counts the first try; botocore's max_attempts would count retries only.
    retries={"mode": "standard", "total_max_attempts": 1},
    tcp_keepalive=True,
)
ALERT_MIN_INTERVAL_SECONDS = 3600.0

Capture = Callable[[str, dict[str, Any]], None]
Alert = Callable[[str], object]


def enqueue_media_deletions(session, keys: Iterable[str | None], *, reason: str) -> int:
    """Record keys to delete, inside the caller's transaction. Returns the number of new jobs."""
    unique = sorted({key for key in keys if key})
    if not unique:
        return 0
    result = session.execute(
        insert(schema.MediaDeletionJob)
        .values([{"object_key": key, "reason": reason} for key in unique])
        .on_conflict_do_nothing(index_elements=["object_key"])
    )
    return result.rowcount or 0


class MediaDeletionProcessor:
    def __init__(
        self,
        manager: DatabaseSessionManager,
        storage: ObjectStorage,
        *,
        capture: Capture | None = None,
        alert: Alert | None = None,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        self.manager = manager
        self.storage = storage
        self.capture = capture
        self.alert = alert
        self._monotonic = monotonic
        self._unalerted: Counter[str] = Counter()
        self._last_alert_at: float | None = None

    def process(
        self,
        now: datetime,
        stop_event: threading.Event | None = None,
        *,
        max_jobs: int = MAX_JOBS_PER_PASS,
        time_budget: float = PASS_TIME_BUDGET_SECONDS,
    ) -> int:
        """Delete due objects within the per-pass caps, or until a stop. Returns deletions."""
        started = self._monotonic()
        self._give_up_expired_leases(now)
        self._purge_done(now)
        deleted = handled = 0
        try:
            while handled < max_jobs:
                claimed = self._claim(now, min(CLAIM_BATCH_SIZE, max_jobs - handled))
                if not claimed:
                    break
                for index, (job_id, key) in enumerate(claimed):
                    stopping = stop_event is not None and stop_event.is_set()
                    if stopping or self._monotonic() - started >= time_budget:
                        self._release([jid for jid, _ in claimed[index:]])
                        return deleted
                    deleted += self._delete_one(job_id, key)
                    handled += 1
                now = datetime.now(UTC)
            return deleted
        finally:
            self._send_alert()

    def _claim(self, now: datetime, limit: int = CLAIM_BATCH_SIZE) -> list[tuple[UUID, str]]:
        job = schema.MediaDeletionJob
        with self.manager.session_scope() as session:
            rows = session.scalars(
                select(job)
                .where(
                    job.attempts < MAX_ATTEMPTS,
                    or_(
                        and_(job.status == "pending", job.next_attempt_at <= now),
                        and_(job.status == "deleting", job.lease_until <= now),
                    ),
                )
                .order_by(job.next_attempt_at, job.id)
                .limit(limit)
                .with_for_update(skip_locked=True)
            ).all()
            for row in rows:
                row.status = "deleting"
                row.lease_until = now + LEASE_TIME
                row.attempts += 1
            return [(row.id, row.object_key) for row in rows]

    def _delete_one(self, job_id: UUID, key: str) -> int:
        try:
            self.storage.delete(key)
        except Exception as exc:  # any storage failure is retried; never crash the worker
            cause = exc.__cause__ or exc
            self._fail(job_id, type(cause).__name__)
            return 0
        with self.manager.session_scope() as session:
            row = session.get(schema.MediaDeletionJob, job_id)
            if row is not None:
                row.status = "done"
                row.completed_at = datetime.now(UTC)
                row.lease_until = None
                row.last_error_code = None
        return 1

    def _fail(self, job_id: UUID, error_code: str) -> None:
        with self.manager.session_scope() as session:
            row = session.get(schema.MediaDeletionJob, job_id)
            if row is None:
                return
            row.lease_until = None
            row.last_error_code = error_code
            if row.attempts < MAX_ATTEMPTS:
                row.status = "pending"
                row.next_attempt_at = datetime.now(UTC) + timedelta(
                    seconds=RETRY_DELAYS[row.attempts - 1]
                )
                logger.warning(
                    "media_deletion_retry",
                    job_id=str(job_id),
                    attempts=row.attempts,
                    error_code=error_code,
                )
                return
            row.status = "failed"
            reason, attempts = row.reason, row.attempts
        self._report_failed(job_id, reason, attempts, error_code)

    def _give_up_expired_leases(self, now: datetime) -> None:
        """A job whose last attempt was interrupted (worker killed) cannot be claimed again."""
        job = schema.MediaDeletionJob
        with self.manager.session_scope() as session:
            rows = session.scalars(
                select(job)
                .where(
                    job.status == "deleting",
                    job.lease_until <= now,
                    job.attempts >= MAX_ATTEMPTS,
                )
                .with_for_update(skip_locked=True)
            ).all()
            failed = []
            for row in rows:
                row.status = "failed"
                row.lease_until = None
                row.last_error_code = "LEASE_EXPIRED"
                failed.append((row.id, row.reason, row.attempts))
        for job_id, reason, attempts in failed:
            self._report_failed(job_id, reason, attempts, "LEASE_EXPIRED")

    def _report_failed(self, job_id: UUID, reason: str, attempts: int, error_code: str) -> None:
        # The key stays in the job row (status 'failed') for a manual retry; it is not sent out.
        properties = {"reason": reason, "attempts": attempts, "error_code": error_code}
        logger.error("media_deletion_failed", job_id=str(job_id), **properties)
        self._unalerted[error_code] += 1
        if self.capture is not None:
            try:
                self.capture("media_deletion_failed", properties)
            except Exception as exc:
                logger.warning("media_deletion_event_failed", error_type=type(exc).__name__)

    def _send_alert(self) -> None:
        """One Telegram summary for the give-ups so far, at most once an hour (never raises)."""
        if not self._unalerted or self.alert is None:
            return
        now = self._monotonic()
        if (
            self._last_alert_at is not None
            and now - self._last_alert_at < ALERT_MIN_INTERVAL_SECONDS
        ):
            return
        total = sum(self._unalerted.values())
        codes = ", ".join(f"{code} x{n}" for code, n in self._unalerted.most_common())
        text = (
            f"Media deletion gave up on {total} R2 object(s) after {MAX_ATTEMPTS} attempts "
            f"({codes}). The keys are kept in media_deletion_jobs (status failed); "
            "requeue with the command in docs/IMAGE_STORAGE.md."
        )
        try:
            delivered = self.alert(text) is not False  # TelegramOpsNotifier.send returns a bool
        except Exception as exc:
            logger.warning("media_deletion_alert_failed", error_type=type(exc).__name__)
            delivered = False
        if not delivered:
            return  # kept: the next pass tries again
        self._unalerted.clear()
        self._last_alert_at = now

    def _release(self, job_ids: list[UUID]) -> None:
        """Put claimed jobs that were not started back, without spending an attempt."""
        if not job_ids:
            return
        job = schema.MediaDeletionJob
        with self.manager.session_scope() as session:
            session.execute(
                update(job)
                .where(job.id.in_(job_ids), job.status == "deleting")
                .values(status="pending", lease_until=None, attempts=job.attempts - 1)
            )

    def _purge_done(self, now: datetime) -> None:
        job = schema.MediaDeletionJob
        with self.manager.session_scope() as session:
            session.execute(
                delete(job).where(job.status == "done", job.completed_at < now - DONE_RETENTION)
            )
