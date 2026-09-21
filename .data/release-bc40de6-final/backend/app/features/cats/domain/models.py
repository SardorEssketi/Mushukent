from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class CatStatus(StrEnum):
    HEALTHY = "healthy"
    INJURED = "injured"
    NEEDS_HELP = "needs_help"
    ADOPTED = "adopted"
    UNKNOWN = "unknown"
    FEED = "feed"


class CatListFilter(StrEnum):
    NEARBY = "nearby"
    RECENTLY_SEEN = "recently_seen"
    NEEDS_HELP = "needs_help"
    RECENTLY_ADDED = "recently_added"


class ObservationSortOrder(StrEnum):
    LATEST = "latest"
    OLDEST = "oldest"


@dataclass(slots=True)
class GeoPoint:
    latitude: float
    longitude: float


@dataclass(slots=True)
class CatSummary:
    id: UUID
    name: str | None
    status: CatStatus
    cover_photo_url: str | None
    canonical_location: GeoPoint | None
    last_seen_at: datetime | None
    total_observations: int = 0
    distance_meters: float | None = None
    created_at: datetime | None = None


@dataclass(slots=True)
class CatRecord(CatSummary):
    approximate_age_smallyears: int | None = None
    first_seen_at: datetime | None = None
    total_contributors: int = 0
    total_likes: int = 0
    created_at: datetime | None = None
    updated_at: datetime | None = None
    created_by: UUID | None = None
    is_active: bool = True
    merged_into: UUID | None = None
    deleted_at: datetime | None = None


@dataclass(slots=True)
class ObservationAuthor:
    id: UUID | None
    name: str | None
    avatar_url: str | None


@dataclass(slots=True)
class PostListItem:
    id: UUID
    cat: CatSummary
    author: ObservationAuthor | None
    photo_url: str
    thumb_url: str | None
    description: str | None
    location: GeoPoint | None
    created_at: datetime
    like_count: int = 0
    comment_count: int = 0


@dataclass(slots=True)
class CatDetailRecord(CatRecord):
    observation_history: list[PostListItem] = field(default_factory=list)
