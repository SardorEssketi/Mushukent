from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class ReportTargetType(StrEnum):
    POST = "post"
    COMMENT = "comment"
    USER = "user"
    CAT = "cat"
    LOST_PET = "lost_pet"
    ADOPTION_POST = "adoption_post"


class ReportStatus(StrEnum):
    OPEN = "open"
    RESOLVED = "resolved"
    DISMISSED = "dismissed"


class ReportAction(StrEnum):
    SOFT_DELETE_POST = "soft_delete_post"
    SOFT_DELETE_COMMENT = "soft_delete_comment"
    SUSPEND_USER = "suspend_user"


@dataclass(slots=True)
class ReportUserSummary:
    id: UUID | None
    name: str | None
    avatar_url: str | None


@dataclass(slots=True)
class ReportTargetPreview:
    id: UUID
    target_type: ReportTargetType
    title: str | None
    subtitle: str | None
    status: str | None
    is_public: bool | None
    is_active: bool | None
    deleted_at: datetime | None


@dataclass(slots=True)
class ReportRecord:
    id: UUID
    reporter_id: UUID | None
    target_type: ReportTargetType
    target_id: UUID
    reason: str | None
    metadata: dict[str, object] | None
    status: ReportStatus
    handled_by: UUID | None
    handled_at: datetime | None
    created_at: datetime
    reporter: ReportUserSummary | None
    handler: ReportUserSummary | None


@dataclass(slots=True)
class ReportPage:
    items: list[ReportRecord]
    next_cursor: str | None
    limit: int


@dataclass(slots=True)
class ReportCreateDraft:
    reporter_id: UUID
    target_type: ReportTargetType
    target_id: UUID
    reason: str | None
    metadata: dict[str, object] | None


@dataclass(slots=True)
class ReportHandleDraft:
    status: ReportStatus
    handled_by: UUID
    handled_at: datetime
