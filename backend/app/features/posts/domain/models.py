from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID

from app.features.cats.domain.models import CatStatus, GeoPoint


class PostSortOrder(StrEnum):
    LATEST = "latest"
    OLDEST = "oldest"


class PostHistoryAction(StrEnum):
    EDITED = "edited"
    DELETED = "deleted"


@dataclass(slots=True)
class PostAuthorSummary:
    id: UUID | None
    name: str | None
    avatar_url: str | None


@dataclass(slots=True)
class PostCatSummary:
    id: UUID
    name: str | None
    cover_photo_url: str | None
    status: CatStatus
    is_active: bool
    merged_into: UUID | None
    deleted_at: datetime | None


@dataclass(slots=True)
class PostRecord:
    id: UUID
    cat_id: UUID
    user_id: UUID | None
    photo_url: str
    thumb_url: str | None
    photo_urls: list[str]
    description: str | None
    location: GeoPoint | None
    status: CatStatus | None
    is_public: bool
    like_count: int
    comment_count: int
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    author: PostAuthorSummary | None
    cat: PostCatSummary
    is_liked_by_me: bool = False
    is_edited: bool = False


@dataclass(slots=True)
class PostDetailRecord(PostRecord):
    pass


@dataclass(slots=True)
class PostPage:
    items: list[PostRecord]
    next_cursor: str | None
    limit: int


@dataclass(slots=True)
class CatObservationStats:
    first_seen_at: datetime | None
    last_seen_at: datetime | None
    total_observations: int
    total_contributors: int
    total_likes: int


@dataclass(slots=True)
class PostHistoryRecord:
    id: UUID
    post_id: UUID
    actor_id: UUID | None
    actor_name: str | None
    action: PostHistoryAction
    before: dict[str, object]
    after: dict[str, object]
    created_at: datetime


def post_history_snapshot(post: PostDetailRecord) -> dict[str, object]:
    """Return the stable, moderator-visible subset of a post used for auditing."""
    location = post.location
    return post_history_snapshot_from_values(
        description=post.description,
        status=post.status.value if post.status is not None else None,
        location_latitude=location.latitude if location is not None else None,
        location_longitude=location.longitude if location is not None else None,
        is_public=post.is_public,
        photo_urls=post.photo_urls,
    )


def post_history_snapshot_from_values(
    *,
    description: str | None,
    status: str | None,
    location_latitude: float | None,
    location_longitude: float | None,
    is_public: bool,
    photo_urls: list[str],
) -> dict[str, object]:
    return {
        "description": description,
        "status": status,
        "location": (
            {"latitude": location_latitude, "longitude": location_longitude}
            if location_latitude is not None and location_longitude is not None
            else None
        ),
        "is_public": is_public,
        "photo_urls": list(photo_urls),
    }
