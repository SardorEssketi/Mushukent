from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.features.leaderboards.domain.models import (
    LeaderboardPeriod,
    LeaderboardRecord,
)


class LeaderboardQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    period: LeaderboardPeriod = LeaderboardPeriod.MONTH
    limit: int = Field(default=20, ge=1, le=100)


class LeaderboardUser(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None
    avatar_url: str | None
    registered_at: datetime


class LeaderboardEntry(BaseModel):
    rank: int
    user: LeaderboardUser
    observation_count: int
    like_count: int


def to_leaderboard_entries(page: list[LeaderboardRecord]) -> list[LeaderboardEntry]:
    return [
        LeaderboardEntry(
            rank=item.rank,
            user=LeaderboardUser(
                id=item.user.id,
                name=item.user.name,
                avatar_url=item.user.avatar_url,
                registered_at=item.user.registered_at,
            ),
            observation_count=item.observation_count,
            like_count=item.like_count,
        )
        for item in page
    ]


LeaderboardResponse = list[LeaderboardEntry]
