from __future__ import annotations

from typing import Protocol

from app.features.leaderboards.application.schemas import (
    LeaderboardEntry,
    LeaderboardQuery,
    to_leaderboard_entries,
)
from app.features.leaderboards.domain.models import LeaderboardType
from app.features.leaderboards.domain.repositories import LeaderboardRepository
from app.infrastructure.db.session import DatabaseSessionManager


class LeaderboardRepositoryFactory(Protocol):
    def __call__(self, session) -> LeaderboardRepository: ...


class LeaderboardService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: LeaderboardRepositoryFactory,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory

    def get_leaderboard(
        self,
        leaderboard_type: LeaderboardType,
        query: LeaderboardQuery,
    ) -> list[LeaderboardEntry]:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            page = repository.list_leaderboard(
                leaderboard_type,
                period=query.period,
                limit=query.limit,
            )
            return to_leaderboard_entries(page.items)
