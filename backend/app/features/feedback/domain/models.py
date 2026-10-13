from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID

MESSAGE_MIN_LENGTH = 10
MESSAGE_MAX_LENGTH = 2000


class FeedbackCategory(StrEnum):
    BUG = "bug"
    SUGGESTION = "suggestion"
    OTHER = "other"


class FeedbackPlatform(StrEnum):
    WEB = "web"
    ANDROID = "android"


@dataclass(slots=True)
class FeedbackRecord:
    id: UUID
    user_id: UUID
    category: FeedbackCategory
    message: str
    platform: FeedbackPlatform | None
    app_version: str | None
    created_at: datetime


@dataclass(slots=True)
class FeedbackNotification:
    """Everything the developer notification needs; carries no credentials."""

    feedback_id: UUID
    category: FeedbackCategory
    message: str
    user_label: str
    platform: FeedbackPlatform | None
    app_version: str | None
    created_at: datetime
