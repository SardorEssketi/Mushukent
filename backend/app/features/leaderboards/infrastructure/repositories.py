from __future__ import annotations

from collections.abc import Sequence
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.features.cats.domain.models import CatStatus
from app.features.leaderboards.domain.models import (
    LeaderboardPeriod,
    LeaderboardRecord,
    LeaderboardType,
    LeaderboardUserSummary,
)
from app.features.leaderboards.domain.repositories import LeaderboardPage, LeaderboardRepository
from app.infrastructure.db.models import schema


class SqlAlchemyLeaderboardRepository(LeaderboardRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def list_leaderboard(
        self,
        leaderboard_type: LeaderboardType,
        *,
        period: LeaderboardPeriod,
        limit: int,
    ) -> LeaderboardPage:
        visible_posts = self._visible_posts_statement(cutoff=self._cutoff_for_period(period))

        if leaderboard_type == LeaderboardType.MOST_ACTIVE:
            score_expr = func.count(visible_posts.c.post_id).label("score")
        elif leaderboard_type == LeaderboardType.MOST_POPULAR:
            score_expr = func.coalesce(func.sum(visible_posts.c.like_count), 0).label("score")
        else:
            score_expr = (
                func.count(visible_posts.c.post_id)
                .filter(visible_posts.c.status.in_([CatStatus.NEEDS_HELP, CatStatus.INJURED]))
                .label("score")
            )

        statement = (
            select(
                schema.User.id.label("user_id"),
                schema.User.name.label("user_name"),
                schema.User.avatar_url.label("avatar_url"),
                schema.User.registered_at.label("registered_at"),
                score_expr,
            )
            .select_from(visible_posts)
            .join(schema.User, schema.User.id == visible_posts.c.user_id)
            .group_by(
                schema.User.id,
                schema.User.name,
                schema.User.avatar_url,
                schema.User.registered_at,
            )
            .order_by(score_expr.desc(), schema.User.id.asc())
            .limit(limit)
        )
        rows = self.session.execute(statement).mappings().all()
        return LeaderboardPage(items=self._rows_to_records(rows), limit=limit)

    def _visible_posts_statement(self, *, cutoff):
        statement = (
            select(
                schema.Post.id.label("post_id"),
                schema.Post.user_id.label("user_id"),
                schema.Post.like_count.label("like_count"),
                schema.Post.status.label("status"),
                schema.Post.created_at.label("created_at"),
            )
            .select_from(schema.Post)
            .join(schema.Cat, schema.Post.cat_id == schema.Cat.id)
            .where(
                schema.Post.deleted_at.is_(None),
                schema.Post.is_public.is_(True),
                schema.Cat.deleted_at.is_(None),
                schema.Cat.is_active.is_(True),
                schema.Cat.merged_into.is_(None),
            )
        )
        if cutoff is not None:
            statement = statement.where(schema.Post.created_at >= cutoff)
        return statement.subquery()

    def _cutoff_for_period(self, period: LeaderboardPeriod):
        now = datetime.now(UTC)
        if period == LeaderboardPeriod.DAY:
            return now - timedelta(days=1)
        if period == LeaderboardPeriod.WEEK:
            return now - timedelta(days=7)
        if period == LeaderboardPeriod.MONTH:
            return now - timedelta(days=30)
        return None

    def _rows_to_records(self, rows: Sequence[Any]) -> list[LeaderboardRecord]:
        items: list[LeaderboardRecord] = []
        for index, row in enumerate(rows, start=1):
            score = int(row["score"] or 0)
            items.append(
                LeaderboardRecord(
                    rank=index,
                    user=LeaderboardUserSummary(
                        id=row["user_id"],
                        name=row["user_name"],
                        avatar_url=row["avatar_url"],
                        registered_at=row["registered_at"],
                        observation_count=score,
                    ),
                    score=score,
                )
            )
        return items
