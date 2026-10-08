from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator


class AlertPoint(BaseModel):
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class PreferencePatch(BaseModel):
    model_config = ConfigDict(extra="forbid")

    push_comments: bool | None = None
    push_replies: bool | None = None
    push_followups: bool | None = None
    nearby_enabled: bool | None = None
    inactivity_enabled: bool | None = None
    alert_location: AlertPoint | None = None

    @model_validator(mode="after")
    def reject_explicit_nulls(self) -> PreferencePatch:
        for field in self.model_fields_set:
            if getattr(self, field) is None:
                raise ValueError(
                    f"{field} cannot be null; disable nearby alerts to remove the point."
                )
        return self


class PreferenceResponse(BaseModel):
    push_comments: bool
    push_replies: bool
    push_followups: bool
    nearby_enabled: bool
    inactivity_enabled: bool
    alert_location: AlertPoint | None
    push_available: bool


class DeviceTokenRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    platform: str = Field(pattern="^android$")
    token: str = Field(min_length=20, max_length=4096)
    previous_token: str | None = Field(default=None, min_length=20, max_length=4096)


class NotificationItem(BaseModel):
    id: UUID
    kind: str
    actor_name: str | None
    target_kind: str
    target_id: UUID
    comment_id: UUID | None
    created_at: datetime
    read_at: datetime | None


class NotificationPage(BaseModel):
    items: list[NotificationItem]
    next_cursor: str | None
    limit: int


class UnreadCount(BaseModel):
    count: int


class MarkAllResult(BaseModel):
    marked: int
