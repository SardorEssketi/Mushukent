from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field

from app.features.leaderboards.domain.models import (
    LeaderboardPeriod,
    LeaderboardRecord,
)
from app.features.users.application.schemas import UserPublic


class LeaderboardQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    period: LeaderboardPeriod = LeaderboardPeriod.WEEK
    limit: int = Field(default=20, ge=1, le=100)


class LeaderboardEntry(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    rank: int
    user: UserPublic
    score: int


def to_leaderboard_entries(page: list[LeaderboardRecord]) -> list[LeaderboardEntry]:
    return [
        LeaderboardEntry(
            rank=item.rank,
            user=UserPublic(
                id=item.user.id,
                name=item.user.name,
                avatar_url=item.user.avatar_url,
                registered_at=item.user.registered_at,
                observation_count=item.user.observation_count,
            ),
            score=item.score,
        )
        for item in page
    ]


LeaderboardResponse = list[LeaderboardEntry]
