from __future__ import annotations

from datetime import datetime
from uuid import UUID, uuid4

from sqlalchemy import func, select, text
from sqlalchemy.orm import Session

from app.features.feedback.domain.models import (
    FeedbackCategory,
    FeedbackPlatform,
    FeedbackRecord,
)
from app.infrastructure.db.models import schema


class SqlAlchemyFeedbackRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def lock_user(self, user_id: UUID) -> None:
        """Serialise a user's submissions so the hourly cap cannot be raced."""
        self.session.execute(
            text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
            {"key": f"feedback:{user_id}"},
        )

    def count_since(self, *, user_id: UUID, since: datetime) -> int:
        return int(
            self.session.scalar(
                select(func.count())
                .select_from(schema.Feedback)
                .where(schema.Feedback.user_id == user_id, schema.Feedback.created_at > since)
            )
            or 0
        )

    def oldest_since(self, *, user_id: UUID, since: datetime) -> datetime | None:
        return self.session.scalar(
            select(func.min(schema.Feedback.created_at)).where(
                schema.Feedback.user_id == user_id, schema.Feedback.created_at > since
            )
        )

    def create(
        self,
        *,
        user_id: UUID,
        category: FeedbackCategory,
        message: str,
        platform: FeedbackPlatform | None,
        app_version: str | None,
    ) -> FeedbackRecord:
        model = schema.Feedback(
            id=uuid4(),
            user_id=user_id,
            category=category.value,
            message=message,
            platform=platform.value if platform else None,
            app_version=app_version,
        )
        self.session.add(model)
        self.session.flush()
        self.session.refresh(model)
        return FeedbackRecord(
            id=model.id,
            user_id=user_id,
            category=category,
            message=message,
            platform=platform,
            app_version=app_version,
            created_at=model.created_at,
        )
