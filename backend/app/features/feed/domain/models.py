from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class FeedFilter(StrEnum):
    RECENT = "recent"
    POPULAR = "popular"
    NEARBY = "nearby"
    INJURED = "injured"
    NEEDS_HELP = "needs_help"
    ADOPTION = "adoption"


class FeedPopularPeriod(StrEnum):
    DAY = "day"
    MONTH = "month"
    ALL = "all"


class FeedItemType(StrEnum):
    OBSERVATION = "observation"
    LOST_PET = "lost_pet"
    ADOPTION = "adoption"


FEED_ITEM_TYPE_RANK: dict[FeedItemType, int] = {
    FeedItemType.OBSERVATION: 3,
    FeedItemType.LOST_PET: 2,
    FeedItemType.ADOPTION: 1,
}


@dataclass(frozen=True, slots=True)
class FeedCursorPosition:
    created_at: datetime
    item_type: FeedItemType
    item_id: UUID
    distance_meters: float | None = None


@dataclass(frozen=True, slots=True)
class FeedItemKey:
    created_at: datetime
    item_type: FeedItemType
    item_id: UUID
    distance_meters: float | None = None


@dataclass(slots=True)
class FeedKeyPage:
    items: list[FeedItemKey]
    has_next: bool
