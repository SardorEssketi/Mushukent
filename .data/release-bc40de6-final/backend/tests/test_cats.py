from __future__ import annotations

import io
import json
from dataclasses import dataclass, field
from datetime import UTC, datetime
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi.testclient import TestClient
from geoalchemy2 import WKTElement
from PIL import Image
from sqlalchemy import select, text

from app.core.auth import AuthenticatedPrincipal, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.core.dependencies import get_cats_service
from app.core.security import api_error
from app.core.storage import ObjectStorage, StoredObject
from app.features.auth.domain.models import AuthUser
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.features.cats.application.schemas import CatCreateRequest
from app.features.cats.application.service import CatsService
from app.features.cats.infrastructure.repositories import SqlAlchemyCatRepository
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.storage.service import MediaStorageService
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
def cats_runtime(monkeypatch: pytest.MonkeyPatch, db_session_manager: DatabaseSessionManager):
    settings = _test_settings(monkeypatch)
    token_service = JoseAccessTokenService(settings)
    fake_storage = FakeObjectStorage()
    cats_service = CatsService(
        db_session_manager=db_session_manager,
        repository_factory=SqlAlchemyCatRepository,
        media_storage_service=MediaStorageService(storage=fake_storage),
    )

    app.state.container = AppContainer(settings=settings, db_session_manager=db_session_manager)
    app.dependency_overrides[get_cats_service] = lambda: cats_service

    context = SimpleNamespace(
        settings=settings,
        token_service=token_service,
        db_session_manager=db_session_manager,
        cats_service=cats_service,
        fake_storage=fake_storage,
    )

    try:
        yield context
    finally:
        app.dependency_overrides.clear()


@pytest.fixture()
def client(cats_runtime):
    with TestClient(app) as test_client:
        yield test_client


def _create_user_with_token(
    db_session_manager: DatabaseSessionManager,
    token_service: JoseAccessTokenService,
    *,
    email: str,
    name: str = "Cat User",
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


def _insert_cat_with_posts(
    db_session_manager: DatabaseSessionManager,
    *,
    cat_id: UUID,
    user_id: UUID,
) -> None:
    with db_session_manager.session_scope() as session:
        other_user = schema.User(
            email=f"other-{uuid4().hex}@example.com",
            name="Other User",
            password_hash=None,
        )
        session.add(other_user)
        session.flush()

        first_post = schema.Post(
            cat_id=cat_id,
            user_id=user_id,
            photo_url="https://example.com/first.jpg",
            location=WKTElement("POINT(69.2500 41.3000)", srid=4326),
            like_count=1,
        )
        second_post = schema.Post(
            cat_id=cat_id,
            user_id=other_user.id,
            photo_url="https://example.com/second.jpg",
            location=WKTElement("POINT(69.2501 41.3001)", srid=4326),
            comment_count=1,
        )
        session.add_all([first_post, second_post])
        session.flush()
        session.add_all(
            [
                schema.Like(post_id=first_post.id, user_id=other_user.id),
                schema.Comment(post_id=second_post.id, user_id=user_id, content="Cute cat"),
            ]
        )


def test_authenticated_cat_creation(client: TestClient, cats_runtime) -> None:
    user, token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="create-cat@example.com",
    )

    response = client.post(
        "/api/v1/cats",
        headers={"Authorization": f"Bearer {token}"},
        data={
            "name": "Mittens",
            "status": "unknown",
            "canonical_location": json.dumps({"latitude": 41.3, "longitude": 69.25}),
        },
        files={
            "cover_photo": ("cover.jpg", _jpeg_bytes(), "image/jpeg"),
        },
    )
    assert response.status_code == 201
    payload = response.json()["data"]
    assert payload["name"] == "Mittens"
    assert payload["status"] == "unknown"
    assert payload["cover_photo_url"].startswith("https://storage.example/cats/covers/")
    assert payload["canonical_location"]["latitude"] == pytest.approx(41.3)
    assert payload["canonical_location"]["longitude"] == pytest.approx(69.25)
    assert "created_by" not in payload
    assert "deleted_at" not in payload
    assert "is_active" not in payload
    assert "merged_into" not in payload

    with cats_runtime.db_session_manager.session_scope() as session:
        created = session.scalar(select(schema.Cat).where(schema.Cat.name == "Mittens"))
        assert created is not None
        assert created.created_by == user.id
        assert created.cover_photo_url == payload["cover_photo_url"]

    assert len(cats_runtime.fake_storage.objects) == 1
    stored_key = next(iter(cats_runtime.fake_storage.objects))
    assert stored_key.startswith("cats/covers/")


def test_unauthorized_creation(client: TestClient) -> None:
    response = client.post("/api/v1/cats", json={"name": "Unauthorized"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "UNAUTHORIZED"


def test_validation_failures(client: TestClient, cats_runtime) -> None:
    _, token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="validation-cat@example.com",
    )

    response = client.post(
        "/api/v1/cats",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "name": "a" * 101,
            "canonical_location": {"latitude": 200, "longitude": 69.25},
        },
    )
    assert response.status_code == 422

    list_response = client.get(
        "/api/v1/cats",
        params={"filter": "nearby", "lat": 41.3, "lon": 69.25, "radius_meters": 0},
    )
    assert list_response.status_code == 422


def test_cat_detail_retrieval(client: TestClient, cats_runtime) -> None:
    user, token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="detail-cat@example.com",
    )
    create_response = client.post(
        "/api/v1/cats",
        headers={"Authorization": f"Bearer {token}"},
        json={
            "name": "Detail Cat",
            "status": "unknown",
            "canonical_location": {"latitude": 41.3, "longitude": 69.25},
        },
    )
    cat_id = UUID(create_response.json()["data"]["id"])
    _insert_cat_with_posts(cats_runtime.db_session_manager, cat_id=cat_id, user_id=user.id)

    response = client.get(f"/api/v1/cats/{cat_id}")
    assert response.status_code == 200
    payload = response.json()["data"]
    assert payload["id"] == str(cat_id)
    assert payload["name"] == "Detail Cat"
    assert payload["total_observations"] == 2
    assert payload["total_contributors"] == 2
    assert payload["total_likes"] == 1
    assert len(payload["observation_history"]["items"]) == 2
    assert "next_cursor" not in payload["observation_history"]
    assert "created_by" not in payload
    assert "is_active" not in payload


def test_missing_and_soft_deleted_cat_behavior(client: TestClient, cats_runtime) -> None:
    missing_response = client.get(f"/api/v1/cats/{uuid4()}")
    assert missing_response.status_code == 404
    assert missing_response.json()["error"]["code"] == "CAT_NOT_FOUND"

    user, token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="deleted-cat@example.com",
    )
    create_response = client.post(
        "/api/v1/cats",
        headers={"Authorization": f"Bearer {token}"},
        json={"name": "Soft Deleted Cat"},
    )
    cat_id = UUID(create_response.json()["data"]["id"])

    with cats_runtime.db_session_manager.session_scope() as session:
        cat = session.get(schema.Cat, cat_id)
        assert cat is not None
        cat.deleted_at = datetime.now(UTC)

    deleted_response = client.get(f"/api/v1/cats/{cat_id}")
    assert deleted_response.status_code == 404


def test_allowed_and_forbidden_updates(client: TestClient, cats_runtime) -> None:
    user, user_token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="cat-update@example.com",
    )
    moderator, moderator_token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="cat-moderator@example.com",
        is_moderator=True,
    )

    create_response = client.post(
        "/api/v1/cats",
        headers={"Authorization": f"Bearer {user_token}"},
        json={"name": "Update Target"},
    )
    cat_id = UUID(create_response.json()["data"]["id"])

    allowed = client.patch(
        f"/api/v1/cats/{cat_id}",
        headers={"Authorization": f"Bearer {user_token}"},
        json={"name": "Updated Name"},
    )
    assert allowed.status_code == 200
    assert allowed.json()["data"]["name"] == "Updated Name"

    forbidden = client.patch(
        f"/api/v1/cats/{cat_id}",
        headers={"Authorization": f"Bearer {user_token}"},
        json={"status": "healthy"},
    )
    assert forbidden.status_code == 403
    assert forbidden.json()["error"]["code"] == "FORBIDDEN"

    merge_target = client.post(
        "/api/v1/cats",
        headers={"Authorization": f"Bearer {moderator_token}"},
        json={"name": "Merge Target"},
    )
    target_id = UUID(merge_target.json()["data"]["id"])

    moderator_update = client.patch(
        f"/api/v1/cats/{cat_id}",
        headers={"Authorization": f"Bearer {moderator_token}"},
        json={"status": "healthy", "merged_into": str(target_id)},
    )
    assert moderator_update.status_code == 200
    payload = moderator_update.json()["data"]
    assert payload["status"] == "healthy"

    with cats_runtime.db_session_manager.session_scope() as session:
        cat = session.get(schema.Cat, cat_id)
        assert cat is not None
        assert cat.merged_into == target_id


def test_postgis_nearby_query_and_index_usage(client: TestClient, cats_runtime) -> None:
    _user, token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="geo-cat@example.com",
    )

    cat_ids = []
    coordinates = [
        (41.3000, 69.2500),
        (41.3004, 69.2504),
        (41.3010, 69.2510),
    ]
    for index, (latitude, longitude) in enumerate(coordinates, start=1):
        response = client.post(
            "/api/v1/cats",
            headers={"Authorization": f"Bearer {token}"},
            json={
                "name": f"Geo Cat {index}",
                "canonical_location": {"latitude": latitude, "longitude": longitude},
            },
        )
        cat_ids.append(UUID(response.json()["data"]["id"]))

    nearby = client.get(
        "/api/v1/cats",
        params={
            "filter": "nearby",
            "lat": 41.3000,
            "lon": 69.2500,
            "radius_meters": 500,
            "limit": 2,
        },
    )
    assert nearby.status_code == 200
    nearby_payload = nearby.json()["data"]
    assert len(nearby_payload["items"]) == 2
    assert nearby_payload["next_cursor"] is not None
    assert nearby_payload["items"][0]["id"] == str(cat_ids[0])
    assert nearby_payload["items"][1]["id"] == str(cat_ids[1])

    with cats_runtime.db_session_manager.session_scope() as session:
        session.execute(text("SET LOCAL enable_seqscan = off"))
        plan = (
            session.execute(
                text(
                    """
                EXPLAIN (COSTS OFF)
                SELECT id
                FROM cats
                WHERE deleted_at IS NULL
                  AND is_active IS TRUE
                  AND merged_into IS NULL
                  AND canonical_location IS NOT NULL
                  AND canonical_location && ST_Expand(
                        ST_SetSRID(ST_MakePoint(:lon, :lat), 4326),
                        :degree_radius
                  )
                  AND ST_DWithin(
                        canonical_location::geography,
                        ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography,
                        :radius_meters
                  )
                ORDER BY ST_Distance(
                    canonical_location::geography,
                    ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)::geography
                ), id
                LIMIT 2
                """
                ),
                {
                    "lat": 41.3000,
                    "lon": 69.2500,
                    "degree_radius": 500 / 111_320.0,
                    "radius_meters": 500,
                },
            )
            .scalars()
            .all()
        )
    assert any("cats_canonical_location_gist" in line for line in plan)


def test_image_storage_integration_using_fake_storage_adapter(
    client: TestClient, cats_runtime
) -> None:
    _, token = _create_user_with_token(
        cats_runtime.db_session_manager,
        cats_runtime.token_service,
        email="cover-photo@example.com",
    )

    response = client.post(
        "/api/v1/cats",
        headers={"Authorization": f"Bearer {token}"},
        data={"name": "Cover Cat"},
        files={"cover_photo": ("cover.jpg", _jpeg_bytes(), "image/jpeg")},
    )
    assert response.status_code == 201
    payload = response.json()["data"]
    assert payload["cover_photo_url"].startswith("https://storage.example/cats/covers/")
    assert len(cats_runtime.fake_storage.objects) == 1


def test_cleanup_when_database_persistence_fails_after_upload(cats_runtime) -> None:
    uploaded_keys_before = len(cats_runtime.fake_storage.objects)

    class FailingCatRepository(SqlAlchemyCatRepository):
        def create(self, *, cat):  # type: ignore[override]
            super().create(cat=cat)
            raise api_error(500, "INTERNAL_SERVER_ERROR", "force rollback")

    failing_service = CatsService(
        db_session_manager=cats_runtime.db_session_manager,
        repository_factory=FailingCatRepository,
        media_storage_service=MediaStorageService(storage=cats_runtime.fake_storage),
    )

    with cats_runtime.db_session_manager.session_scope() as session:
        auth_user = schema.User(
            email="rollback@example.com",
            name="Rollback",
            password_hash=None,
        )
        session.add(auth_user)
        session.flush()
        rollback_user = AuthUser(
            id=auth_user.id,
            email=auth_user.email,
            password_hash=None,
            name=auth_user.name,
            avatar_url=auth_user.avatar_url,
            bio=auth_user.bio,
            email_verified=auth_user.email_verified,
            is_active=auth_user.is_active,
            is_moderator=auth_user.is_moderator,
            registered_at=auth_user.registered_at,
            last_login_at=auth_user.last_login_at,
        )

    with pytest.raises(Exception) as excinfo:
        failing_service.create_cat(
            rollback_user,
            CatCreateRequest.model_validate({"name": "Rollback Cat"}),
            cover_photo_content=_jpeg_bytes(),
            cover_photo_content_type="image/jpeg",
            cover_photo_filename="rollback.jpg",
        )

    assert getattr(excinfo.value, "status_code", 500) == 500
    assert len(cats_runtime.fake_storage.objects) == uploaded_keys_before
    assert cats_runtime.fake_storage.deleted_keys

    with cats_runtime.db_session_manager.session_scope() as session:
        persisted = session.scalar(select(schema.Cat).where(schema.Cat.name == "Rollback Cat"))
        assert persisted is None
