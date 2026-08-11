from __future__ import annotations

from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from geoalchemy2.elements import WKTElement

from app.core.auth import AuthenticatedPrincipal, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.features.cats.domain.models import CatStatus
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.main import app


def _test_settings(monkeypatch: pytest.MonkeyPatch) -> Settings:
    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key")
    monkeypatch.setenv("JWT_ISSUER", "mushukistan-api")
    monkeypatch.setenv("JWT_AUDIENCE", "mushukistan-mobile")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "google-client-id")
    monkeypatch.setenv(
        "DATABASE_URL",
        "postgresql+psycopg://mushukistan:change_me@localhost:5432/mushukistan_validation",
    )
    return Settings()


@pytest.fixture()
def reports_runtime(monkeypatch: pytest.MonkeyPatch, db_session_manager: DatabaseSessionManager):
    settings = _test_settings(monkeypatch)
    token_service = JoseAccessTokenService(settings)

    app.state.container = AppContainer(settings=settings, db_session_manager=db_session_manager)
    app.dependency_overrides.clear()

    context = SimpleNamespace(
        settings=settings,
        token_service=token_service,
        db_session_manager=db_session_manager,
    )

    try:
        yield context
    finally:
        app.dependency_overrides.clear()


@pytest.fixture()
def client(reports_runtime):
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


def _create_user(
    db_session_manager: DatabaseSessionManager,
    token_service: JoseAccessTokenService,
    *,
    user_id: UUID,
    email: str,
    name: str,
    is_moderator: bool = False,
    is_active: bool = True,
):
    with db_session_manager.session_scope() as session:
        user = schema.User(
            id=user_id,
            email=email,
            name=name,
            password_hash=PasslibPasswordHasher().hash_password("StrongPass123"),
            is_active=is_active,
            is_moderator=is_moderator,
        )
        session.add(user)
        session.flush()
        token = token_service.issue_access_token(
            AuthenticatedPrincipal(
                user_id=user.id,
                role=Role.MODERATOR if is_moderator else Role.USER,
                email=user.email,
            )
        )
        return user, token


def _create_cat(
    db_session_manager: DatabaseSessionManager,
    *,
    cat_id: UUID,
    creator_id: UUID | None,
    name: str = "Mittens",
    status: CatStatus = CatStatus.UNKNOWN,
    is_active: bool = True,
    deleted_at: datetime | None = None,
    merged_into: UUID | None = None,
):
    with db_session_manager.session_scope() as session:
        cat = schema.Cat(
            id=cat_id,
            name=name,
            status=status,
            created_by=creator_id,
            is_active=is_active,
            deleted_at=deleted_at,
            merged_into=merged_into,
            canonical_location=WKTElement("POINT(69.25 41.30)", srid=4326),
        )
        session.add(cat)
        session.flush()
        return cat


def _create_post(
    db_session_manager: DatabaseSessionManager,
    *,
    post_id: UUID,
    cat_id: UUID,
    user_id: UUID,
    is_public: bool = True,
    like_count: int = 0,
    comment_count: int = 0,
    status: CatStatus | None = None,
    deleted_at: datetime | None = None,
):
    with db_session_manager.session_scope() as session:
        post = schema.Post(
            id=post_id,
            cat_id=cat_id,
            user_id=user_id,
            photo_url=f"https://example.invalid/{post_id}.jpg",
            thumb_url=None,
            description="Observation",
            location=WKTElement("POINT(69.2501 41.3001)", srid=4326),
            status=status,
            is_public=is_public,
            like_count=like_count,
            comment_count=comment_count,
            deleted_at=deleted_at,
        )
        session.add(post)
        session.flush()
        return post


def _create_comment(
    db_session_manager: DatabaseSessionManager,
    *,
    comment_id: UUID,
    post_id: UUID,
    user_id: UUID,
    content: str = "Nice cat",
    deleted_at: datetime | None = None,
):
    with db_session_manager.session_scope() as session:
        comment = schema.Comment(
            id=comment_id,
            post_id=post_id,
            user_id=user_id,
            content=content,
            deleted_at=deleted_at,
        )
        session.add(comment)
        session.flush()
        return comment


def test_create_report_and_reject_spoofed_reporter(
    client: TestClient,
    reports_runtime,
):
    reporter_id = UUID("11111111-1111-4111-8111-111111111111")
    reporter, token = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=reporter_id,
        email="reporter@example.com",
        name="Reporter",
    )
    cat = _create_cat(
        reports_runtime.db_session_manager,
        cat_id=UUID("22222222-2222-4222-8222-222222222222"),
        creator_id=reporter.id,
    )
    post = _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("33333333-3333-4333-8333-333333333333"),
        cat_id=cat.id,
        user_id=reporter.id,
    )

    response = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "target_type": "post",
            "target_id": str(post.id),
            "reason": "Contains graphic content",
            "metadata": {"source": "camera"},
        },
    )
    assert response.status_code == 201, response.text
    payload = response.json()["data"]
    assert payload["reporter"]["id"] == str(reporter.id)
    assert payload["target"]["id"] == str(post.id)
    assert payload["target"]["target_type"] == "post"

    spoof = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "target_type": "post",
            "target_id": str(post.id),
            "reason": "Contains graphic content",
            "reporter_id": str(UUID("99999999-9999-4999-8999-999999999999")),
        },
    )
    assert spoof.status_code == 422


def test_report_rejects_anonymous_invalid_target_deleted_and_duplicate(
    client: TestClient,
    reports_runtime,
):
    reporter, token = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=UUID("44444444-4444-4444-8444-444444444444"),
        email="reporter2@example.com",
        name="Reporter 2",
    )
    cat = _create_cat(
        reports_runtime.db_session_manager,
        cat_id=UUID("55555555-5555-4555-8555-555555555555"),
        creator_id=reporter.id,
    )
    post = _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("66666666-6666-4666-8666-666666666666"),
        cat_id=cat.id,
        user_id=reporter.id,
    )

    anonymous = client.post(
        "/api/v1/reports",
        json={"target_type": "post", "target_id": str(post.id), "reason": "spam"},
    )
    assert anonymous.status_code == 401

    invalid = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={"target_type": "post", "target_id": str(UUID(int=1)), "reason": "spam"},
    )
    assert invalid.status_code == 404

    _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("77777777-7777-4777-8777-777777777777"),
        cat_id=cat.id,
        user_id=reporter.id,
        deleted_at=datetime.now(UTC),
    )
    deleted = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "target_type": "post",
            "target_id": str(UUID("77777777-7777-4777-8777-777777777777")),
            "reason": "deleted target",
        },
    )
    assert deleted.status_code == 404

    duplicate_first = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={"target_type": "post", "target_id": str(post.id), "reason": "spam"},
    )
    duplicate_second = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={"target_type": "post", "target_id": str(post.id), "reason": "spam"},
    )
    assert duplicate_first.status_code == 201
    assert duplicate_second.status_code == 201
    assert duplicate_first.json()["data"]["id"] == duplicate_second.json()["data"]["id"]


def test_report_validation_errors(client: TestClient, reports_runtime):
    reporter, token = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=UUID("88888888-8888-4888-8888-888888888888"),
        email="reporter3@example.com",
        name="Reporter 3",
    )
    cat = _create_cat(
        reports_runtime.db_session_manager,
        cat_id=UUID("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
        creator_id=reporter.id,
    )
    post = _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"),
        cat_id=cat.id,
        user_id=reporter.id,
    )

    blank_reason = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {token}"},
        json={"target_type": "post", "target_id": str(post.id), "reason": "   "},
    )
    assert blank_reason.status_code == 422


def test_moderation_report_listing_resolution_and_delete_post(
    client: TestClient,
    reports_runtime,
):
    _moderator, mod_token = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=UUID("cccccccc-cccc-4ccc-8ccc-cccccccccccc"),
        email="mod@example.com",
        name="Mod",
        is_moderator=True,
    )
    reporter, reporter_token = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=UUID("dddddddd-dddd-4ddd-8ddd-dddddddddddd"),
        email="reporter4@example.com",
        name="Reporter 4",
    )
    cat = _create_cat(
        reports_runtime.db_session_manager,
        cat_id=UUID("eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee"),
        creator_id=reporter.id,
    )
    post = _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("ffffffff-ffff-4fff-8fff-ffffffffffff"),
        cat_id=cat.id,
        user_id=reporter.id,
    )
    comment = _create_comment(
        reports_runtime.db_session_manager,
        comment_id=UUID("12121212-1212-4212-8212-121212121212"),
        post_id=post.id,
        user_id=reporter.id,
    )

    post_report = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {reporter_token}"},
        json={"target_type": "post", "target_id": str(post.id), "reason": "spam"},
    )
    comment_report = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {reporter_token}"},
        json={"target_type": "comment", "target_id": str(comment.id), "reason": "spam"},
    )
    user_report = client.post(
        "/api/v1/reports",
        headers={"Authorization": f"Bearer {reporter_token}"},
        json={"target_type": "user", "target_id": str(reporter.id), "reason": "spam"},
    )
    assert post_report.status_code == 201
    assert comment_report.status_code == 201
    assert user_report.status_code == 201

    forbidden = client.get(
        "/api/v1/moderation/reports",
        headers={"Authorization": f"Bearer {reporter_token}"},
    )
    assert forbidden.status_code == 403

    anonymous = client.get("/api/v1/moderation/reports")
    assert anonymous.status_code == 401

    listing = client.get(
        "/api/v1/moderation/reports",
        headers={"Authorization": f"Bearer {mod_token}"},
        params={"status": "open", "limit": 1},
    )
    assert listing.status_code == 200, listing.text
    page1 = listing.json()["data"]
    assert page1["limit"] == 1
    assert len(page1["items"]) == 1
    assert page1["next_cursor"] is not None
    assert page1["items"][0]["reporter"]["id"] == str(reporter.id)

    second_page = client.get(
        "/api/v1/moderation/reports",
        headers={"Authorization": f"Bearer {mod_token}"},
        params={"status": "open", "limit": 1, "cursor": page1["next_cursor"]},
    )
    assert second_page.status_code == 200
    assert len(second_page.json()["data"]["items"]) == 2 - 1

    resolved = client.patch(
        f"/api/v1/moderation/reports/{post_report.json()['data']['id']}",
        headers={"Authorization": f"Bearer {mod_token}"},
        json={"status": "resolved", "action": "soft_delete_post", "note": "Removed spam"},
    )
    assert resolved.status_code == 200, resolved.text
    assert resolved.json()["data"]["status"] == "resolved"

    with reports_runtime.db_session_manager.session_scope() as session:
        stored_post = session.get(schema.Post, post.id)
        stored_comment = session.get(schema.Comment, comment.id)
        stored_user = session.get(schema.User, reporter.id)
        assert stored_post is not None and stored_post.deleted_at is not None
        assert stored_comment is not None and stored_comment.deleted_at is None
        assert stored_user is not None and stored_user.is_active is True

    repeat_resolution = client.patch(
        f"/api/v1/moderation/reports/{post_report.json()['data']['id']}",
        headers={"Authorization": f"Bearer {mod_token}"},
        json={"status": "resolved", "action": "soft_delete_post", "note": "Again"},
    )
    assert repeat_resolution.status_code == 409

    user_resolution = client.patch(
        f"/api/v1/moderation/reports/{user_report.json()['data']['id']}",
        headers={"Authorization": f"Bearer {mod_token}"},
        json={"status": "resolved", "action": "suspend_user", "note": "Abuse"},
    )
    assert user_resolution.status_code == 200
    with reports_runtime.db_session_manager.session_scope() as session:
        stored_user = session.get(schema.User, reporter.id)
        assert stored_user is not None and stored_user.is_active is False

    delete_post = client.delete(
        f"/api/v1/moderation/posts/{post.id}",
        headers={"Authorization": f"Bearer {mod_token}"},
    )
    assert delete_post.status_code == 204


def test_leaderboards_rankings_and_visibility_filters(
    client: TestClient,
    reports_runtime,
):
    user1, _ = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=UUID("11111111-1111-4111-8111-111111111111"),
        email="lb1@example.com",
        name="Alice",
    )
    user2, _ = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=UUID("22222222-2222-4222-8222-222222222222"),
        email="lb2@example.com",
        name="Bob",
    )
    user3, _ = _create_user(
        reports_runtime.db_session_manager,
        reports_runtime.token_service,
        user_id=UUID("33333333-3333-4333-8333-333333333333"),
        email="lb3@example.com",
        name="Charlie",
    )
    cat = _create_cat(
        reports_runtime.db_session_manager,
        cat_id=UUID("44444444-4444-4444-8444-444444444444"),
        creator_id=user1.id,
    )
    _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("55555555-5555-4555-8555-555555555555"),
        cat_id=cat.id,
        user_id=user1.id,
        like_count=2,
        status=CatStatus.NEEDS_HELP,
    )
    _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("66666666-6666-4666-8666-666666666666"),
        cat_id=cat.id,
        user_id=user1.id,
        like_count=1,
        status=CatStatus.NEEDS_HELP,
    )
    _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("77777777-7777-4777-8777-777777777777"),
        cat_id=cat.id,
        user_id=user2.id,
        like_count=2,
        status=CatStatus.NEEDS_HELP,
    )
    _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("aaaaaaaa-1111-4111-8111-aaaaaaaa1111"),
        cat_id=cat.id,
        user_id=user2.id,
        like_count=1,
        status=CatStatus.NEEDS_HELP,
    )
    _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("88888888-8888-4888-8888-888888888888"),
        cat_id=cat.id,
        user_id=user3.id,
        like_count=5,
        status=CatStatus.NEEDS_HELP,
        is_public=False,
    )
    _create_post(
        reports_runtime.db_session_manager,
        post_id=UUID("99999999-9999-4999-8999-999999999999"),
        cat_id=cat.id,
        user_id=user3.id,
        like_count=5,
        status=CatStatus.NEEDS_HELP,
        deleted_at=datetime.now(UTC),
    )

    most_active = client.get(
        "/api/v1/leaderboards/most_active",
        params={"period": "all", "limit": 10},
    )
    assert most_active.status_code == 200, most_active.text
    active_items = most_active.json()["data"]
    assert active_items[0]["score"] >= active_items[1]["score"]
    assert "email" not in active_items[0]["user"]

    tie_break = client.get(
        "/api/v1/leaderboards/most_active",
        params={"period": "all", "limit": 2},
    )
    tie_items = tie_break.json()["data"]
    assert tie_items[0]["score"] == tie_items[1]["score"]
    assert tie_items[0]["user"]["id"] < tie_items[1]["user"]["id"]

    popular = client.get(
        "/api/v1/leaderboards/most_popular",
        params={"period": "all", "limit": 10},
    )
    assert popular.status_code == 200
    popular_items = popular.json()["data"]
    assert popular_items[0]["score"] >= popular_items[1]["score"]

    helpers = client.get(
        "/api/v1/leaderboards/top_helpers",
        params={"period": "all", "limit": 10},
    )
    assert helpers.status_code == 200
    helper_items = helpers.json()["data"]
    assert helper_items[0]["score"] >= helper_items[1]["score"]
    assert helper_items[0]["user"]["name"] is not None
