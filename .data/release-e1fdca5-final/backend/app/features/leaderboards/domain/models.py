from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class LeaderboardType(StrEnum):
    MOST_ACTIVE = "most_active"
    MOST_POPULAR = "most_popular"
    TOP_HELPERS = "top_helpers"


class LeaderboardPeriod(StrEnum):
    DAY = "day"
    WEEK = "week"
    MONTH = "month"
    ALL = "all"


@dataclass(slots=True)
class LeaderboardUserSummary:
    id: UUID
    name: str | None
    avatar_url: str | None
    registered_at: datetime
    observation_count: int = 0


@dataclass(slots=True)
class LeaderboardRecord:
    rank: int
    user: LeaderboardUserSummary
    score: int
