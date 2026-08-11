from __future__ import annotations

import io
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from geoalchemy2.elements import WKTElement
from PIL import Image
from sqlalchemy import select

from app.core.auth import AuthenticatedPrincipal, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.core.storage import ObjectStorage, StoredObject
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.features.cats.domain.models import CatStatus
from app.features.posts.infrastructure.repositories import SqlAlchemyPostRepository
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


@dataclass(slots=True)
class FakeObjectStorage(ObjectStorage):
    bucket_name: str = "fake-bucket"
    objects: dict[str, StoredObject] = field(default_factory=dict)
    deleted_keys: list[str] = field(default_factory=list)

    def upload(
        self,
        *,
        key: str,
        content: bytes,
        content_type: str,
        metadata: dict[str, str] | None = None,
        cache_control: str | None = None,
    ) -> StoredObject:
        stored = StoredObject(
            key=key,
            url=self.public_url(key),
            content_type=content_type,
            size_bytes=len(content),
            etag="fake-etag",
        )
        self.objects[key] = stored
        return stored

    def delete(self, key: str) -> None:
        self.deleted_keys.append(key)
        self.objects.pop(key, None)

    def exists(self, key: str) -> bool:
        return key in self.objects

    def public_url(self, key: str) -> str:
        return f"https://storage.example/{key}"


@pytest.fixture()
def posts_runtime(monkeypatch: pytest.MonkeyPatch, db_session_manager: DatabaseSessionManager):
    settings = _test_settings(monkeypatch)
    token_service = JoseAccessTokenService(settings)
    fake_storage = FakeObjectStorage()

    app.state.container = AppContainer(
        settings=settings,
        db_session_manager=db_session_manager,
        object_storage=fake_storage,
    )
    app.dependency_overrides.clear()

    context = SimpleNamespace(
        settings=settings,
        token_service=token_service,
        db_session_manager=db_session_manager,
        fake_storage=fake_storage,
    )

    try:
        yield context
    finally:
        app.dependency_overrides.clear()


@pytest.fixture()
def client(posts_runtime):
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


def _create_user_with_token(
    db_session_manager: DatabaseSessionManager,
    token_service: JoseAccessTokenService,
    *,
    email: str,
    name: str = "Post User",
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


def _jpeg_bytes(
    color: tuple[int, int, int] = (255, 0, 0), size: tuple[int, int] = (512, 512)
) -> bytes:
    image = Image.new("RGB", size, color=color)
    buffer = io.BytesIO()
    image.save(buffer, format="JPEG", quality=90)
    return buffer.getvalue()


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


def _create_seeded_post(
    db_session_manager: DatabaseSessionManager,
    *,
    cat_id: UUID,
    user_id: UUID,
    created_at: datetime,
    description: str,
    is_public: bool = True,
) -> UUID:
    with db_session_manager.session_scope() as session:
        post = schema.Post(
            cat_id=cat_id,
            user_id=user_id,
            photo_url=f"https://example.com/{uuid4().hex}.jpg",
            thumb_url=f"https://example.com/{uuid4().hex}.jpg",
            description=description,
            location=WKTElement("POINT(69.25 41.3)", srid=4326),
            status=CatStatus.UNKNOWN,
            is_public=is_public,
            like_count=0,
            comment_count=0,
            created_at=created_at,
            updated_at=created_at,
        )
        session.add(post)
        session.flush()
        return post.id


def test_authenticated_post_creation_with_existing_cat_and_image_upload(
    client: TestClient,
    posts_runtime,
) -> None:
    user, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="create-post@example.com",
    )
    cat = _create_cat(
        posts_runtime.db_session_manager,
        creator_id=user.id,
        name="Existing Cat",
    )

    response = client.post(
        "/api/v1/posts",
        headers={"Authorization": f"Bearer {token}"},
        data={
            "cat_id": str(cat.id),
            "description": "Saw this kitty near the market",
            "status": "healthy",
            "latitude": "41.3",
            "longitude": "69.25",
            "is_public": "true",
        },
        files={
            "photo": ("observation.jpg", _jpeg_bytes(), "image/jpeg"),
        },
    )

    assert response.status_code == 201
    payload = response.json()["data"]
    assert payload["cat"]["id"] == str(cat.id)
    assert payload["author"]["id"] == str(user.id)
    assert payload["photo_url"].startswith("https://storage.example/posts/original/")
    assert payload["thumb_url"].startswith("https://storage.example/posts/thumbs/")
    assert payload["description"] == "Saw this kitty near the market"
    assert payload["location"]["latitude"] == pytest.approx(41.3)
    assert payload["location"]["longitude"] == pytest.approx(69.25)
    assert payload["like_count"] == 0
    assert payload["comment_count"] == 0
    assert payload["is_liked_by_me"] is False
    assert "user_id" not in payload
    assert "cat_id" not in payload
    assert "deleted_at" not in payload
    assert "is_public" not in payload

    with posts_runtime.db_session_manager.session_scope() as session:
        stored_post = session.scalar(select(schema.Post).where(schema.Post.cat_id == cat.id))
        stored_cat = session.get(schema.Cat, cat.id)
        assert stored_post is not None
        assert stored_post.photo_url == payload["photo_url"]
        assert stored_cat is not None
        assert stored_cat.total_observations == 1
        assert stored_cat.total_contributors == 1
        assert stored_cat.first_seen_at is not None
        assert stored_cat.last_seen_at is not None

    assert len(posts_runtime.fake_storage.objects) == 2


def test_create_post_with_new_cat_workflow(client: TestClient, posts_runtime) -> None:
    user, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="new-cat-post@example.com",
    )

    response = client.post(
        "/api/v1/posts",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "photo_url": "https://storage.example/existing.jpg",
            "new_cat": {
                "name": "New Cat",
                "status": "needs_help",
                "canonical_location": {"latitude": 41.31, "longitude": 69.26},
            },
            "description": "New cat found near the park",
            "location": {"latitude": 41.31, "longitude": 69.26},
            "is_public": False,
        },
    )

    assert response.status_code == 201
    payload = response.json()["data"]
    assert payload["description"] == "New cat found near the park"
    assert "thumb_url" not in payload
    assert payload["is_liked_by_me"] is False

    with posts_runtime.db_session_manager.session_scope() as session:
        stored_cat = session.scalar(select(schema.Cat).where(schema.Cat.name == "New Cat"))
        stored_post = session.scalar(
            select(schema.Post).where(schema.Post.description == "New cat found near the park")
        )
        assert stored_cat is not None
        assert stored_cat.created_by == user.id
        assert stored_post is not None
        assert stored_post.cat_id == stored_cat.id


def test_unauthorized_creation(client: TestClient) -> None:
    response = client.post("/api/v1/posts", json={"photo_url": "https://example.com/photo.jpg"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_required_image_behavior(client: TestClient, posts_runtime) -> None:
    _, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="required-image@example.com",
    )
    cat = _create_cat(posts_runtime.db_session_manager, creator_id=None)

    response = client.post(
        "/api/v1/posts",
        headers={"Authorization": f"Bearer {token}"},
        files=[
            ("cat_id", (None, str(cat.id))),
            ("description", (None, "No photo")),
            ("latitude", (None, "41.3")),
            ("longitude", (None, "69.25")),
        ],
    )
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "INVALID_PAYLOAD"


@pytest.mark.parametrize(
    "filename, content_type, content, expected_code",
    [
        ("observation.jpg", "text/plain", _jpeg_bytes(), "INVALID_IMAGE"),
        ("observation.jpg", "image/jpeg", b"not-an-image", "INVALID_IMAGE"),
    ],
)
def test_invalid_image_inputs(
    client: TestClient,
    posts_runtime,
    filename: str,
    content_type: str,
    content: bytes,
    expected_code: str,
) -> None:
    _, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="invalid-image@example.com",
    )
    cat = _create_cat(posts_runtime.db_session_manager, creator_id=None)

    response = client.post(
        "/api/v1/posts",
        headers={"Authorization": f"Bearer {token}"},
        data={
            "cat_id": str(cat.id),
            "description": "Invalid image",
            "latitude": "41.3",
            "longitude": "69.25",
        },
        files={"photo": (filename, content, content_type)},
    )
    assert response.status_code == 422
    assert response.json()["error"]["code"] == expected_code


def test_invalid_description_and_coordinates(client: TestClient, posts_runtime) -> None:
    _, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="invalid-fields@example.com",
    )
    cat = _create_cat(posts_runtime.db_session_manager, creator_id=None)

    response = client.post(
        "/api/v1/posts",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "photo_url": "https://storage.example/valid.jpg",
            "cat_id": str(cat.id),
            "description": "x" * 2001,
            "location": {"latitude": 200, "longitude": 69.25},
        },
    )
    assert response.status_code == 422


def test_post_detail_retrieval_and_private_field_boundary(
    client: TestClient,
    posts_runtime,
) -> None:
    author, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="detail-post@example.com",
    )
    cat = _create_cat(posts_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_seeded_post(
        posts_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        created_at=datetime.now(UTC) - timedelta(minutes=2),
        description="Seeded observation",
    )

    response = client.get(f"/api/v1/posts/{post_id}")
    assert response.status_code == 200
    payload = response.json()["data"]
    assert payload["id"] == str(post_id)
    assert payload["cat"]["id"] == str(cat.id)
    assert payload["cat"]["name"] == cat.name
    assert payload["author"]["id"] == str(author.id)
    assert payload["author"]["name"] == author.name
    assert payload["photo_url"].startswith("https://example.com/")
    assert payload["thumb_url"].startswith("https://example.com/")
    assert payload["description"] == "Seeded observation"
    assert payload["created_at"] is not None
    assert payload["like_count"] == 0
    assert payload["comment_count"] == 0
    assert payload["is_liked_by_me"] is False
    assert "user_id" not in payload
    assert "cat_id" not in payload
    assert "deleted_at" not in payload
    assert "is_public" not in payload


def test_cat_association_validation(
    client: TestClient,
    posts_runtime,
) -> None:
    user, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="cat-association@example.com",
    )

    missing_cat_id = uuid4()
    deleted_cat = _create_cat(
        posts_runtime.db_session_manager,
        creator_id=user.id,
        deleted_at=datetime.now(UTC),
    )
    inactive_cat = _create_cat(
        posts_runtime.db_session_manager,
        creator_id=user.id,
        is_active=False,
    )
    merged_target_cat = _create_cat(
        posts_runtime.db_session_manager,
        creator_id=user.id,
        name="Merge Target",
    )
    merged_cat = _create_cat(
        posts_runtime.db_session_manager,
        creator_id=user.id,
        merged_into=merged_target_cat.id,
    )

    for cat_id in (missing_cat_id, deleted_cat.id, inactive_cat.id, merged_cat.id):
        response = client.post(
            "/api/v1/posts",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "photo_url": "https://storage.example/valid.jpg",
                "cat_id": str(cat_id),
                "description": "Association check",
                "location": {"latitude": 41.3, "longitude": 69.25},
            },
        )
        assert response.status_code == 404
        assert response.json()["error"]["code"] == "CAT_NOT_FOUND"


def test_private_post_visibility_and_soft_delete_behavior(
    client: TestClient,
    posts_runtime,
) -> None:
    author, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="private-post@example.com",
    )
    cat = _create_cat(posts_runtime.db_session_manager, creator_id=author.id)

    create_response = client.post(
        "/api/v1/posts",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "photo_url": "https://storage.example/private.jpg",
            "cat_id": str(cat.id),
            "description": "Private observation",
            "location": {"latitude": 41.31, "longitude": 69.26},
            "is_public": False,
        },
    )
    assert create_response.status_code == 201
    post_id = UUID(create_response.json()["data"]["id"])

    anonymous_response = client.get(f"/api/v1/posts/{post_id}")
    assert anonymous_response.status_code == 404

    author_response = client.get(
        f"/api/v1/posts/{post_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert author_response.status_code == 200

    user_posts_response = client.get(
        f"/api/v1/users/{author.id}/posts",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert user_posts_response.status_code == 200
    assert len(user_posts_response.json()["data"]["items"]) == 1

    delete_response = client.delete(
        f"/api/v1/posts/{post_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert delete_response.status_code == 204

    repeat_delete_response = client.delete(
        f"/api/v1/posts/{post_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert repeat_delete_response.status_code == 204

    deleted_detail_response = client.get(
        f"/api/v1/posts/{post_id}",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert deleted_detail_response.status_code == 404


def test_listing_by_cat_and_author_paginates_stably(
    client: TestClient,
    posts_runtime,
) -> None:
    author, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="pagination@example.com",
    )
    cat = _create_cat(posts_runtime.db_session_manager, creator_id=author.id)
    older = _create_seeded_post(
        posts_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        created_at=datetime.now(UTC) - timedelta(minutes=5),
        description="Older observation",
    )
    newer = _create_seeded_post(
        posts_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        created_at=datetime.now(UTC) - timedelta(minutes=1),
        description="Newer observation",
    )

    user_page = client.get(
        f"/api/v1/users/{author.id}/posts",
        params={"limit": 1, "sort": "latest"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert user_page.status_code == 200
    user_page_payload = user_page.json()["data"]
    assert len(user_page_payload["items"]) == 1
    assert user_page_payload["items"][0]["id"] == str(newer)
    assert user_page_payload["next_cursor"] is not None

    next_page = client.get(
        f"/api/v1/users/{author.id}/posts",
        params={"limit": 1, "sort": "latest", "cursor": user_page_payload["next_cursor"]},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert next_page.status_code == 200
    assert next_page.json()["data"]["items"][0]["id"] == str(older)

    cat_page = client.get(
        f"/api/v1/cats/{cat.id}/posts",
        params={"limit": 2, "sort": "oldest"},
    )
    assert cat_page.status_code == 200
    cat_items = cat_page.json()["data"]["items"]
    assert [item["id"] for item in cat_items] == [str(older), str(newer)]


def test_cleanup_and_rollback_on_database_failure_after_upload(
    client: TestClient,
    posts_runtime,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    user, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="rollback@example.com",
    )
    cat = _create_cat(posts_runtime.db_session_manager, creator_id=user.id)

    def fail_after_insert(self, cat_id: UUID):
        raise RuntimeError("database failure after upload")

    monkeypatch.setattr(
        SqlAlchemyPostRepository,
        "recalculate_cat_stats",
        fail_after_insert,
    )

    response = client.post(
        "/api/v1/posts",
        headers={"Authorization": f"Bearer {token}"},
        data={
            "cat_id": str(cat.id),
            "description": "Will roll back",
            "latitude": "41.3",
            "longitude": "69.25",
        },
        files={
            "photo": ("rollback.jpg", _jpeg_bytes(), "image/jpeg"),
        },
    )
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "INTERNAL_SERVER_ERROR"
    assert len(posts_runtime.fake_storage.deleted_keys) == 2
    assert posts_runtime.fake_storage.objects == {}

    with posts_runtime.db_session_manager.session_scope() as session:
        post_count = session.scalar(select(schema.Post).where(schema.Post.cat_id == cat.id))
        stored_cat = session.get(schema.Cat, cat.id)
        assert post_count is None
        assert stored_cat is not None
        assert stored_cat.total_observations == 0
