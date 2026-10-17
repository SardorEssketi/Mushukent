from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Protocol

from structlog import get_logger

from app.core.security import api_error
from app.features.auth.domain.models import AuthUser
from app.features.feedback.application.schemas import (
    FeedbackCreate,
    FeedbackResponse,
    to_feedback_response,
)
from app.features.feedback.domain.models import FeedbackNotification
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)

RATE_LIMIT_WINDOW = timedelta(hours=1)


class FeedbackNotifier(Protocol):
    def notify(self, notification: FeedbackNotification) -> bool: ...


class FeedbackService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory,
        notifier: FeedbackNotifier,
        max_per_hour: int,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.notifier = notifier
        self.max_per_hour = max_per_hour

    def submit(
        self, user: AuthUser, payload: FeedbackCreate
    ) -> tuple[FeedbackResponse, FeedbackNotification]:
        """Store feedback and return it with the notification to dispatch.

        Dispatch is separate (`notify`) so it runs after the transaction commits
        and a Telegram outage can never roll back or delay the stored record.
        """
        now = datetime.now(UTC)
        since = now - RATE_LIMIT_WINDOW
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            repository.lock_user(user.id)
            if repository.count_since(user_id=user.id, since=since) >= self.max_per_hour:
                oldest = repository.oldest_since(user_id=user.id, since=since)
                retry_after = (
                    max(1, int((oldest + RATE_LIMIT_WINDOW - now).total_seconds()))
                    if oldest is not None
                    else int(RATE_LIMIT_WINDOW.total_seconds())
                )
                error = api_error(
                    429,
                    "FEEDBACK_RATE_LIMITED",
                    "You have sent a lot of feedback recently. Please try again later.",
                )
                error.headers = {"Retry-After": str(retry_after)}
                raise error
            record = repository.create(
                user_id=user.id,
                category=payload.category,
                message=payload.message,
                platform=payload.platform,
                app_version=payload.app_version,
            )
            logger.info(
                "feedback_created",
                feedback_id=str(record.id),
                user_id=str(user.id),
                category=record.category.value,
            )
        notification = FeedbackNotification(
            feedback_id=record.id,
            category=record.category,
            message=record.message,
            user_label=user.name or str(user.id),
            platform=record.platform,
            app_version=record.app_version,
            created_at=record.created_at,
        )
        return to_feedback_response(record), notification

    def notify(self, notification: FeedbackNotification) -> None:
        self.notifier.notify(notification)
