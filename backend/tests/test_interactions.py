from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi.testclient import TestClient
from geoalchemy2.elements import WKTElement
from sqlalchemy import select

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
def interactions_runtime(
    monkeypatch: pytest.MonkeyPatch,
    db_session_manager: DatabaseSessionManager,
):
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
def client(interactions_runtime):
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


def _create_user_with_token(
    db_session_manager: DatabaseSessionManager,
    token_service: JoseAccessTokenService,
    *,
    email: str,
    name: str = "Interaction User",
    is_active: bool = True,
    is_moderator: bool = False,
):
    with db_session_manager.session_scope() as session:
        user = schema.User(
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
    creator_id: UUID | None,
    name: str = "Mittens",
    status: CatStatus = CatStatus.UNKNOWN,
    is_active: bool = True,
    deleted_at: datetime | None = None,
    merged_into: UUID | None = None,
):
    with db_session_manager.session_scope() as session:
        cat = schema.Cat(
            name=name,
            status=status,
            created_by=creator_id,
            is_active=is_active,
            deleted_at=deleted_at,
            merged_into=merged_into,
        )
        session.add(cat)
        session.flush()
        return cat


def _create_post(
    db_session_manager: DatabaseSessionManager,
    *,
    cat_id: UUID,
    user_id: UUID,
    photo_url: str = "https://example.com/post.jpg",
    thumb_url: str | None = "https://example.com/thumb.jpg",
    description: str = "Observation",
    is_public: bool = True,
    like_count: int = 0,
    comment_count: int = 0,
    created_at: datetime | None = None,
) -> UUID:
    created_at = created_at or datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        post = schema.Post(
            cat_id=cat_id,
            user_id=user_id,
            photo_url=photo_url,
            thumb_url=thumb_url,
            description=description,
            location=WKTElement("POINT(69.25 41.3)", srid=4326),
            status=CatStatus.UNKNOWN,
            is_public=is_public,
            like_count=like_count,
            comment_count=comment_count,
            created_at=created_at,
            updated_at=created_at,
        )
        session.add(post)
        session.flush()
    return post.id


def _create_locationless_post(
    db_session_manager: DatabaseSessionManager,
    *,
    cat_id: UUID,
    user_id: UUID,
    photo_url: str = "https://example.com/locationless.jpg",
) -> UUID:
    with db_session_manager.session_scope() as session:
        post = schema.Post(
            cat_id=cat_id,
            user_id=user_id,
            photo_url=photo_url,
            description="Locationless observation",
            location=None,
            status=CatStatus.UNKNOWN,
            is_public=True,
            like_count=0,
            comment_count=0,
        )
        session.add(post)
        session.flush()
        return post.id


def _create_comment(
    db_session_manager: DatabaseSessionManager,
    *,
    post_id: UUID,
    user_id: UUID,
    content: str,
    created_at: datetime | None = None,
) -> UUID:
    created_at = created_at or datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        comment = schema.Comment(
            post_id=post_id,
            user_id=user_id,
            content=content,
            created_at=created_at,
            updated_at=created_at,
        )
        session.add(comment)
        session.flush()
        return comment.id


def test_authenticated_like_and_duplicate_behavior(
    client: TestClient,
    interactions_runtime,
) -> None:
    user, token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="like@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=user.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
    )

    response = client.post(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    assert response.json()["data"] == {"liked": True, "like_count": 1}

    duplicate = client.post(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert duplicate.status_code == 409
    assert duplicate.json()["error"]["code"] == "ALREADY_LIKED"

    with interactions_runtime.db_session_manager.session_scope() as session:
        post = session.get(schema.Post, post_id)
        like_count = session.scalar(select(schema.Like).where(schema.Like.post_id == post_id))
        assert post is not None
        assert post.like_count == 1
        assert like_count is not None


def test_like_locationless_post(
    client: TestClient,
    interactions_runtime,
) -> None:
    user, token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="like-locationless@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=user.id)
    post_id = _create_locationless_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
    )

    response = client.post(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    assert response.json()["data"] == {"liked": True, "like_count": 1}


def test_unauthenticated_like_rejected(client: TestClient, interactions_runtime) -> None:
    user, _ = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="like-unauth@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=user.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
    )

    response = client.post(f"/api/v1/posts/{post_id}/likes")
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_unlike_and_idempotent_unlike_when_no_like_exists(
    client: TestClient,
    interactions_runtime,
) -> None:
    user, token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="unlike@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=user.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
    )

    like_response = client.post(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert like_response.status_code == 200

    unlike_response = client.delete(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert unlike_response.status_code == 204

    repeat_unlike = client.delete(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert repeat_unlike.status_code == 204

    with interactions_runtime.db_session_manager.session_scope() as session:
        post = session.get(schema.Post, post_id)
        likes = session.execute(select(schema.Like).where(schema.Like.post_id == post_id)).all()
        assert post is not None
        assert post.like_count == 0
        assert likes == []


@pytest.mark.parametrize("is_public", [False, True])
def test_like_visibility_and_deleted_post_behavior(
    client: TestClient,
    interactions_runtime,
    is_public: bool,
) -> None:
    author, author_token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email=f"visibility-author-{is_public}@example.com",
    )
    _other_user, other_token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email=f"visibility-other-{is_public}@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        is_public=is_public,
    )

    if is_public:
        public_like = client.post(
            f"/api/v1/posts/{post_id}/likes",
            headers={"Authorization": f"Bearer {other_token}"},
        )
        assert public_like.status_code == 200
    else:
        private_like = client.post(
            f"/api/v1/posts/{post_id}/likes",
            headers={"Authorization": f"Bearer {other_token}"},
        )
        assert private_like.status_code == 404
        assert private_like.json()["error"]["code"] == "POST_NOT_FOUND"

    delete_response = client.delete(
        f"/api/v1/posts/{post_id}",
        headers={"Authorization": f"Bearer {author_token}"},
    )
    assert delete_response.status_code == 204

    deleted_like = client.post(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {other_token}"},
    )
    assert deleted_like.status_code == 404


def test_like_counter_consistency(client: TestClient, interactions_runtime) -> None:
    user, token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="counter-like@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=user.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
    )

    for expected_count in (1, 0, 1):
        if expected_count == 1:
            response = client.post(
                f"/api/v1/posts/{post_id}/likes",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert response.status_code == 200
        else:
            response = client.delete(
                f"/api/v1/posts/{post_id}/likes",
                headers={"Authorization": f"Bearer {token}"},
            )
            assert response.status_code == 204

        with interactions_runtime.db_session_manager.session_scope() as session:
            post = session.get(schema.Post, post_id)
            assert post is not None
            assert post.like_count == expected_count

        if expected_count == 1:
            client.delete(
                f"/api/v1/posts/{post_id}/likes",
                headers={"Authorization": f"Bearer {token}"},
            )


def test_create_comment_and_validation_behaviour(
    client: TestClient,
    interactions_runtime,
) -> None:
    user, token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-create@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=user.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
    )

    response = client.post(
        f"/api/v1/posts/{post_id}/comments",
        headers={"Authorization": f"Bearer {token}"},
        json={"content": "So cute!"},
    )
    assert response.status_code == 201
    payload = response.json()["data"]
    assert payload["post_id"] == str(post_id)
    assert payload["content"] == "So cute!"
    assert payload["user"]["id"] == str(user.id)

    blank_response = client.post(
        f"/api/v1/posts/{post_id}/comments",
        headers={"Authorization": f"Bearer {token}"},
        json={"content": "   "},
    )
    assert blank_response.status_code == 422


def test_unauthenticated_comment_creation_rejected(
    client: TestClient,
    interactions_runtime,
) -> None:
    user, _ = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-unauth@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=user.id)
    post_id = _create_post(interactions_runtime.db_session_manager, cat_id=cat.id, user_id=user.id)

    response = client.post(f"/api/v1/posts/{post_id}/comments", json={"content": "No auth"})
    assert response.status_code == 401


def test_list_comments_with_stable_pagination(client: TestClient, interactions_runtime) -> None:
    author, token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-list@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
    )

    older = _create_comment(
        interactions_runtime.db_session_manager,
        post_id=post_id,
        user_id=author.id,
        content="Older",
        created_at=datetime.now(UTC) - timedelta(minutes=3),
    )
    middle = _create_comment(
        interactions_runtime.db_session_manager,
        post_id=post_id,
        user_id=author.id,
        content="Middle",
        created_at=datetime.now(UTC) - timedelta(minutes=2),
    )
    newer = _create_comment(
        interactions_runtime.db_session_manager,
        post_id=post_id,
        user_id=author.id,
        content="Newer",
        created_at=datetime.now(UTC) - timedelta(minutes=1),
    )

    first_page = client.get(
        f"/api/v1/posts/{post_id}/comments",
        params={"limit": 1, "order": "asc"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert first_page.status_code == 200
    first_payload = first_page.json()["data"]
    assert first_payload["items"][0]["id"] == str(older)
    assert first_payload["next_cursor"] is not None

    second_page = client.get(
        f"/api/v1/posts/{post_id}/comments",
        params={
            "limit": 1,
            "order": "asc",
            "cursor": first_payload["next_cursor"],
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert second_page.status_code == 200
    assert second_page.json()["data"]["items"][0]["id"] == str(middle)

    third_page = client.get(
        f"/api/v1/posts/{post_id}/comments",
        params={
            "limit": 1,
            "order": "asc",
            "cursor": second_page.json()["data"]["next_cursor"],
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert third_page.status_code == 200
    assert third_page.json()["data"]["items"][0]["id"] == str(newer)


def test_comment_delete_by_author_and_moderator(
    client: TestClient,
    interactions_runtime,
) -> None:
    author, author_token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-author@example.com",
    )
    _moderator, moderator_token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-moderator@example.com",
        is_moderator=True,
    )
    _other_user, other_token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-other@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
    )

    comment_response = client.post(
        f"/api/v1/posts/{post_id}/comments",
        headers={"Authorization": f"Bearer {author_token}"},
        json={"content": "Delete me"},
    )
    comment_id = UUID(comment_response.json()["data"]["id"])

    forbidden = client.delete(
        f"/api/v1/comments/{comment_id}",
        headers={"Authorization": f"Bearer {other_token}"},
    )
    assert forbidden.status_code == 403

    author_delete = client.delete(
        f"/api/v1/comments/{comment_id}",
        headers={"Authorization": f"Bearer {author_token}"},
    )
    assert author_delete.status_code == 204

    repeat_delete = client.delete(
        f"/api/v1/comments/{comment_id}",
        headers={"Authorization": f"Bearer {author_token}"},
    )
    assert repeat_delete.status_code == 204

    second_comment = client.post(
        f"/api/v1/posts/{post_id}/comments",
        headers={"Authorization": f"Bearer {author_token}"},
        json={"content": "Moderator delete"},
    )
    second_comment_id = UUID(second_comment.json()["data"]["id"])

    moderator_delete = client.delete(
        f"/api/v1/comments/{second_comment_id}",
        headers={"Authorization": f"Bearer {moderator_token}"},
    )
    assert moderator_delete.status_code == 204

    with interactions_runtime.db_session_manager.session_scope() as session:
        post = session.get(schema.Post, post_id)
        comments = session.execute(
            select(schema.Comment).where(
                schema.Comment.post_id == post_id,
                schema.Comment.deleted_at.is_(None),
            )
        ).all()
        assert post is not None
        assert post.comment_count == 0
        assert comments == []


def test_inaccessible_or_deleted_post_comment_behavior(
    client: TestClient,
    interactions_runtime,
) -> None:
    author, author_token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-private-author@example.com",
    )
    other_user, other_token = _create_user_with_token(
        interactions_runtime.db_session_manager,
        interactions_runtime.token_service,
        email="comment-private-other@example.com",
    )
    cat = _create_cat(interactions_runtime.db_session_manager, creator_id=author.id)
    private_post_id = _create_post(
        interactions_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        is_public=False,
    )

    private_comment = client.post(
        f"/api/v1/posts/{private_post_id}/comments",
        headers={"Authorization": f"Bearer {other_token}"},
        json={"content": "Hidden"},
    )
    assert private_comment.status_code == 404

    private_list = client.get(
        f"/api/v1/posts/{private_post_id}/comments",
        headers={"Authorization": f"Bearer {other_token}"},
    )
    assert private_list.status_code == 404

    delete_post = client.delete(
        f"/api/v1/posts/{private_post_id}",
        headers={"Authorization": f"Bearer {author_token}"},
    )
    assert delete_post.status_code == 204

    deleted_comment = client.post(
        f"/api/v1/posts/{private_post_id}/comments",
        headers={"Authorization": f"Bearer {author_token}"},
        json={"content": "After delete"},
    )
    assert deleted_comment.status_code == 404
