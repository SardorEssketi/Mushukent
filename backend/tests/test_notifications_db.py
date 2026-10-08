from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from cryptography.fernet import Fernet
from fastapi import HTTPException
from geoalchemy2.elements import WKTElement
from pydantic import ValidationError
from sqlalchemy import func, select

from app.core.config import Settings
from app.features.auth.domain.models import AuthUser
from app.features.cats.domain.models import CatStatus
from app.features.comments.application.schemas import CommentCreate
from app.features.comments.application.service import CommentsService
from app.features.comments.infrastructure.repositories import SqlAlchemyCommentRepository
from app.features.notifications.application.schemas import PreferencePatch
from app.features.notifications.application.service import NotificationService
from app.features.notifications.application.worker import NotificationWorker
from app.features.notifications.infrastructure.fcm import PushResult
from app.features.notifications.infrastructure.repository import NotificationRepository
from app.infrastructure.db.models import schema


def _user(session, name: str) -> schema.User:
    user = schema.User(email=f"{uuid4()}@example.invalid", name=name)
    session.add(user)
    session.flush()
    return user


def _auth(user: schema.User) -> AuthUser:
    return AuthUser(id=user.id, email=user.email, password_hash=None, name=user.name)


@pytest.mark.parametrize(
    "field",
    (
        "push_comments",
        "push_replies",
        "push_followups",
        "nearby_enabled",
        "inactivity_enabled",
        "alert_location",
    ),
)
def test_explicit_null_preference_is_rejected(field: str) -> None:
    with pytest.raises(ValidationError):
        PreferencePatch.model_validate({field: None})


def test_partial_or_invalid_production_push_configuration_fails(tmp_path) -> None:
    with pytest.raises(ValueError, match="FCM push requires"):
        Settings(_env_file=None, APP_ENV="production", FIREBASE_PROJECT_ID="test-project")

    credential_path = tmp_path / "not-a-real-service-account.json"
    credential_path.write_text("{}", encoding="utf-8")
    with pytest.raises(ValueError, match="PUSH_TOKEN_ENCRYPTION_KEY"):
        Settings(
            _env_file=None,
            APP_ENV="production",
            FIREBASE_PROJECT_ID="test-project",
            FIREBASE_CREDENTIALS_FILE=str(credential_path),
            PUSH_TOKEN_ENCRYPTION_KEY="invalid",
        )
    with pytest.raises(ValueError, match="valid service account"):
        Settings(
            _env_file=None,
            APP_ENV="production",
            FIREBASE_PROJECT_ID="test-project",
            FIREBASE_CREDENTIALS_FILE=str(credential_path),
            PUSH_TOKEN_ENCRYPTION_KEY=Fernet.generate_key().decode(),
        )


def test_comment_reply_inbox_dedup_and_read(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        actor = _user(session, "Actor")
        pet = schema.LostPet(
            user_id=owner.id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
            last_seen_location=WKTElement("POINT(69.2797 41.3111)", srid=4326),
        )
        session.add(pet)
        session.flush()
        owner_id, actor_id, pet_id = owner.id, actor.id, pet.id
        owner_auth, actor_auth = _auth(owner), _auth(actor)

    service = CommentsService(
        settings=Settings(),
        db_session_manager=db_session_manager,
        repository_factory=SqlAlchemyCommentRepository,
        user_repository_factory=lambda session: None,
        notification_repository_factory=NotificationRepository,
    )
    first = service.create_lost_pet_comment(
        pet_id, actor_auth, CommentCreate(content="Seen nearby")
    )
    owner_reply = service.create_lost_pet_comment(
        pet_id,
        owner_auth,
        CommentCreate(content="Thanks", parent_comment_id=first.id),
    )
    with db_session_manager.session_scope() as session:
        rows = session.scalars(
            select(schema.Notification).order_by(schema.Notification.created_at)
        ).all()
        assert len(rows) == 2
        assert {(row.recipient_id, row.kind) for row in rows} == {
            (owner_id, "comment"),
            (actor_id, "reply"),
        }
        assert all(row.actor_id != row.recipient_id for row in rows)
        assert NotificationRepository(session).unread_count(owner_id) == 1

    service.create_lost_pet_comment(
        pet_id,
        actor_auth,
        CommentCreate(content="Yes", parent_comment_id=first.id),
    )
    with db_session_manager.session_scope() as session:
        # A reply to the actor's own direct parent is a self-action.
        assert session.scalar(select(func.count(schema.Notification.id))) == 2

    service.create_lost_pet_comment(
        pet_id,
        actor_auth,
        CommentCreate(content="Another", parent_comment_id=owner_reply.id),
    )
    # Owner is both content owner and direct-parent author: one reply event.
    assert NotificationService(db_session_manager, Settings()).unread_count(owner_id) == 2


def test_rehoming_comment_notifies_owner(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        actor = _user(session, "Actor")
        post = schema.AdoptionPost(
            user_id=owner.id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
        )
        session.add(post)
        session.flush()
        owner_id, post_id, actor_auth = owner.id, post.id, _auth(actor)

    service = CommentsService(
        settings=Settings(),
        db_session_manager=db_session_manager,
        repository_factory=SqlAlchemyCommentRepository,
        user_repository_factory=lambda session: None,
        notification_repository_factory=NotificationRepository,
    )
    service.create_adoption_post_comment(post_id, actor_auth, CommentCreate(content="Interested"))
    page = NotificationService(db_session_manager, Settings()).list_notifications(
        owner_id, 20, None
    )
    assert len(page.items) == 1
    assert page.items[0].target_kind == "adoption_post"


def test_observation_comment_notifies_owner(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        actor = _user(session, "Actor")
        cat = schema.Cat(status=CatStatus.UNKNOWN, name="Cat")
        session.add(cat)
        session.flush()
        post = schema.Post(
            cat_id=cat.id,
            user_id=owner.id,
            photo_url="https://example.invalid/cat.jpg",
        )
        session.add(post)
        session.flush()
        owner_id, post_id, actor_auth = owner.id, post.id, _auth(actor)

    service = CommentsService(
        settings=Settings(),
        db_session_manager=db_session_manager,
        repository_factory=SqlAlchemyCommentRepository,
        user_repository_factory=lambda session: None,
        notification_repository_factory=NotificationRepository,
    )
    service.create_comment(post_id, actor_auth, CommentCreate(content="Nice cat"))
    page = NotificationService(db_session_manager, Settings()).list_notifications(
        owner_id, 20, None
    )
    assert len(page.items) == 1
    assert page.items[0].target_kind == "post"


def test_private_alert_point_and_500_meter_boundary(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        inside = _user(session, "Inside")
        edge = _user(session, "Edge")
        outside = _user(session, "Outside")
        disabled = _user(session, "Disabled")
        repo = NotificationRepository(session)
        for user, latitude, enabled in (
            (inside, 0.0044, True),
            (edge, 0.00449, True),
            (outside, 0.0046, True),
            (disabled, 0.0, False),
            (owner, 0.0, True),
        ):
            pref = repo.preferences(user.id)
            repo.set_alert_location(pref, latitude, 0.0)
            session.flush()
            pref.nearby_enabled = enabled
        session.flush()
        matched = set(repo.nearby_recipients(latitude=0.0, longitude=0.0, owner_id=owner.id))
        assert matched == {inside.id, edge.id}
        assert outside.id not in matched and disabled.id not in matched
        assert repo.get_alert_location(inside.id) == (0.0044, 0.0)
        pet = schema.LostPet(
            user_id=owner.id,
            pet_name="Nearby pet",
            owner_phone_number="+998901234567",
            last_seen_location=WKTElement("POINT(0 0)", srid=4326),
        )
        session.add(pet)
        session.flush()
        assert repo.create_nearby_events(lost_pet_id=pet.id, recipient_ids=list(matched)) == 2
        assert repo.create_nearby_events(lost_pet_id=pet.id, recipient_ids=list(matched)) == 0
        assert set(session.scalars(select(schema.Notification.recipient_id)).all()) == matched
        owner_id = owner.id
        inside_id = inside.id

    service = NotificationService(db_session_manager, Settings())
    result = service.update_preferences(inside_id, PreferencePatch(nearby_enabled=False))
    assert result.alert_location is None and not result.nearby_enabled
    with db_session_manager.session_scope() as session:
        assert inside_id not in NotificationRepository(session).nearby_recipients(
            latitude=0.0, longitude=0.0, owner_id=owner_id
        )


def test_nearby_job_is_cancelled_when_pet_becomes_private(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        recipient = _user(session, "Recipient")
        pet = schema.LostPet(
            user_id=owner.id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
            last_seen_location=WKTElement("POINT(69.2797 41.3111)", srid=4326),
        )
        session.add(pet)
        session.flush()
        repo = NotificationRepository(session)
        preference = repo.preferences(recipient.id)
        repo.set_alert_location(preference, 41.3111, 69.2797)
        preference.nearby_enabled = True
        repo.upsert_device(recipient.id, "private-pet-test-device-token", key)
        repo.create_nearby_events(lost_pet_id=pet.id, recipient_ids=[recipient.id])
        pet.is_public = False

    sender = _FakeSender()
    worker = NotificationWorker(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)
    assert worker.deliver(datetime.now(UTC)) == 0
    assert sender.calls == 0
    with db_session_manager.session_scope() as session:
        assert session.scalar(select(schema.NotificationPushJob.status)) == "cancelled"


class _FakeSender:
    def __init__(self, result: PushResult = PushResult(success=True)) -> None:
        self.result = result
        self.calls = 0

    def send(self, token, title, body, data) -> PushResult:
        self.calls += 1
        assert "phone" not in data and "latitude" not in data and "longitude" not in data
        return self.result


def test_inactivity_once_per_period_and_activity_reset(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    now = datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        user = _user(session, "Inactive")
        user.last_active_at = now - timedelta(days=7, minutes=15, seconds=1)
        repo = NotificationRepository(session)
        repo.preferences(user.id).inactivity_enabled = True
        repo.upsert_device(user.id, "test-device-token-long-enough", key)
        user_id = user.id

    worker = NotificationWorker(
        db_session_manager,
        Settings(PUSH_TOKEN_ENCRYPTION_KEY=key),
        _FakeSender(),
    )
    assert worker.enqueue_inactivity(now) == 1
    assert worker.enqueue_inactivity(now) == 0
    assert worker.deliver(datetime.now(UTC)) == 1
    assert worker.enqueue_inactivity(now + timedelta(days=1)) == 0
    with db_session_manager.session_scope() as session:
        user = session.get(schema.User, user_id)
        user.last_active_at = now + timedelta(seconds=1)
    assert worker.enqueue_inactivity(now + timedelta(days=8)) == 1


def test_due_followup_one_job_per_device_and_completed_cycle_cancelled(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    now = datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        pet = schema.LostPet(
            user_id=owner.id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
            last_seen_location=WKTElement("POINT(69.2797 41.3111)", srid=4326),
        )
        session.add(pet)
        session.flush()
        followup = schema.LostPetFollowUp(
            lost_pet_id=pet.id, owner_id=owner.id, due_at=now - timedelta(minutes=1)
        )
        session.add(followup)
        NotificationRepository(session).upsert_device(
            owner.id, "test-followup-token-long-enough", key
        )
        session.flush()
        followup_id = followup.id

    sender = _FakeSender()
    worker = NotificationWorker(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)
    assert worker.enqueue_due_followups(now) == 1
    assert worker.enqueue_due_followups(now) == 0
    with db_session_manager.session_scope() as session:
        followup = session.get(schema.LostPetFollowUp, followup_id)
        followup.completed_at = now
        followup.answer_yes = False
    assert worker.deliver(datetime.now(UTC)) == 0
    assert sender.calls == 0


def test_due_rehoming_followup_uses_existing_cycle(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    now = datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        post = schema.AdoptionPost(
            user_id=owner.id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
        )
        session.add(post)
        session.flush()
        followup = schema.AdoptionFollowUp(
            adoption_post_id=post.id,
            owner_id=owner.id,
            due_at=now - timedelta(minutes=1),
        )
        session.add(followup)
        NotificationRepository(session).upsert_device(owner.id, "test-adoption-followup-token", key)

    sender = _FakeSender()
    worker = NotificationWorker(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)
    assert worker.enqueue_due_followups(now) == 1
    assert worker.enqueue_due_followups(now) == 0
    assert worker.deliver(datetime.now(UTC)) == 1
    assert sender.calls == 1
    with db_session_manager.session_scope() as session:
        job = session.scalar(select(schema.NotificationPushJob))
        assert job.kind == "adoption_followup" and job.status == "sent"


def test_inbox_is_recipient_scoped_paginated_and_readable(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        first = _user(session, "First")
        second = _user(session, "Second")
        repo = NotificationRepository(session)
        for number in range(3):
            repo.create_event(
                recipient_id=first.id,
                actor_id=second.id,
                kind="comment",
                target_kind="post",
                target_id=uuid4(),
                event_key=f"test-inbox-{number}",
                push_enabled=False,
            )
        first_id, second_id = first.id, second.id

    service = NotificationService(db_session_manager, Settings())
    page = service.list_notifications(first_id, 2, None)
    assert len(page.items) == 2 and page.next_cursor
    later = service.list_notifications(first_id, 2, page.next_cursor)
    assert len(later.items) == 1
    assert {item.id for item in page.items}.isdisjoint({item.id for item in later.items})
    assert service.list_notifications(second_id, 20, None).items == []
    assert service.unread_count(first_id) == 3
    with pytest.raises(HTTPException) as forbidden:
        service.mark_read(second_id, page.items[0].id)
    assert forbidden.value.status_code == 404
    service.mark_read(first_id, page.items[0].id)
    assert service.unread_count(first_id) == 2
    assert service.mark_all_read(first_id) == 2
    assert service.unread_count(first_id) == 0
    with pytest.raises(HTTPException) as bad_cursor:
        service.list_notifications(first_id, 20, "not-a-cursor")
    assert bad_cursor.value.status_code == 422


def test_token_rebind_drops_previous_account_jobs_and_invalid_token_retires(
    db_session_manager,
) -> None:
    key = Fernet.generate_key().decode()
    token = "long-device-token-for-rebind"
    with db_session_manager.session_scope() as session:
        first = _user(session, "First")
        second = _user(session, "Second")
        repo = NotificationRepository(session)
        repo.upsert_device(first.id, token, key)
        repo.create_event(
            recipient_id=first.id,
            actor_id=second.id,
            kind="comment",
            target_kind="post",
            target_id=uuid4(),
            event_key="token-rebind-test",
            push_enabled=True,
        )
        assert session.scalar(select(func.count(schema.NotificationPushJob.id))) == 1
        repo.upsert_device(second.id, token, key)
        second_id = second.id
        assert session.scalar(select(func.count(schema.NotificationPushJob.id))) == 0
        assert session.scalar(select(schema.NotificationDevice.user_id)) == second_id

    with db_session_manager.session_scope() as session:
        pet = schema.LostPet(
            user_id=second_id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
            last_seen_location=WKTElement("POINT(69.2797 41.3111)", srid=4326),
        )
        session.add(pet)
        session.flush()
        repo = NotificationRepository(session)
        repo.create_event(
            recipient_id=second_id,
            actor_id=None,
            kind="nearby_lost_pet",
            target_kind="lost_pet",
            target_id=pet.id,
            event_key="invalid-token-test",
            push_enabled=True,
        )
        repo.preferences(second_id).nearby_enabled = True
        repo.set_alert_location(repo.preferences(second_id), 41.3111, 69.2797)

    worker = NotificationWorker(
        db_session_manager,
        Settings(PUSH_TOKEN_ENCRYPTION_KEY=key),
        _FakeSender(PushResult(success=False, invalid_token=True, error_code="UnregisteredError")),
    )
    worker.deliver(datetime.now(UTC))
    with db_session_manager.session_scope() as session:
        assert session.scalar(select(schema.NotificationDevice)) is None
        assert session.scalar(select(schema.NotificationPushJob)) is None


def test_token_rotation_is_atomic_and_cannot_remove_another_users_token(
    db_session_manager, monkeypatch
) -> None:
    key = Fernet.generate_key().decode()
    monkeypatch.setattr(NotificationService, "push_available", property(lambda self: True))
    with db_session_manager.session_scope() as session:
        first = _user(session, "First")
        second = _user(session, "Second")
        first_id, second_id = first.id, second.id

    service = NotificationService(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key))
    first_token = "first-account-token-old-enough"
    rotated_token = "first-account-token-new-enough"
    other_token = "second-account-token-long-enough"
    service.register_device(first_id, first_token)
    service.register_device(second_id, other_token)
    service.register_device(first_id, rotated_token, first_token)
    service.register_device(first_id, rotated_token, other_token)
    with db_session_manager.session_scope() as session:
        devices = session.scalars(select(schema.NotificationDevice)).all()
        assert len(devices) == 2
        assert {device.user_id for device in devices} == {first_id, second_id}
        assert {
            Fernet(key.encode()).decrypt(device.token_encrypted.encode()).decode()
            for device in devices
        } == {
            rotated_token,
            other_token,
        }


def test_expired_final_lease_is_terminal(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    now = datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        user = _user(session, "Owner")
        repo = NotificationRepository(session)
        repo.upsert_device(user.id, "test-final-lease-token-long", key)
        device = session.scalar(select(schema.NotificationDevice))
        job = schema.NotificationPushJob(
            recipient_id=user.id,
            device_id=device.id,
            event_key="final-lease-test",
            kind="inactivity",
            status="sending",
            attempts=4,
            lease_until=now - timedelta(seconds=1),
        )
        session.add(job)
        session.flush()
        job_id = job.id

    worker = NotificationWorker(
        db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), _FakeSender()
    )
    assert worker._claim(now) == []
    with db_session_manager.session_scope() as session:
        job = session.get(schema.NotificationPushJob, job_id)
        assert job.status == "failed" and job.attempts == 4


def test_second_worker_skips_locked_or_leased_job(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    with db_session_manager.session_scope() as session:
        user = _user(session, "Owner")
        NotificationRepository(session).upsert_device(user.id, "locked-job-device-token-long", key)
        device = session.scalar(select(schema.NotificationDevice))
        job = schema.NotificationPushJob(
            recipient_id=user.id,
            device_id=device.id,
            event_key="locked-job-test",
            kind="inactivity",
        )
        session.add(job)
        session.flush()
        job_id = job.id

    worker = NotificationWorker(
        db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), _FakeSender()
    )
    with db_session_manager.session_scope() as session:
        session.scalar(
            select(schema.NotificationPushJob)
            .where(schema.NotificationPushJob.id == job_id)
            .with_for_update()
        )
        assert worker._claim(datetime.now(UTC)) == []
    assert worker._claim(datetime.now(UTC)) == [job_id]
    assert worker._claim(datetime.now(UTC)) == []
    with db_session_manager.session_scope() as session:
        job = session.get(schema.NotificationPushJob, job_id)
        assert job.status == "sending" and job.attempts == 1


def test_fcm_failure_does_not_rollback_comment_or_inbox(db_session_manager) -> None:
    key = Fernet.generate_key().decode()
    with db_session_manager.session_scope() as session:
        owner = _user(session, "Owner")
        actor = _user(session, "Actor")
        pet = schema.LostPet(
            user_id=owner.id,
            pet_name="Pet",
            owner_phone_number="+998901234567",
            last_seen_location=WKTElement("POINT(69.2797 41.3111)", srid=4326),
        )
        session.add(pet)
        session.flush()
        owner_id, pet_id, actor_auth = owner.id, pet.id, _auth(actor)
        NotificationRepository(session).upsert_device(owner.id, "failed-fcm-device-token", key)

    service = CommentsService(
        settings=Settings(),
        db_session_manager=db_session_manager,
        repository_factory=SqlAlchemyCommentRepository,
        user_repository_factory=lambda session: None,
        notification_repository_factory=NotificationRepository,
    )
    comment = service.create_lost_pet_comment(pet_id, actor_auth, CommentCreate(content="I saw it"))
    sender = _FakeSender(PushResult(success=False, error_code="Unavailable"))
    worker = NotificationWorker(db_session_manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)
    assert worker.deliver(datetime.now(UTC)) == 0
    assert sender.calls == 1
    with db_session_manager.session_scope() as session:
        assert session.get(schema.Comment, comment.id) is not None
        assert NotificationRepository(session).unread_count(owner_id) == 1
        job = session.scalar(select(schema.NotificationPushJob))
        assert job.status == "pending" and job.attempts == 1
