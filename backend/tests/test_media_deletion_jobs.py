"""Durable R2 deletion after account deletion (ADR-0025): jobs, retries, give-up and restarts."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest
from fastapi.testclient import TestClient
from geoalchemy2 import WKTElement
from sqlalchemy import select

from app.core.storage import StorageOperationError
from app.infrastructure.db.models import schema
from app.infrastructure.storage import deletion_jobs
from app.infrastructure.storage.deletion_jobs import (
    MAX_ATTEMPTS,
    MediaDeletionProcessor,
    enqueue_media_deletions,
)
from app.infrastructure.storage.service import MediaStorageService
from tests.test_users import (  # noqa: F401 (fixtures)
    AvatarObjectStorage,
    _create_user_with_token,
    client,
    users_runtime,
)

MEDIA = "https://media.example"


class FakeR2:
    def __init__(self, failing: set[str] | None = None) -> None:
        self.failing = failing or set()
        self.deleted: list[str] = []
        self.calls = 0

    def delete(self, key: str) -> None:
        self.calls += 1
        if key in self.failing:
            raise StorageOperationError("r2 unavailable") from TimeoutError()
        self.deleted.append(key)


def _jobs(manager) -> dict[str, schema.MediaDeletionJob]:
    with manager.session_scope() as session:
        rows = session.scalars(select(schema.MediaDeletionJob)).all()
        session.expunge_all()
        return {row.object_key: row for row in rows}


def _enqueue(manager, keys: list[str]) -> None:
    with manager.session_scope() as session:
        enqueue_media_deletions(session, keys, reason="account_deletion")


def _later(hours: float = 0, minutes: float = 0) -> datetime:
    return datetime.now(UTC) + timedelta(hours=hours, minutes=minutes)


def test_account_deletion_records_photos_and_does_not_call_r2(
    client: TestClient, users_runtime  # noqa: F811
) -> None:
    manager = users_runtime.db_session_manager
    user, token = _create_user_with_token(
        manager, users_runtime.token_service, email="jobs-delete@example.com"
    )
    storage = AvatarObjectStorage()
    users_runtime.users_service.media_storage_service = MediaStorageService(storage=storage)
    with manager.session_scope() as session:
        session.get(schema.User, user.id).avatar_url = f"{MEDIA}/users/avatars/a.jpg"
        cat = schema.Cat(status=schema.CatStatus.UNKNOWN, name="C", created_by=user.id)
        session.add(cat)
        session.flush()
        post = schema.Post(
            cat_id=cat.id,
            user_id=user.id,
            photo_url=f"{MEDIA}/posts/original/p0.jpg",
            thumb_url=f"{MEDIA}/posts/thumb/p0.jpg",
            location=WKTElement("POINT(69.25 41.30)", srid=4326),
        )
        session.add(post)
        session.flush()
        for i in range(3):
            session.add(
                schema.PostPhoto(
                    post_id=post.id,
                    photo_url=f"{MEDIA}/posts/original/p{i}.jpg",
                    thumb_url=f"{MEDIA}/posts/thumb/p{i}.jpg",
                    position=i,
                )
            )
        # Not ours: never recorded, never deleted.
        session.add(
            schema.PostPhoto(
                post_id=post.id, photo_url="https://evil.example/posts/x.jpg", position=3
            )
        )

    response = client.delete("/api/v1/users/me", headers={"Authorization": f"Bearer {token}"})

    assert response.status_code == 204 and not response.content  # unchanged contract
    assert storage.deleted_keys == []  # no R2 call inside the request
    jobs = _jobs(manager)
    assert set(jobs) == {
        "users/avatars/a.jpg",
        *(f"posts/original/p{i}.jpg" for i in range(3)),
        *(f"posts/thumb/p{i}.jpg" for i in range(3)),
    }
    assert all(j.status == "pending" and j.reason == "account_deletion" for j in jobs.values())


def test_processor_deletes_and_marks_done(db_session_manager) -> None:
    _enqueue(db_session_manager, ["posts/a.jpg", "posts/b.jpg", None, "posts/a.jpg"])
    r2 = FakeR2()
    processor = MediaDeletionProcessor(db_session_manager, r2)

    assert processor.process(datetime.now(UTC)) == 2
    assert sorted(r2.deleted) == ["posts/a.jpg", "posts/b.jpg"]
    jobs = _jobs(db_session_manager)
    assert {j.status for j in jobs.values()} == {"done"}
    assert all(j.completed_at is not None and j.attempts == 1 for j in jobs.values())
    assert processor.process(_later(hours=1)) == 0  # nothing due: no repeat calls
    assert r2.calls == 2


def test_enqueue_ignores_keys_already_recorded(db_session_manager) -> None:
    _enqueue(db_session_manager, ["posts/a.jpg"])
    _enqueue(db_session_manager, ["posts/a.jpg", "posts/b.jpg"])
    assert set(_jobs(db_session_manager)) == {"posts/a.jpg", "posts/b.jpg"}


def test_r2_failure_is_retried_with_backoff_then_succeeds(db_session_manager) -> None:
    _enqueue(db_session_manager, ["posts/flaky.jpg"])
    r2 = FakeR2(failing={"posts/flaky.jpg"})
    processor = MediaDeletionProcessor(db_session_manager, r2)

    processor.process(datetime.now(UTC))
    job = _jobs(db_session_manager)["posts/flaky.jpg"]
    assert (job.status, job.attempts, job.last_error_code) == ("pending", 1, "TimeoutError")
    assert job.next_attempt_at > _later(minutes=0.9)  # first delay is 60 s

    assert processor.process(datetime.now(UTC)) == 0  # not due yet: no call
    assert r2.calls == 1

    r2.failing.clear()
    assert processor.process(_later(minutes=2)) == 1
    job = _jobs(db_session_manager)["posts/flaky.jpg"]
    assert (job.status, job.attempts) == ("done", 2)


def test_gives_up_after_max_attempts_with_one_event(db_session_manager) -> None:
    _enqueue(db_session_manager, ["posts/gone.jpg"])
    events: list[tuple[str, dict]] = []
    r2 = FakeR2(failing={"posts/gone.jpg"})
    processor = MediaDeletionProcessor(
        db_session_manager, r2, capture=lambda e, p: events.append((e, p))
    )

    for _ in range(MAX_ATTEMPTS + 3):
        processor.process(_later(hours=24 * 7))

    job = _jobs(db_session_manager)["posts/gone.jpg"]
    assert (job.status, job.attempts) == ("failed", MAX_ATTEMPTS)
    assert r2.calls == MAX_ATTEMPTS
    assert events == [
        (
            "media_deletion_failed",
            {"reason": "account_deletion", "attempts": MAX_ATTEMPTS, "error_code": "TimeoutError"},
        )
    ]  # one event, and no object key in it


def test_a_killed_worker_leaves_a_lease_that_expires(db_session_manager) -> None:
    _enqueue(db_session_manager, ["posts/a.jpg"])
    r2 = FakeR2()
    crashed = MediaDeletionProcessor(db_session_manager, r2)
    now = datetime.now(UTC)
    assert crashed._claim(now)  # claimed, then the process dies before deleting

    fresh = MediaDeletionProcessor(db_session_manager, r2)
    assert fresh.process(now + timedelta(minutes=1)) == 0  # lease still held
    assert fresh.process(now + deletion_jobs.LEASE_TIME + timedelta(seconds=1)) == 1
    job = _jobs(db_session_manager)["posts/a.jpg"]
    assert (job.status, job.attempts) == ("done", 2)


def test_lease_expiry_on_the_last_attempt_gives_up(db_session_manager) -> None:
    _enqueue(db_session_manager, ["posts/a.jpg"])
    with db_session_manager.session_scope() as session:
        job = session.scalars(select(schema.MediaDeletionJob)).one()
        job.attempts = MAX_ATTEMPTS - 1
    events: list = []
    processor = MediaDeletionProcessor(
        db_session_manager, FakeR2(), capture=lambda e, p: events.append(p)
    )
    now = datetime.now(UTC)
    assert processor._claim(now)
    processor.process(now + deletion_jobs.LEASE_TIME + timedelta(seconds=1))
    assert _jobs(db_session_manager)["posts/a.jpg"].status == "failed"
    assert events[0]["error_code"] == "LEASE_EXPIRED"


def test_stop_releases_unstarted_jobs_without_spending_an_attempt(db_session_manager) -> None:
    import threading

    _enqueue(db_session_manager, [f"posts/{i}.jpg" for i in range(5)])
    stop = threading.Event()

    class StopAfterTwo(FakeR2):
        def delete(self, key: str) -> None:
            super().delete(key)
            if len(self.deleted) == 2:
                stop.set()

    r2 = StopAfterTwo()
    assert MediaDeletionProcessor(db_session_manager, r2).process(datetime.now(UTC), stop) == 2
    jobs = _jobs(db_session_manager).values()
    assert sorted(j.status for j in jobs) == ["done", "done", "pending", "pending", "pending"]
    assert all(j.attempts == 0 for j in jobs if j.status == "pending")
    assert all(j.lease_until is None for j in jobs)


def test_done_jobs_are_purged_after_the_retention(db_session_manager) -> None:
    _enqueue(db_session_manager, ["posts/old.jpg"])
    processor = MediaDeletionProcessor(db_session_manager, FakeR2())
    processor.process(datetime.now(UTC))
    processor.process(_later(hours=24 * 31))
    assert _jobs(db_session_manager) == {}


@pytest.mark.parametrize("failing", [True, False])
def test_capture_failure_never_breaks_the_worker(db_session_manager, failing) -> None:
    _enqueue(db_session_manager, ["posts/x.jpg"])

    def boom(event, properties):
        raise RuntimeError("posthog down")

    processor = MediaDeletionProcessor(
        db_session_manager, FakeR2(failing={"posts/x.jpg"} if failing else set()), capture=boom
    )
    for _ in range(MAX_ATTEMPTS):
        processor.process(_later(hours=24 * 7))
    expected = "failed" if failing else "done"
    assert _jobs(db_session_manager)["posts/x.jpg"].status == expected


class FakeClock:
    def __init__(self, step: float = 0.0) -> None:
        self.t, self.step = 1000.0, step

    def __call__(self) -> float:
        self.t += self.step
        return self.t


def test_a_pass_handles_at_most_max_jobs(db_session_manager) -> None:
    _enqueue(db_session_manager, [f"posts/{i:03}.jpg" for i in range(30)])
    r2 = FakeR2()
    processor = MediaDeletionProcessor(db_session_manager, r2)
    assert processor.process(datetime.now(UTC), max_jobs=10) == 10
    jobs = list(_jobs(db_session_manager).values())
    assert sum(j.status == "done" for j in jobs) == 10
    assert all(j.status == "pending" and j.attempts == 0 for j in jobs if j.status != "done")
    assert deletion_jobs.MAX_JOBS_PER_PASS == 100


def test_a_pass_stops_at_the_time_budget_and_releases_the_rest(db_session_manager) -> None:
    _enqueue(db_session_manager, [f"posts/{i}.jpg" for i in range(10)])
    r2 = FakeR2()
    # Every clock read advances 4 s: checks at 4, 8, 12 s pass, the one at 16 s stops (budget 15).
    processor = MediaDeletionProcessor(db_session_manager, r2, monotonic=FakeClock(step=4.0))
    assert processor.process(datetime.now(UTC), time_budget=15.0) == 3
    pending = [j for j in _jobs(db_session_manager).values() if j.status == "pending"]
    assert len(pending) == 7 and all(j.attempts == 0 and j.lease_until is None for j in pending)
    assert deletion_jobs.PASS_TIME_BUDGET_SECONDS == 15.0


def test_worker_r2_client_uses_short_timeouts_and_one_try() -> None:
    from app.core.config import Settings
    from app.infrastructure.storage.r2 import R2ObjectStorage, build_object_storage

    settings = Settings(r2_account_id="acc", r2_access_key_id="key", r2_secret_access_key="secret")
    storage = build_object_storage(settings, client_config=deletion_jobs.R2_CLIENT_CONFIG)
    assert isinstance(storage, R2ObjectStorage)
    config = storage._client.meta.config
    assert (config.connect_timeout, config.read_timeout) == (3, 5)
    # One try in total, no botocore retry: the job's own backoff replaces it.
    assert config.retries["total_max_attempts"] == 1
    api = build_object_storage(settings)._client.meta.config  # the API keeps its own
    assert (api.connect_timeout, api.read_timeout) == (10, 30)


def _give_up(db_session_manager, keys, processor) -> None:
    _enqueue(db_session_manager, keys)
    for _ in range(MAX_ATTEMPTS):
        processor.process(_later(hours=24 * 7))


def test_failures_are_summarised_to_telegram_at_most_hourly(db_session_manager) -> None:
    clock = FakeClock()
    sent: list[str] = []
    r2 = FakeR2(failing={"posts/a.jpg", "posts/b.jpg", "posts/c.jpg"})
    processor = MediaDeletionProcessor(
        db_session_manager, r2, alert=lambda text: sent.append(text) or True, monotonic=clock
    )
    _give_up(db_session_manager, ["posts/a.jpg", "posts/b.jpg"], processor)
    assert len(sent) == 1
    assert "gave up on 2 R2 object(s)" in sent[0] and "TimeoutError x2" in sent[0]
    assert "posts/" not in sent[0]  # no keys in the chat

    _give_up(db_session_manager, ["posts/c.jpg"], processor)
    assert len(sent) == 1  # within the hour: held back
    clock.t += deletion_jobs.ALERT_MIN_INTERVAL_SECONDS
    processor.process(datetime.now(UTC))
    assert len(sent) == 2 and "gave up on 1 R2 object(s)" in sent[1]


def test_an_undelivered_summary_is_retried(db_session_manager) -> None:
    attempts: list[str] = []
    delivered = [False]
    processor = MediaDeletionProcessor(
        db_session_manager,
        FakeR2(failing={"posts/a.jpg"}),
        alert=lambda text: attempts.append(text) or delivered[0],
        monotonic=FakeClock(),
    )
    _give_up(db_session_manager, ["posts/a.jpg"], processor)
    assert len(attempts) == 1
    delivered[0] = True
    processor.process(datetime.now(UTC))
    processor.process(datetime.now(UTC))
    assert len(attempts) == 2  # sent once more, then cleared
