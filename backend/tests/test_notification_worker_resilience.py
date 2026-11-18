"""Notification worker resilience (load audit LT-12/LT-13, FIX-8).

One bad row (an undecryptable device token, a sender exception) must fail only its own job, and a
backlog larger than one claim must drain in one pass instead of 50 jobs per 30 s.
"""

from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from cryptography.fernet import Fernet
from geoalchemy2.elements import WKTElement
from sqlalchemy import func, select

from app.core.config import Settings
from app.features.notifications.application.worker import NotificationWorker
from app.features.notifications.infrastructure.fcm import PushResult
from app.features.notifications.infrastructure.repository import NotificationRepository
from app.infrastructure.db.models import schema


class _Sender:
    def __init__(self, explode_for: set[str] | None = None) -> None:
        self.sent: list[str] = []
        self.explode_for = explode_for or set()

    def send(self, token, title, body, data) -> PushResult:
        if token in self.explode_for:
            raise RuntimeError("transport failure")
        self.sent.append(token)
        return PushResult(success=True)


def _backlog(db_session_manager, key: str, count: int) -> list[str]:
    """`count` users with one device and one pending comment push each; returns device tokens."""
    tokens: list[str] = []
    with db_session_manager.session_scope() as session:
        actor = schema.User(email=f"{uuid4()}@example.invalid", name="Actor")
        session.add(actor)
        session.flush()
        # Comment pushes are only delivered while the commented publication exists.
        target = schema.LostPet(
            user_id=actor.id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
            last_seen_location=WKTElement("POINT(69.2797 41.3111)", srid=4326),
        )
        session.add(target)
        session.flush()
        repo = NotificationRepository(session)
        for index in range(count):
            user = schema.User(email=f"{uuid4()}@example.invalid", name=f"U{index}")
            session.add(user)
            session.flush()
            token = f"device-token-{index:04d}-long-enough"
            repo.upsert_device(user.id, token, key)
            repo.create_event(
                recipient_id=user.id,
                actor_id=actor.id,
                kind="comment",
                target_kind="lost_pet",
                target_id=target.id,
                event_key=f"resilience-{index}",
                push_enabled=True,
            )
            tokens.append(token)
    return tokens


def _statuses(db_session_manager) -> dict[str, int]:
    with db_session_manager.session_scope() as session:
        rows = session.execute(
            select(schema.NotificationPushJob.status, func.count()).group_by(
                schema.NotificationPushJob.status
            )
        ).all()
    return {status: count for status, count in rows}


def test_corrupt_device_token_fails_only_its_own_job(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    tokens = _backlog(db_session_manager, key, 10)
    with db_session_manager.session_scope() as session:
        bad = session.scalars(select(schema.NotificationDevice).limit(1)).one()
        bad.token_encrypted = "not-a-fernet-token"  # e.g. after a key rotation
    sender = _Sender()
    worker = NotificationWorker(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)

    assert worker.deliver(datetime.now(UTC)) == 9
    assert len(sender.sent) == 9
    assert set(sender.sent) < set(tokens)
    statuses = _statuses(db_session_manager)
    assert statuses.get("sent") == 9
    assert statuses.get("failed") == 1
    with db_session_manager.session_scope() as session:
        failed = session.scalars(
            select(schema.NotificationPushJob).where(schema.NotificationPushJob.status == "failed")
        ).one()
        assert failed.last_error_code == "InvalidToken"
        assert failed.lease_until is None


def test_sender_exception_affects_only_its_own_job(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    tokens = _backlog(db_session_manager, key, 6)
    sender = _Sender(explode_for={tokens[2]})
    worker = NotificationWorker(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)

    assert worker.deliver(datetime.now(UTC)) == 5
    statuses = _statuses(db_session_manager)
    assert statuses.get("sent") == 5
    # A transport error is transient: the job is retried later, not dropped.
    assert statuses.get("pending") == 1


def test_drain_delivers_a_backlog_larger_than_one_claim(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    _backlog(db_session_manager, key, 120)
    sender = _Sender()
    worker = NotificationWorker(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)

    assert worker.drain(datetime.now(UTC)) == 120
    assert _statuses(db_session_manager) == {"sent": 120}
