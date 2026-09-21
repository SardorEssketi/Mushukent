from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from app.features.leaderboards.domain.models import (
    LeaderboardPeriod,
    LeaderboardRecord,
    LeaderboardType,
)


@dataclass(slots=True)
class LeaderboardPage:
    items: list[LeaderboardRecord]
    limit: int


class LeaderboardRepository(Protocol):
    def list_leaderboard(
        self,
        leaderboard_type: LeaderboardType,
        *,
        period: LeaderboardPeriod,
        limit: int,
    ) -> LeaderboardPage: ...
