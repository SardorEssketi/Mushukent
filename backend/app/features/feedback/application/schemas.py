from __future__ import annotations

from datetime import datetime
from typing import Annotated
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, StringConstraints, field_validator

from app.features.feedback.domain.models import (
    MESSAGE_MAX_LENGTH,
    MESSAGE_MIN_LENGTH,
    FeedbackCategory,
    FeedbackPlatform,
    FeedbackRecord,
)

AppVersion = Annotated[str, StringConstraints(strip_whitespace=True, max_length=32)]


class FeedbackCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    category: FeedbackCategory
    # Raw cap guards against huge payloads; the real limit is applied after trimming.
    message: str = Field(max_length=MESSAGE_MAX_LENGTH * 2)
    platform: FeedbackPlatform | None = None
    app_version: AppVersion | None = None

    @field_validator("message")
    @classmethod
    def _validate_message(cls, value: str) -> str:
        trimmed = value.strip()
        if not MESSAGE_MIN_LENGTH <= len(trimmed) <= MESSAGE_MAX_LENGTH:
            raise ValueError(
                f"Message must be {MESSAGE_MIN_LENGTH}-{MESSAGE_MAX_LENGTH} characters."
            )
        return trimmed

    @field_validator("app_version")
    @classmethod
    def _blank_version_is_none(cls, value: str | None) -> str | None:
        return value or None


class FeedbackResponse(BaseModel):
    id: UUID
    category: FeedbackCategory
    created_at: datetime


def to_feedback_response(record: FeedbackRecord) -> FeedbackResponse:
    return FeedbackResponse(
        id=record.id,
        category=record.category,
        created_at=record.created_at,
    )
