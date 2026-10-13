from __future__ import annotations

from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import httpx
import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.core.dependencies import get_current_active_user, get_feedback_service
from app.features.auth.domain.models import AuthUser
from app.features.feedback.application.schemas import FeedbackCreate
from app.features.feedback.application.service import FeedbackService
from app.features.feedback.domain.models import (
    FeedbackCategory,
    FeedbackNotification,
    FeedbackPlatform,
    FeedbackRecord,
)
from app.features.feedback.infrastructure.repository import SqlAlchemyFeedbackRepository
from app.features.feedback.infrastructure.telegram import (
    TELEGRAM_MESSAGE_LIMIT,
    TelegramFeedbackNotifier,
    format_feedback_message,
)
from app.main import create_app

VALID_MESSAGE = "The map freezes when switching between tabs."


def make_user(name: str | None = "Sardor") -> AuthUser:
    return AuthUser(id=uuid4(), email="user@example.com", password_hash=None, name=name)


class FakeSessionManager:
    @contextmanager
    def session_scope(self):
        yield object()


class FakeRepository:
    """In-memory stand-in shared between service calls via `store`."""

    def __init__(self, store: list[FeedbackRecord]) -> None:
        self.store = store

    def lock_user(self, user_id: UUID) -> None:
        return None

    def count_since(self, *, user_id: UUID, since: datetime) -> int:
        return sum(1 for r in self.store if r.user_id == user_id and r.created_at > since)

    def oldest_since(self, *, user_id: UUID, since: datetime) -> datetime | None:
        times = [r.created_at for r in self.store if r.user_id == user_id and r.created_at > since]
        return min(times) if times else None

    def create(self, *, user_id, category, message, platform, app_version) -> FeedbackRecord:
        record = FeedbackRecord(
            id=uuid4(),
            user_id=user_id,
            category=category,
            message=message,
            platform=platform,
            app_version=app_version,
            created_at=datetime.now(UTC),
        )
        self.store.append(record)
        return record


class RecordingNotifier:
    def __init__(self, *, fail: bool = False) -> None:
        self.sent: list[FeedbackNotification] = []
        self.fail = fail

    def notify(self, notification: FeedbackNotification) -> bool:
        if self.fail:
            raise RuntimeError("telegram down")
        self.sent.append(notification)
        return True


def make_service(store=None, notifier=None, max_per_hour: int = 3) -> FeedbackService:
    shared = store if store is not None else []
    return FeedbackService(
        db_session_manager=FakeSessionManager(),
        repository_factory=lambda _session: FakeRepository(shared),
        notifier=notifier or RecordingNotifier(),
        max_per_hour=max_per_hour,
    )


def payload(**overrides) -> FeedbackCreate:
    data = {
        "category": "bug",
        "message": VALID_MESSAGE,
        "platform": "web",
        "app_version": "0.1.0+8",
    }
    data.update(overrides)
    return FeedbackCreate(**data)


# --- validation -------------------------------------------------------------


def test_payload_trims_and_accepts_valid_message() -> None:
    assert payload(message=f"  {VALID_MESSAGE}  ").message == VALID_MESSAGE


@pytest.mark.parametrize("message", ["", "   ", "too short", "x" * 2001, " " * 30 + "abc"])
def test_payload_rejects_bad_message_length(message: str) -> None:
    with pytest.raises(ValidationError):
        payload(message=message)


def test_payload_accepts_boundary_lengths() -> None:
    assert len(payload(message="x" * 10).message) == 10
    assert len(payload(message="x" * 2000).message) == 2000


def test_payload_rejects_unknown_category_platform_and_extra_fields() -> None:
    with pytest.raises(ValidationError):
        payload(category="complaint")
    with pytest.raises(ValidationError):
        payload(platform="ios")
    with pytest.raises(ValidationError):
        FeedbackCreate(category="bug", message=VALID_MESSAGE, user_id=str(uuid4()))


# --- service ----------------------------------------------------------------


def test_submit_persists_feedback_and_builds_notification() -> None:
    store: list[FeedbackRecord] = []
    user = make_user()
    response, notification = make_service(store).submit(user, payload())

    assert len(store) == 1
    saved = store[0]
    assert saved.user_id == user.id
    assert saved.category is FeedbackCategory.BUG
    assert saved.message == VALID_MESSAGE
    assert saved.platform is FeedbackPlatform.WEB
    assert saved.app_version == "0.1.0+8"
    assert response.id == saved.id
    assert notification.user_label == "Sardor"


def test_notification_falls_back_to_user_id_without_name() -> None:
    user = make_user(name=None)
    _, notification = make_service().submit(user, payload())
    assert notification.user_label == str(user.id)


def test_fourth_submission_in_an_hour_is_rate_limited() -> None:
    store: list[FeedbackRecord] = []
    service = make_service(store)
    user = make_user()
    for _ in range(3):
        service.submit(user, payload())

    with pytest.raises(HTTPException) as caught:
        service.submit(user, payload())

    assert caught.value.status_code == 429
    assert caught.value.detail["error"]["code"] == "FEEDBACK_RATE_LIMITED"
    assert int(caught.value.headers["Retry-After"]) > 0
    assert len(store) == 3


def test_rate_limit_is_per_user_and_expires() -> None:
    store: list[FeedbackRecord] = []
    service = make_service(store)
    user = make_user()
    for _ in range(3):
        service.submit(user, payload())
    service.submit(make_user("Other"), payload())  # another user is unaffected

    for record in store:
        record.created_at = datetime.now(UTC) - timedelta(hours=1, minutes=1)
    service.submit(user, payload())  # old submissions fell out of the window
    assert len(store) == 5


def test_telegram_failure_after_commit_does_not_lose_feedback() -> None:
    store: list[FeedbackRecord] = []
    service = make_service(store, notifier=RecordingNotifier(fail=True))
    _, notification = service.submit(make_user(), payload())

    assert len(store) == 1  # stored before any notification attempt
    with pytest.raises(RuntimeError):
        service.notify(notification)  # the real notifier swallows this; see below
    assert len(store) == 1


# --- telegram ---------------------------------------------------------------


def make_notification(
    message: str = VALID_MESSAGE, user_label: str = "Sardor"
) -> FeedbackNotification:
    return FeedbackNotification(
        feedback_id=UUID("11111111-1111-1111-1111-111111111111"),
        category=FeedbackCategory.BUG,
        message=message,
        user_label=user_label,
        platform=FeedbackPlatform.ANDROID,
        app_version="0.1.0+8",
        created_at=datetime(2026, 10, 13, 9, 30, tzinfo=UTC),
    )


def test_message_format_contains_expected_fields() -> None:
    text = format_feedback_message(make_notification())
    assert "<b>New Mushukistan Feedback</b>" in text
    assert "Category: Bug Report" in text
    assert "User: Sardor" in text
    assert "Platform: Android 0.1.0+8" in text
    assert "Date: 2026-10-13 09:30 UTC" in text
    assert VALID_MESSAGE in text
    assert "11111111-1111-1111-1111-111111111111" in text


def test_message_format_escapes_user_html() -> None:
    text = format_feedback_message(
        make_notification(
            message='<a href="https://evil.example">click</a> & <b>bold</b>',
            user_label="<script>alert(1)</script>",
        )
    )
    assert "<script>" not in text
    assert "&lt;script&gt;" in text
    assert '<a href="https://evil.example">' not in text
    assert "&lt;a href=" in text
    assert "&amp;" in text
    assert "<b>bold</b>" not in text


def test_message_format_respects_telegram_limit_even_when_escaping_expands() -> None:
    text = format_feedback_message(make_notification(message="<" * 2000 + "&" * 100))
    assert len(text) <= TELEGRAM_MESSAGE_LIMIT


def _client(handler) -> httpx.Client:
    return httpx.Client(transport=httpx.MockTransport(handler))


def test_notifier_posts_html_message_to_bot_api() -> None:
    seen: dict[str, object] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        seen["url"] = str(request.url)
        seen["json"] = __import__("json").loads(request.content)
        return httpx.Response(200, json={"ok": True})

    notifier = TelegramFeedbackNotifier(bot_token="TOKEN", chat_id="42", client=_client(handler))
    assert notifier.notify(make_notification()) is True
    assert seen["url"] == "https://api.telegram.org/botTOKEN/sendMessage"
    assert seen["json"]["chat_id"] == "42"
    assert seen["json"]["parse_mode"] == "HTML"


def test_notifier_is_disabled_without_credentials() -> None:
    calls: list[int] = []
    notifier = TelegramFeedbackNotifier(
        bot_token="",
        chat_id="42",
        client=_client(lambda r: calls.append(1) or httpx.Response(200)),
    )
    assert notifier.enabled is False
    assert notifier.notify(make_notification()) is False
    assert calls == []


@pytest.mark.parametrize(
    "handler",
    [
        lambda r: httpx.Response(401, json={"ok": False}),
        lambda r: httpx.Response(500),
        lambda r: (_ for _ in ()).throw(httpx.ConnectTimeout("timeout")),
    ],
)
def test_notifier_swallows_failures_and_never_logs_token(handler, capsys) -> None:
    notifier = TelegramFeedbackNotifier(
        bot_token="SECRET-TOKEN", chat_id="42", client=_client(handler)
    )
    assert notifier.notify(make_notification()) is False
    captured = capsys.readouterr()
    assert "SECRET-TOKEN" not in captured.out + captured.err


# --- HTTP layer -------------------------------------------------------------


@pytest.fixture()
def api():
    app = create_app()
    store: list[FeedbackRecord] = []
    notifier = RecordingNotifier()
    user = make_user()
    app.dependency_overrides[get_current_active_user] = lambda: user
    app.dependency_overrides[get_feedback_service] = lambda: make_service(store, notifier)
    # No context manager: skips lifespan (PostHog bootstrap) but still runs
    # background tasks, which is all these tests need.
    yield TestClient(app), store, notifier, user
    app.dependency_overrides.clear()


def test_authenticated_submission_returns_201_and_notifies(api) -> None:
    client, store, notifier, _ = api
    response = client.post(
        "/api/v1/feedback",
        json={"category": "suggestion", "message": VALID_MESSAGE, "platform": "web"},
    )
    assert response.status_code == 201
    data = response.json()["data"]
    assert data["category"] == "suggestion"
    assert "message" not in data
    assert len(store) == 1
    assert len(notifier.sent) == 1  # background task ran after the response


def test_http_rejects_invalid_payloads(api) -> None:
    client, store, _, _ = api
    for body in (
        {"category": "nope", "message": VALID_MESSAGE},
        {"category": "bug", "message": ""},
        {"category": "bug", "message": "x" * 2001},
        {"category": "bug"},
    ):
        assert client.post("/api/v1/feedback", json=body).status_code == 422
    assert store == []


def test_http_rate_limit_returns_429_with_retry_after(api) -> None:
    client, _, _, _ = api
    body = {"category": "bug", "message": VALID_MESSAGE}
    assert [client.post("/api/v1/feedback", json=body).status_code for _ in range(3)] == [201] * 3
    blocked = client.post("/api/v1/feedback", json=body)
    assert blocked.status_code == 429
    assert blocked.json()["error"]["code"] == "FEEDBACK_RATE_LIMITED"
    assert blocked.headers["Retry-After"]


def test_http_succeeds_even_if_notifier_raises() -> None:
    app = create_app()
    store: list[FeedbackRecord] = []
    app.dependency_overrides[get_current_active_user] = make_user
    app.dependency_overrides[get_feedback_service] = lambda: make_service(
        store, RecordingNotifier(fail=True)
    )
    response = TestClient(app, raise_server_exceptions=False).post(
        "/api/v1/feedback", json={"category": "bug", "message": VALID_MESSAGE}
    )
    assert response.status_code == 201
    assert len(store) == 1


def test_unauthenticated_submission_is_rejected() -> None:
    response = TestClient(create_app()).post(
        "/api/v1/feedback", json={"category": "bug", "message": VALID_MESSAGE}
    )
    assert response.status_code == 401


# --- database ---------------------------------------------------------------


def test_repository_persists_and_counts(integration_session) -> None:
    from app.infrastructure.db.models import schema

    user = schema.User(id=uuid4(), email=f"fb-{uuid4().hex[:8]}@example.com")
    integration_session.add(user)
    integration_session.flush()

    repository = SqlAlchemyFeedbackRepository(integration_session)
    repository.lock_user(user.id)
    record = repository.create(
        user_id=user.id,
        category=FeedbackCategory.SUGGESTION,
        message=VALID_MESSAGE,
        platform=FeedbackPlatform.ANDROID,
        app_version="0.1.0+8",
    )
    stored = integration_session.get(schema.Feedback, record.id)
    assert stored is not None
    assert (stored.category, stored.message, stored.platform) == (
        "suggestion",
        VALID_MESSAGE,
        "android",
    )
    since = datetime.now(UTC) - timedelta(hours=1)
    assert repository.count_since(user_id=user.id, since=since) == 1
    assert repository.oldest_since(user_id=user.id, since=since) is not None
