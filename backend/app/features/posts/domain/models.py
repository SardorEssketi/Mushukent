from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID

from app.features.cats.domain.models import CatStatus, GeoPoint


class PostSortOrder(StrEnum):
    LATEST = "latest"
    OLDEST = "oldest"


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


@dataclass(slots=True)
class PostDetailRecord(PostRecord):
    is_liked_by_me: bool = False


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
