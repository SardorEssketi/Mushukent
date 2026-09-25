from __future__ import annotations

from datetime import UTC, datetime, timedelta
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
from app.infrastructure.db.enums import PlaceCategory, PlaceSource, PostKind
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
def feed_runtime(
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
def client(feed_runtime):
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


def _create_user_with_token(
    db_session_manager: DatabaseSessionManager,
    token_service: JoseAccessTokenService,
    *,
    email: str,
    name: str = "Feed User",
    is_active: bool = True,
    is_moderator: bool = False,
    allow_public_activity_view: bool = True,
):
    with db_session_manager.session_scope() as session:
        user = schema.User(
            email=email,
            name=name,
            password_hash=PasslibPasswordHasher().hash_password("StrongPass123"),
            is_active=is_active,
            is_moderator=is_moderator,
            allow_public_activity_view=allow_public_activity_view,
        )
        session.add(user)
        session.flush()
        token = token_service.issue_access_token(
            AuthenticatedPrincipal(
                user_id=user.id,
                role=Role.MODERATOR if is_moderator else Role.USER,
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
    canonical_location: tuple[float, float] | None = None,
):
    with db_session_manager.session_scope() as session:
        cat = schema.Cat(
            name=name,
            status=status,
            created_by=creator_id,
            is_active=is_active,
            deleted_at=deleted_at,
            merged_into=merged_into,
            canonical_location=(
                WKTElement(
                    f"POINT({canonical_location[1]} {canonical_location[0]})",
                    srid=4326,
                )
                if canonical_location is not None
                else None
            ),
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
    description: str = "Observation",
    is_public: bool = True,
    like_count: int = 0,
    comment_count: int = 0,
    latitude: float | None = 41.3,
    longitude: float | None = 69.25,
    created_at: datetime | None = None,
    deleted_at: datetime | None = None,
    kind: PostKind = PostKind.OBSERVATION,
):
    created_at = created_at or datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        post = schema.Post(
            cat_id=cat_id,
            user_id=user_id,
            photo_url=photo_url,
            thumb_url="https://example.com/thumb.jpg",
            description=description,
            location=(
                WKTElement(f"POINT({longitude} {latitude})", srid=4326)
                if latitude is not None and longitude is not None
                else None
            ),
            status=CatStatus.UNKNOWN,
            kind=kind,
            is_public=is_public,
            like_count=like_count,
            comment_count=comment_count,
            created_at=created_at,
            updated_at=created_at,
            deleted_at=deleted_at,
        )
        session.add(post)
        session.flush()
        return post.id


def _create_comment(
    db_session_manager: DatabaseSessionManager,
    *,
    user_id: UUID,
    post_id: UUID | None = None,
    lost_pet_id: UUID | None = None,
    adoption_post_id: UUID | None = None,
    content: str = "Helpful comment",
    created_at: datetime | None = None,
    deleted_at: datetime | None = None,
):
    created_at = created_at or datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        comment = schema.Comment(
            post_id=post_id,
            lost_pet_id=lost_pet_id,
            adoption_post_id=adoption_post_id,
            user_id=user_id,
            content=content,
            created_at=created_at,
            updated_at=created_at,
            deleted_at=deleted_at,
        )
        session.add(comment)
        session.flush()
        return comment.id


def _create_place(
    db_session_manager: DatabaseSessionManager,
    *,
    name: str,
    category: PlaceCategory,
    categories: list[PlaceCategory] | None = None,
    latitude: float,
    longitude: float,
    phone: str | None = None,
    phone_2: str | None = None,
    instagram: str | None = None,
    telegram: str | None = None,
    days_off: str | None = None,
    description: str | None = None,
    source_id: str | None = None,
):
    with db_session_manager.session_scope() as session:
        place = schema.Place(
            name=name,
            category=category,
            location=WKTElement(f"POINT({longitude} {latitude})", srid=4326),
            phone=phone,
            phone_2=phone_2,
            instagram=instagram,
            telegram=telegram,
            days_off=days_off,
            description=description,
            source=PlaceSource.OSM,
            source_id=source_id,
            is_active=True,
        )
        if categories is not None:
            place.category_links = [
                schema.PlaceCategoryLink(category=place_category) for place_category in categories
            ]
        session.add(place)
        session.flush()
        return place.id


def _create_adoption_post(
    db_session_manager: DatabaseSessionManager,
    *,
    user_id: UUID,
    pet_name: str = "Mittens",
    created_at: datetime | None = None,
):
    created_at = created_at or datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        adoption_post = schema.AdoptionPost(
            user_id=user_id,
            pet_name=pet_name,
            owner_phone_number="+998 90 123 45 67",
            owner_phone_publication_consent=True,
            additional_info="Looking for a good home.",
            is_public=True,
            created_at=created_at,
            updated_at=created_at,
        )
        adoption_post.photos = [
            schema.AdoptionPostPhoto(
                photo_url="https://example.com/adoption.jpg",
                thumb_url="https://example.com/adoption-thumb.jpg",
                position=0,
            )
        ]
        session.add(adoption_post)
        session.flush()
        return adoption_post.id


def _create_lost_pet(
    db_session_manager: DatabaseSessionManager,
    *,
    user_id: UUID,
    pet_name: str = "Mittens",
    latitude: float = 41.3,
    longitude: float = 69.25,
    created_at: datetime | None = None,
    is_public: bool = True,
    is_resolved: bool = False,
    deleted_at: datetime | None = None,
):
    created_at = created_at or datetime.now(UTC)
    with db_session_manager.session_scope() as session:
        lost_pet = schema.LostPet(
            user_id=user_id,
            pet_name=pet_name,
            owner_phone_number="+998 90 123 45 67",
            owner_phone_publication_consent=True,
            last_seen_location=WKTElement(f"POINT({longitude} {latitude})", srid=4326),
            additional_info="Please help find this pet.",
            is_resolved=is_resolved,
            is_public=is_public,
            created_at=created_at,
            updated_at=created_at,
            deleted_at=deleted_at,
        )
        lost_pet.photos = [
            schema.LostPetPhoto(
                photo_url="https://example.com/lost-pet.jpg",
                thumb_url="https://example.com/lost-pet-thumb.jpg",
                position=0,
            )
        ]
        session.add(lost_pet)
        session.flush()
        return lost_pet.id


def test_anonymous_recent_feed_hides_private_deleted_and_unavailable_posts(
    client: TestClient,
    feed_runtime,
) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-author@example.com",
    )
    other, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-other@example.com",
    )
    visible_cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    unavailable_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=author.id,
        is_active=False,
    )

    visible_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=visible_cat.id,
        user_id=author.id,
        created_at=datetime.now(UTC) - timedelta(minutes=1),
    )
    private_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=visible_cat.id,
        user_id=author.id,
        is_public=False,
        created_at=datetime.now(UTC) - timedelta(minutes=2),
    )
    deleted_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=visible_cat.id,
        user_id=other.id,
        deleted_at=datetime.now(UTC),
        created_at=datetime.now(UTC) - timedelta(minutes=3),
    )
    hidden_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=unavailable_cat.id,
        user_id=other.id,
        created_at=datetime.now(UTC) - timedelta(minutes=4),
    )

    response = client.get("/api/v1/feed", params={"filter": "recent", "limit": 20})
    assert response.status_code == 200
    payload = response.json()["data"]
    ids = [item["id"] for item in payload["items"]]
    assert str(visible_post) in ids
    assert str(private_post) not in ids
    assert str(deleted_post) not in ids
    assert str(hidden_post) not in ids
    assert payload["items"][0]["id"] == str(visible_post)


def test_recent_feed_returns_null_location_for_locationless_posts(
    client: TestClient,
    feed_runtime,
) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-locationless@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        latitude=None,
        longitude=None,
    )

    response = client.get("/api/v1/feed", params={"filter": "recent", "limit": 20})

    assert response.status_code == 200
    items = response.json()["data"]["items"]
    item = next(item for item in items if item["id"] == str(post_id))
    assert "location" in item
    assert item["location"] is None


def test_recent_feed_includes_adoption_posts(client: TestClient, feed_runtime) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-adoption@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        created_at=datetime.now(UTC) - timedelta(minutes=2),
    )
    adoption_post_id = _create_adoption_post(
        feed_runtime.db_session_manager,
        user_id=author.id,
        created_at=datetime.now(UTC) - timedelta(minutes=1),
    )

    response = client.get("/api/v1/feed", params={"filter": "recent", "limit": 20})

    assert response.status_code == 200
    items = response.json()["data"]["items"]
    assert [item["id"] for item in items[:2]] == [str(adoption_post_id), str(post_id)]
    assert items[0]["item_type"] == "adoption"
    assert "last_seen_location" not in items[0]


def test_recent_mixed_feed_cursor_paginates_without_duplicates_or_skips(
    client: TestClient,
    feed_runtime,
) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-mixed-pagination@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    newest_time = datetime.now(UTC) - timedelta(minutes=1)
    older_time = newest_time - timedelta(minutes=1)

    newest_observation = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        created_at=newest_time,
    )
    newest_lost_pet = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=author.id,
        created_at=newest_time,
    )
    newest_adoption = _create_adoption_post(
        feed_runtime.db_session_manager,
        user_id=author.id,
        created_at=newest_time,
    )
    older_observation = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        created_at=older_time,
    )
    older_lost_pet = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=author.id,
        created_at=older_time,
    )
    older_adoption = _create_adoption_post(
        feed_runtime.db_session_manager,
        user_id=author.id,
        created_at=older_time,
    )

    seen_ids: list[str] = []
    cursor = None
    for _ in range(3):
        params = {"filter": "recent", "limit": 2}
        if cursor is not None:
            params["cursor"] = cursor
        response = client.get("/api/v1/feed", params=params)
        assert response.status_code == 200
        payload = response.json()["data"]
        seen_ids.extend(item["id"] for item in payload["items"])
        cursor = payload["next_cursor"]

    assert seen_ids == [
        str(newest_observation),
        str(newest_lost_pet),
        str(newest_adoption),
        str(older_observation),
        str(older_lost_pet),
        str(older_adoption),
    ]
    assert len(seen_ids) == len(set(seen_ids))
    assert cursor is None


def test_nearby_mixed_feed_orders_globally_and_excludes_adoption(
    client: TestClient,
    feed_runtime,
) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-nearby-mixed@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    observation = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        latitude=41.3002,
        longitude=69.25,
    )
    lost_pet = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=author.id,
        latitude=41.3001,
        longitude=69.25,
    )
    adoption = _create_adoption_post(
        feed_runtime.db_session_manager,
        user_id=author.id,
    )

    response = client.get(
        "/api/v1/feed",
        params={
            "filter": "nearby",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
    )

    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["data"]["items"]]
    assert ids.index(str(lost_pet)) < ids.index(str(observation))
    assert str(adoption) not in ids


def test_adoption_feed_filter_returns_only_adoption_posts(
    client: TestClient,
    feed_runtime,
) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-adoption-filter@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
    )
    adoption_post_id = _create_adoption_post(
        feed_runtime.db_session_manager,
        user_id=author.id,
    )

    response = client.get("/api/v1/feed", params={"filter": "adoption", "limit": 20})

    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["data"]["items"]]
    assert ids == [str(adoption_post_id)]
    assert str(post_id) not in ids


def test_authenticated_feed_includes_own_private_post(
    client: TestClient,
    feed_runtime,
) -> None:
    author, token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-own@example.com",
    )
    other, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-public@example.com",
    )
    moderator, moderator_token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-moderator@example.com",
        is_moderator=True,
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    public_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=other.id,
        created_at=datetime.now(UTC) - timedelta(minutes=1),
    )
    private_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        is_public=False,
        created_at=datetime.now(UTC),
    )
    moderator_private_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=other.id,
        is_public=False,
        created_at=datetime.now(UTC) - timedelta(minutes=2),
    )

    response = client.get(
        "/api/v1/feed",
        params={"filter": "recent"},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["data"]["items"]]
    assert ids[:2] == [str(private_post), str(public_post)]

    moderator_response = client.get(
        "/api/v1/feed",
        params={"filter": "recent"},
        headers={"Authorization": f"Bearer {moderator_token}"},
    )
    assert moderator_response.status_code == 200
    moderator_ids = [item["id"] for item in moderator_response.json()["data"]["items"]]
    assert str(moderator_private_post) in moderator_ids


def test_authenticated_feed_marks_posts_liked_by_current_user(
    client: TestClient,
    feed_runtime,
) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-liked-author@example.com",
    )
    _viewer, viewer_token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-liked-viewer@example.com",
    )
    _other, other_token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-liked-other@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
    )

    like_response = client.post(
        f"/api/v1/posts/{post_id}/likes",
        headers={"Authorization": f"Bearer {viewer_token}"},
    )
    assert like_response.status_code == 200

    viewer_response = client.get(
        "/api/v1/feed",
        params={"filter": "recent"},
        headers={"Authorization": f"Bearer {viewer_token}"},
    )
    assert viewer_response.status_code == 200
    viewer_item = next(
        item for item in viewer_response.json()["data"]["items"] if item["id"] == str(post_id)
    )
    assert viewer_item["is_liked_by_me"] is True

    other_response = client.get(
        "/api/v1/feed",
        params={"filter": "recent"},
        headers={"Authorization": f"Bearer {other_token}"},
    )
    assert other_response.status_code == 200
    other_item = next(
        item for item in other_response.json()["data"]["items"] if item["id"] == str(post_id)
    )
    assert other_item["is_liked_by_me"] is False


def test_feed_popular_order_and_cursor_pagination(client: TestClient, feed_runtime) -> None:
    author, token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-popular@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    newest = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        like_count=9,
        created_at=datetime.now(UTC) - timedelta(minutes=1),
    )
    middle = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        like_count=7,
        created_at=datetime.now(UTC) - timedelta(minutes=2),
    )
    oldest = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        like_count=5,
        created_at=datetime.now(UTC) - timedelta(minutes=3),
    )

    first_page = client.get(
        "/api/v1/feed",
        params={"filter": "popular", "limit": 2},
        headers={"Authorization": f"Bearer {token}"},
    )
    assert first_page.status_code == 200
    first_payload = first_page.json()["data"]
    assert [item["id"] for item in first_payload["items"]] == [str(newest), str(middle)]
    assert first_payload["next_cursor"] is not None

    second_page = client.get(
        "/api/v1/feed",
        params={
            "filter": "popular",
            "limit": 2,
            "cursor": first_payload["next_cursor"],
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert second_page.status_code == 200
    assert [item["id"] for item in second_page.json()["data"]["items"]] == [str(oldest)]


def test_feed_popular_day_limits_to_last_24_hours(client: TestClient, feed_runtime) -> None:
    author, token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-popular-day@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    fresh = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        like_count=5,
        created_at=datetime.now(UTC) - timedelta(hours=23),
    )
    stale = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        like_count=99,
        created_at=datetime.now(UTC) - timedelta(hours=25),
    )

    response = client.get(
        "/api/v1/feed",
        params={"filter": "popular", "popular_period": "day"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["data"]["items"]]
    assert str(fresh) in ids
    assert str(stale) not in ids


def test_feed_filters_by_current_cat_status(client: TestClient, feed_runtime) -> None:
    author, token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-status@example.com",
    )
    injured_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=author.id,
        status=CatStatus.INJURED,
    )
    help_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=author.id,
        status=CatStatus.NEEDS_HELP,
    )
    injured_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=injured_cat.id,
        user_id=author.id,
    )
    help_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=help_cat.id,
        user_id=author.id,
    )

    response = client.get(
        "/api/v1/feed",
        params={"filter": "injured"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    ids = [item["id"] for item in response.json()["data"]["items"]]
    assert str(injured_post) in ids
    assert str(help_post) not in ids


def test_public_user_posts_respect_activity_privacy(client: TestClient, feed_runtime) -> None:
    author, token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="private-activity@example.com",
        allow_public_activity_view=False,
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
    )

    public_response = client.get(f"/api/v1/users/{author.id}/posts")
    assert public_response.status_code == 403
    assert public_response.json()["error"]["code"] == "ACTIVITY_PRIVATE"

    owner_response = client.get(
        f"/api/v1/users/{author.id}/posts",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert owner_response.status_code == 200
    assert [item["id"] for item in owner_response.json()["data"]["items"]] == [str(post_id)]


def test_public_user_comments_respect_activity_privacy(client: TestClient, feed_runtime) -> None:
    author, token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="private-comments@example.com",
        allow_public_activity_view=False,
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    post_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
    )
    comment_id = _create_comment(
        feed_runtime.db_session_manager,
        post_id=post_id,
        user_id=author.id,
    )

    public_response = client.get(f"/api/v1/users/{author.id}/comments")
    assert public_response.status_code == 403
    assert public_response.json()["error"]["code"] == "ACTIVITY_PRIVATE"

    owner_response = client.get(
        f"/api/v1/users/{author.id}/comments",
        headers={"Authorization": f"Bearer {token}"},
    )
    assert owner_response.status_code == 200
    items = owner_response.json()["data"]["items"]
    assert [item["id"] for item in items] == [str(comment_id)]
    assert items[0]["post_id"] == str(post_id)


def test_public_user_comments_include_lost_pet_and_adoption_activity(
    client: TestClient,
    feed_runtime,
) -> None:
    author, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="public-pet-comments@example.com",
        allow_public_activity_view=True,
    )
    lost_pet_id = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=author.id,
    )
    adoption_post_id = _create_adoption_post(
        feed_runtime.db_session_manager,
        user_id=author.id,
    )
    lost_comment_id = _create_comment(
        feed_runtime.db_session_manager,
        user_id=author.id,
        lost_pet_id=lost_pet_id,
    )
    adoption_comment_id = _create_comment(
        feed_runtime.db_session_manager,
        user_id=author.id,
        adoption_post_id=adoption_post_id,
    )

    response = client.get(f"/api/v1/users/{author.id}/comments")

    assert response.status_code == 200
    items = response.json()["data"]["items"]
    ids = {item["id"] for item in items}
    assert ids == {str(lost_comment_id), str(adoption_comment_id)}


def test_feed_nearby_query_and_visibility(client: TestClient, feed_runtime) -> None:
    author, token = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-nearby@example.com",
    )
    other, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="feed-nearby-private@example.com",
    )
    cat = _create_cat(feed_runtime.db_session_manager, creator_id=author.id)
    near_one = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        latitude=41.3002,
        longitude=69.2502,
        created_at=datetime.now(UTC) - timedelta(minutes=2),
    )
    near_two = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        latitude=41.3001,
        longitude=69.2501,
        created_at=datetime.now(UTC) - timedelta(minutes=1),
    )
    far_post = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=author.id,
        latitude=41.35,
        longitude=69.35,
    )
    private_other = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=other.id,
        is_public=False,
        latitude=41.30015,
        longitude=69.25015,
    )

    response = client.get(
        "/api/v1/feed",
        params={
            "filter": "nearby",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
        headers={"Authorization": f"Bearer {token}"},
    )
    assert response.status_code == 200
    items = response.json()["data"]["items"]
    ids = [item["id"] for item in items]
    assert ids[0] == str(near_two)
    assert ids[1] == str(near_one)
    assert str(far_post) not in ids
    assert str(private_other) not in ids


def test_map_nearby_and_bbox_response_shape(client: TestClient, feed_runtime) -> None:
    user, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="map-user@example.com",
    )
    inside = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.3001, 69.2501),
    )
    outside = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.6, 69.9),
    )
    stale = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.3002, 69.2502),
    )
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=inside.id,
        user_id=user.id,
        created_at=datetime.now(UTC) - timedelta(hours=1),
    )
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=stale.id,
        user_id=user.id,
        created_at=datetime.now(UTC) - timedelta(days=11),
    )

    nearby = client.get(
        "/api/v1/cats",
        params={
            "filter": "nearby",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
    )
    assert nearby.status_code == 200
    payload = nearby.json()["data"]
    assert payload["items"][0]["id"] == str(inside.id)
    assert payload["items"][0]["canonical_location"] is not None
    assert payload["items"][0]["distance_meters"] is not None
    assert str(outside.id) not in {item["id"] for item in payload["items"]}
    assert str(stale.id) not in {item["id"] for item in payload["items"]}

    bbox = client.get(
        "/api/v1/cats",
        params={
            "bbox": "69.0,41.0,69.5,41.5",
            "limit": 20,
        },
    )
    assert bbox.status_code == 200
    bbox_ids = [item["id"] for item in bbox.json()["data"]["items"]]
    assert str(inside.id) in bbox_ids
    assert str(outside.id) not in bbox_ids


def test_map_bbox_kind_filter_includes_edges_and_excludes_hidden_content(
    client: TestClient,
    feed_runtime,
) -> None:
    user, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="map-bbox-user@example.com",
    )
    normal_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.2000, 69.1000),
    )
    latest_needs_help_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.2500, 69.2000),
    )
    latest_observation_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.2600, 69.2100),
    )
    no_public_post_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.2700, 69.2200),
    )
    outside_cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.5000, 69.5000),
    )
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=normal_cat.id,
        user_id=user.id,
        latitude=41.2000,
        longitude=69.1000,
        kind=PostKind.OBSERVATION,
    )
    kind_transition_start = datetime.now(UTC) - timedelta(minutes=2)
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=latest_needs_help_cat.id,
        user_id=user.id,
        latitude=41.2500,
        longitude=69.2000,
        kind=PostKind.OBSERVATION,
        created_at=kind_transition_start,
    )
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=latest_needs_help_cat.id,
        user_id=user.id,
        latitude=41.2500,
        longitude=69.2000,
        kind=PostKind.NEEDS_HELP,
        created_at=kind_transition_start + timedelta(seconds=1),
    )
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=latest_observation_cat.id,
        user_id=user.id,
        latitude=41.2600,
        longitude=69.2100,
        kind=PostKind.NEEDS_HELP,
        created_at=kind_transition_start,
    )
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=latest_observation_cat.id,
        user_id=user.id,
        latitude=41.2600,
        longitude=69.2100,
        kind=PostKind.OBSERVATION,
        created_at=kind_transition_start + timedelta(seconds=1),
    )
    _create_post(
        feed_runtime.db_session_manager,
        cat_id=outside_cat.id,
        user_id=user.id,
        latitude=41.5000,
        longitude=69.5000,
        kind=PostKind.OBSERVATION,
    )

    bbox = "69.1,41.2,69.3,41.4"
    observation_response = client.get(
        "/api/v1/cats",
        params={"filter": "recently_added", "kind": "observation", "bbox": bbox},
    )
    needs_help_response = client.get(
        "/api/v1/cats",
        params={"filter": "recently_added", "kind": "needs_help", "bbox": bbox},
    )

    assert observation_response.status_code == 200
    assert needs_help_response.status_code == 200
    observation_ids = {item["id"] for item in observation_response.json()["data"]["items"]}
    needs_help_ids = {item["id"] for item in needs_help_response.json()["data"]["items"]}
    assert str(normal_cat.id) in observation_ids
    assert str(latest_needs_help_cat.id) not in observation_ids
    assert str(latest_needs_help_cat.id) in needs_help_ids
    assert str(latest_observation_cat.id) in observation_ids
    assert str(latest_observation_cat.id) not in needs_help_ids
    assert str(no_public_post_cat.id) not in observation_ids | needs_help_ids
    assert str(outside_cat.id) not in observation_ids | needs_help_ids

    observation_items = {item["id"]: item for item in observation_response.json()["data"]["items"]}
    needs_help_items = {item["id"]: item for item in needs_help_response.json()["data"]["items"]}
    assert observation_items[str(latest_observation_cat.id)]["latest_post_kind"] == "observation"
    assert needs_help_items[str(latest_needs_help_cat.id)]["latest_post_kind"] == "needs_help"

    inside_lost_pet = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=user.id,
        pet_name="Edge pet",
        latitude=41.2,
        longitude=69.1,
    )
    outside_lost_pet = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=user.id,
        pet_name="Outside pet",
        latitude=41.5,
        longitude=69.5,
    )
    hidden_lost_pet = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=user.id,
        pet_name="Hidden pet",
        latitude=41.25,
        longitude=69.2,
        is_public=False,
    )
    deleted_lost_pet = _create_lost_pet(
        feed_runtime.db_session_manager,
        user_id=user.id,
        pet_name="Deleted pet",
        latitude=41.25,
        longitude=69.2,
        deleted_at=datetime.now(UTC),
    )
    lost_response = client.get(
        "/api/v1/lost-pets/map",
        params={"bbox": bbox},
    )
    assert lost_response.status_code == 200
    lost_items = lost_response.json()["data"]["items"]
    lost_ids = {item["id"] for item in lost_items}
    assert str(inside_lost_pet) in lost_ids
    assert str(outside_lost_pet) not in lost_ids
    assert str(hidden_lost_pet) not in lost_ids
    assert str(deleted_lost_pet) not in lost_ids
    assert "owner_phone_number" not in lost_items[0]
    assert "photo_urls" not in lost_items[0]


def test_map_bbox_latest_kind_uses_post_id_tiebreaker(
    client: TestClient,
    feed_runtime,
) -> None:
    user, _ = _create_user_with_token(
        feed_runtime.db_session_manager,
        feed_runtime.token_service,
        email="map-bbox-tiebreak@example.com",
    )
    cat = _create_cat(
        feed_runtime.db_session_manager,
        creator_id=user.id,
        canonical_location=(41.2800, 69.2300),
    )
    created_at = datetime.now(UTC) - timedelta(minutes=1)
    observation_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
        latitude=41.2800,
        longitude=69.2300,
        kind=PostKind.OBSERVATION,
        created_at=created_at,
    )
    needs_help_id = _create_post(
        feed_runtime.db_session_manager,
        cat_id=cat.id,
        user_id=user.id,
        latitude=41.2800,
        longitude=69.2300,
        kind=PostKind.NEEDS_HELP,
        created_at=created_at,
    )
    expected_kind = "needs_help" if needs_help_id > observation_id else "observation"
    other_kind = "observation" if expected_kind == "needs_help" else "needs_help"

    latest_response = client.get(
        "/api/v1/cats",
        params={
            "filter": "recently_added",
            "kind": expected_kind,
            "bbox": "69.2,41.2,69.3,41.4",
        },
    )
    other_response = client.get(
        "/api/v1/cats",
        params={
            "filter": "recently_added",
            "kind": other_kind,
            "bbox": "69.2,41.2,69.3,41.4",
        },
    )

    assert latest_response.status_code == 200
    assert other_response.status_code == 200
    latest_items = latest_response.json()["data"]["items"]
    other_items = other_response.json()["data"]["items"]
    latest_item = next(item for item in latest_items if item["id"] == str(cat.id))
    assert latest_item["latest_post_kind"] == expected_kind
    assert str(cat.id) not in {item["id"] for item in other_items}


def test_places_endpoint_filters_categories_and_returns_phone(
    client: TestClient,
    feed_runtime,
) -> None:
    vet = _create_place(
        feed_runtime.db_session_manager,
        name="Neighborhood Vet",
        category=PlaceCategory.VETERINARY,
        latitude=41.3001,
        longitude=69.2501,
        phone="+998 90 123 45 67",
        phone_2="+998 90 000 00 00",
        instagram="https://www.instagram.com/neighborhood.vet/",
        telegram="https://t.me/neighborhood_vet",
        days_off="sun",
        description="Open for routine checkups.",
        source_id="node/100",
    )
    shelter = _create_place(
        feed_runtime.db_session_manager,
        name="Cat Shelter",
        category=PlaceCategory.SHELTER,
        latitude=41.3002,
        longitude=69.2502,
        phone="+998 90 765 43 21",
        source_id="node/101",
    )
    shop = _create_place(
        feed_runtime.db_session_manager,
        name="Pet Shop",
        category=PlaceCategory.PET_SHOP,
        latitude=41.3003,
        longitude=69.2503,
        source_id="node/102",
    )

    vets_response = client.get(
        "/api/v1/places",
        params={
            "category": "veterinary",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
    )
    assert vets_response.status_code == 200
    vets_payload = vets_response.json()["data"]
    assert [item["id"] for item in vets_payload["items"]] == [str(vet)]
    assert vets_payload["items"][0]["category"] == "veterinary"
    assert vets_payload["items"][0]["categories"] == ["veterinary"]
    assert vets_payload["items"][0]["phone"] == "+998 90 123 45 67"
    assert vets_payload["items"][0]["phone_2"] == "+998 90 000 00 00"
    assert vets_payload["items"][0]["instagram"] == "https://www.instagram.com/neighborhood.vet/"
    assert vets_payload["items"][0]["telegram"] == "https://t.me/neighborhood_vet"
    assert vets_payload["items"][0]["days_off"] == "sun"
    assert vets_payload["items"][0]["description"] == "Open for routine checkups."
    assert vets_payload["items"][0]["distance_meters"] is not None

    shelters_response = client.get(
        "/api/v1/places",
        params={
            "category": "shelter",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
    )
    assert shelters_response.status_code == 200
    shelter_ids = [item["id"] for item in shelters_response.json()["data"]["items"]]
    assert str(shelter) in shelter_ids
    assert str(vet) not in shelter_ids
    assert str(shop) not in shelter_ids


def test_places_endpoint_returns_multi_category_place_once(
    client: TestClient,
    feed_runtime,
) -> None:
    combo = _create_place(
        feed_runtime.db_session_manager,
        name="Pet Store Vet",
        category=PlaceCategory.VETERINARY,
        categories=[PlaceCategory.VETERINARY, PlaceCategory.PET_SHOP],
        latitude=41.3001,
        longitude=69.2501,
        source_id="node/200",
    )

    vets_response = client.get(
        "/api/v1/places",
        params={
            "category": "veterinary",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
    )
    shops_response = client.get(
        "/api/v1/places",
        params={
            "category": "pet_shop",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
    )

    assert vets_response.status_code == 200
    assert shops_response.status_code == 200
    vet_items = vets_response.json()["data"]["items"]
    shop_items = shops_response.json()["data"]["items"]
    assert [item["id"] for item in vet_items] == [str(combo)]
    assert [item["id"] for item in shop_items] == [str(combo)]
    assert vet_items[0]["category"] == "veterinary"
    assert vet_items[0]["categories"] == ["veterinary", "pet_shop"]


def test_places_endpoint_falls_back_to_legacy_category_without_links(
    client: TestClient,
    feed_runtime,
) -> None:
    legacy = _create_place(
        feed_runtime.db_session_manager,
        name="Legacy Pet Shop",
        category=PlaceCategory.PET_SHOP,
        categories=None,
        latitude=41.3001,
        longitude=69.2501,
        source_id="node/201",
    )

    response = client.get(
        "/api/v1/places",
        params={
            "category": "pet_shop",
            "lat": 41.3,
            "lon": 69.25,
            "radius_meters": 500,
        },
    )

    assert response.status_code == 200
    items = response.json()["data"]["items"]
    assert [item["id"] for item in items] == [str(legacy)]
    assert items[0]["category"] == "pet_shop"
    assert items[0]["categories"] == ["pet_shop"]


def test_places_map_payload_is_compact_and_detail_is_loaded_separately(
    client: TestClient,
    feed_runtime,
) -> None:
    place_id = _create_place(
        feed_runtime.db_session_manager,
        name="Compact Vet",
        category=PlaceCategory.VETERINARY,
        latitude=41.3,
        longitude=69.25,
        phone="+998 90 123 45 67",
        description="Long detail that should not be sent with map markers.",
        source_id="node/compact",
    )

    map_response = client.get(
        "/api/v1/places",
        params={
            "category": "veterinary",
            "bbox": "69.2,41.2,69.3,41.4",
            "map_only": "true",
        },
    )
    assert map_response.status_code == 200
    map_item = map_response.json()["data"]["items"][0]
    assert map_item["id"] == str(place_id)
    assert "phone" not in map_item
    assert "description" not in map_item

    detail_response = client.get(f"/api/v1/places/{place_id}")
    assert detail_response.status_code == 200
    detail = detail_response.json()["data"]
    assert detail["phone"] == "+998 90 123 45 67"
    assert detail["description"] == "Long detail that should not be sent with map markers."
