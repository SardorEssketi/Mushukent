from __future__ import annotations

from uuid import UUID

from sqlalchemy import func, select

from app.features.auth.infrastructure.repositories import SqlAlchemyAuthUserRepository
from app.features.users.domain.repositories import UserProfileRepository
from app.infrastructure.db.models import schema


class SqlAlchemyUserProfileRepository(SqlAlchemyAuthUserRepository, UserProfileRepository):
    def count_observations(self, user_id: UUID) -> int:
        statement = select(func.count(schema.Post.id)).where(
            schema.Post.user_id == user_id,
            schema.Post.deleted_at.is_(None),
        )
        return int(self.session.scalar(statement) or 0)

    def count_likes_received(self, user_id: UUID) -> int:
        statement = (
            select(func.count(schema.Like.id))
            .join(schema.Post, schema.Like.post_id == schema.Post.id)
            .where(
                schema.Post.user_id == user_id,
                schema.Post.deleted_at.is_(None),
            )
        )
        return int(self.session.scalar(statement) or 0)

    def count_comments(self, user_id: UUID) -> int:
        statement = select(func.count(schema.Comment.id)).where(
            schema.Comment.user_id == user_id,
            schema.Comment.deleted_at.is_(None),
        )
        return int(self.session.scalar(statement) or 0)
