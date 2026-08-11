from __future__ import annotations

from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from geoalchemy2 import WKTElement
from sqlalchemy import delete, select

from app.core.auth import AuthenticatedPrincipal, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.core.dependencies import get_users_service
from app.core.security import api_error
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.features.users.application.service import UsersService
from app.features.users.infrastructure.repositories import SqlAlchemyUserProfileRepository
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.main import app


def _test_settings(monkeypatch: pytest.MonkeyPatch) -> Settings:
    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key")
    monkeypatch.setenv("JWT_ISSUER", "mushukistan-api")
    monkeypatch.setenv("JWT_AUDIENCE", "mushukistan-mobile")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "google-client-id")
    monkeypatch.setenv(
        "DATABASE_URL", "postgresql+psycopg://mushukistan:change_me@localhost:5432/mushukistan"
    )
    return Settings()


@pytest.fixture()
def users_runtime(monkeypatch: pytest.MonkeyPatch, db_session_manager: DatabaseSessionManager):
    settings = _test_settings(monkeypatch)
    token_service = JoseAccessTokenService(settings)
    users_service = UsersService(
        db_session_manager=db_session_manager,
        repository_factory=SqlAlchemyUserProfileRepository,
    )

    app.state.container = AppContainer(settings=settings, db_session_manager=db_session_manager)
    app.dependency_overrides[get_users_service] = lambda: users_service

    context = SimpleNamespace(
        settings=settings,
        token_service=token_service,
        db_session_manager=db_session_manager,
        users_service=users_service,
    )

    try:
        yield context
    finally:
        app.dependency_overrides.clear()


@pytest.fixture()
def client(users_runtime):
    with TestClient(app) as test_client:
        yield test_client


def _create_user_with_token(
    db_session_manager: DatabaseSessionManager,
    token_service: JoseAccessTokenService,
    *,
    email: str,
    name: str = "Profile User",
    bio: str = "Cat lover",
    avatar_url: str = "https://example.com/avatar.jpg",
    is_active: bool = True,
):
    with db_session_manager.session_scope() as session:
        user = schema.User(
            email=email,
            name=name,
            bio=bio,
            avatar_url=avatar_url,
            is_active=is_active,
        )
        session.add(user)
        session.flush()
        token = token_service.issue_access_token(
            AuthenticatedPrincipal(user_id=user.id, role=Role.USER)
        )
        return user, token


def _create_profile_activity(db_session_manager: DatabaseSessionManager, user_id: UUID) -> None:
    with db_session_manager.session_scope() as session:
        other_user = schema.User(email=f"other-{uuid4().hex}@example.com", name="Other")
        cat = schema.Cat(status=schema.CatStatus.UNKNOWN, name="Profile Cat")
        session.add_all([other_user, cat])
        session.flush()

        first_post = schema.Post(
            cat_id=cat.id,
            user_id=user_id,
            photo_url="https://example.com/first.jpg",
            location=WKTElement("POINT(69.2500 41.3000)", srid=4326),
        )
        second_post = schema.Post(
            cat_id=cat.id,
            user_id=user_id,
            photo_url="https://example.com/second.jpg",
            location=WKTElement("POINT(69.2501 41.3001)", srid=4326),
        )
        other_post = schema.Post(
            cat_id=cat.id,
            user_id=other_user.id,
            photo_url="https://example.com/other.jpg",
            location=WKTElement("POINT(69.2502 41.3002)", srid=4326),
        )
        session.add_all([first_post, second_post, other_post])
        session.flush()

        session.add_all(
            [
                schema.Like(post_id=first_post.id, user_id=other_user.id),
                schema.Like(post_id=second_post.id, user_id=other_user.id),
                schema.Comment(post_id=other_post.id, user_id=user_id, content="Hello"),
            ]
        )


def test_authenticated_profile_retrieval(client: TestClient, users_runtime) -> None:
    user, token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="self-profile@example.com",
    )
    _create_profile_activity(users_runtime.db_session_manager, user.id)

    response = client.get("/api/v1/users/me", headers={"Authorization": f"Bearer {token}"})
    assert response.status_code == 200
    payload = response.json()["data"]
    assert payload["email"] == "self-profile@example.com"
    assert payload["observation_count"] == 2
    assert payload["total_likes_received"] == 2
    assert payload["comment_count"] == 1


def test_unauthorized_access_rejected(client: TestClient) -> None:
    response = client.get("/api/v1/users/me")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_valid_profile_update(client: TestClient, users_runtime) -> None:
    user, token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="update-profile@example.com",
        name="Original",
        bio="Original bio",
    )

    response = client.patch(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "name": "Updated Name",
            "bio": "Updated bio",
            "phone_number": "+998 90 123 45 67",
            "avatar_url": "https://example.com/new-avatar.jpg",
        },
    )
    assert response.status_code == 200
    payload = response.json()["data"]
    assert payload["email"] == "update-profile@example.com"
    assert payload["name"] == "Updated Name"
    assert payload["bio"] == "Updated bio"
    assert payload["phone_number"] == "+998 90 123 45 67"
    assert payload["avatar_url"] == "https://example.com/new-avatar.jpg"

    with users_runtime.db_session_manager.session_scope() as session:
        updated = session.scalar(select(schema.User).where(schema.User.id == user.id))
        assert updated is not None
        assert updated.email == "update-profile@example.com"
        assert updated.name == "Updated Name"
        assert updated.bio == "Updated bio"
        assert updated.phone_number == "+998 90 123 45 67"
        assert updated.avatar_url == "https://example.com/new-avatar.jpg"
        assert updated.is_active is True


def test_delete_me_deactivates_account_and_rejects_token(
    client: TestClient,
    users_runtime,
) -> None:
    user, token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="delete-me@example.com",
    )

    response = client.delete(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 204
    assert not response.content

    with users_runtime.db_session_manager.session_scope() as session:
        deleted = session.scalar(select(schema.User).where(schema.User.id == user.id))
        assert deleted is not None
        assert deleted.is_active is False

    me_response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert me_response.status_code == 403
    assert me_response.json()["error"]["code"] == "ACCOUNT_DISABLED"

    public_response = client.get(f"/api/v1/users/{user.id}")
    assert public_response.status_code == 404
    assert public_response.json()["error"]["code"] == "USER_NOT_FOUND"


def test_rejection_of_immutable_or_forbidden_fields(client: TestClient, users_runtime) -> None:
    _, token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="immutable@example.com",
    )

    response = client.patch(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={"email": "new@example.com"},
    )
    assert response.status_code == 422


def test_validation_failures(client: TestClient, users_runtime) -> None:
    _, token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="validation@example.com",
    )

    too_long_name = "a" * 101
    response = client.patch(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={"name": too_long_name},
    )
    assert response.status_code == 422

    invalid_url = client.patch(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={"avatar_url": "not-a-url"},
    )
    assert invalid_url.status_code == 422

    invalid_phone = client.patch(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={"phone_number": "bad-phone-ext"},
    )
    assert invalid_phone.status_code == 422

    empty_update = client.patch(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={},
    )
    assert empty_update.status_code == 422


def test_public_profile_visibility_and_private_field_exclusion(
    client: TestClient, users_runtime
) -> None:
    user, _ = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="public-profile@example.com",
    )
    _create_profile_activity(users_runtime.db_session_manager, user.id)

    response = client.get(f"/api/v1/users/{user.id}")
    assert response.status_code == 200
    payload = response.json()["data"]
    assert payload["id"] == str(user.id)
    assert payload["name"] == "Profile User"
    assert "email" not in payload
    assert "phone_number" not in payload
    assert "bio" not in payload
    assert "is_active" not in payload
    assert "is_moderator" not in payload
    assert payload["observation_count"] == 2


def test_missing_inactive_and_deleted_users_return_not_found(
    client: TestClient, users_runtime
) -> None:
    missing_response = client.get(f"/api/v1/users/{uuid4()}")
    assert missing_response.status_code == 404
    assert missing_response.json()["error"]["code"] == "USER_NOT_FOUND"

    inactive_user, _ = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="inactive-public@example.com",
        is_active=False,
    )

    inactive_response = client.get(f"/api/v1/users/{inactive_user.id}")
    assert inactive_response.status_code == 404

    active_user, active_token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="deleted-auth@example.com",
    )

    with users_runtime.db_session_manager.session_scope() as session:
        session.execute(delete(schema.User).where(schema.User.id == active_user.id))

    deleted_public_response = client.get(f"/api/v1/users/{active_user.id}")
    assert deleted_public_response.status_code == 404

    deleted_me_response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {active_token}"},
    )
    assert deleted_me_response.status_code == 401
    assert deleted_me_response.json()["error"]["code"] == "UNAUTHORIZED"

    _, inactive_me_token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="inactive-auth@example.com",
        is_active=False,
    )
    inactive_me_response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {inactive_me_token}"},
    )
    assert inactive_me_response.status_code == 403
    assert inactive_me_response.json()["error"]["code"] == "ACCOUNT_DISABLED"


def test_transaction_rollback_on_failed_updates(client: TestClient, users_runtime) -> None:
    user, token = _create_user_with_token(
        users_runtime.db_session_manager,
        users_runtime.token_service,
        email="rollback-update@example.com",
        name="Before",
    )

    class FailingUserProfileRepository(SqlAlchemyUserProfileRepository):
        def save(self, user):  # type: ignore[override]
            super().save(user)
            raise api_error(500, "INTERNAL_SERVER_ERROR", "force rollback")

    failing_service = UsersService(
        db_session_manager=users_runtime.db_session_manager,
        repository_factory=FailingUserProfileRepository,
    )
    app.dependency_overrides[get_users_service] = lambda: failing_service

    response = client.patch(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "After"},
    )
    assert response.status_code == 500

    with users_runtime.db_session_manager.session_scope() as session:
        persisted = session.scalar(select(schema.User).where(schema.User.id == user.id))
        assert persisted is not None
        assert persisted.name == "Before"
