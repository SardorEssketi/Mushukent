from __future__ import annotations

from datetime import datetime
from typing import Any, Generic, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.features.reports.domain.models import (
    ReportAction,
    ReportPage,
    ReportRecord,
    ReportStatus,
    ReportTargetPreview,
    ReportTargetType,
    ReportUserSummary,
)

T = TypeVar("T")


class GenericListResponse(BaseModel, Generic[T]):
    model_config = ConfigDict(from_attributes=True)

    items: list[T]
    next_cursor: str | None = None
    limit: int


class ReportTargetSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    target_type: ReportTargetType
    title: str | None = None
    subtitle: str | None = None
    status: str | None = None
    is_public: bool | None = None
    is_active: bool | None = None
    deleted_at: datetime | None = None


class ReportActorSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID | None = None
    name: str | None = None
    avatar_url: str | None = None


class ReportMetadata(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    client_context: str | None = Field(default=None, max_length=200)


class ReportCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    target_type: ReportTargetType
    target_id: UUID
    reason: str | None = Field(default=None, max_length=1000)
    metadata: ReportMetadata | None = None

    @model_validator(mode="after")
    def _validate_reason(self) -> "ReportCreate":
        if self.reason is not None and not self.reason.strip():
            raise ValueError("Report reason must not be blank.")
        return self


class ReportHandleRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    status: ReportStatus
    action: ReportAction | None = None
    note: str | None = Field(default=None, max_length=1000)

    @model_validator(mode="after")
    def _validate_state(self) -> "ReportHandleRequest":
        if self.status == ReportStatus.OPEN:
            raise ValueError("Report status must resolve or dismiss a report.")
        if self.action is not None and self.status != ReportStatus.RESOLVED:
            raise ValueError("Report actions require resolved status.")
        if self.note is not None and not self.note.strip():
            raise ValueError("Note must not be blank.")
        return self


class ReportResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    reporter: ReportActorSummary | None = None
    target_type: ReportTargetType
    target_id: UUID
    target: ReportTargetSummary | None = None
    reason: str | None = None
    metadata: dict[str, Any] | None = None
    status: ReportStatus
    handled_by: ReportActorSummary | None = None
    handled_at: datetime | None = None
    created_at: datetime


class ReportListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    status: ReportStatus = ReportStatus.OPEN
    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None


def _to_actor_summary(actor: ReportUserSummary | None) -> ReportActorSummary | None:
    if actor is None:
        return None
    return ReportActorSummary.model_validate(actor, from_attributes=True)


def to_report_response(
    report: ReportRecord,
    *,
    target: ReportTargetPreview | None = None,
) -> ReportResponse:
    payload = {
        "id": report.id,
        "reporter": _to_actor_summary(report.reporter),
        "target_type": report.target_type,
        "target_id": report.target_id,
        "target": (
            ReportTargetSummary.model_validate(target, from_attributes=True)
            if target is not None
            else None
        ),
        "reason": report.reason,
        "metadata": report.metadata,
        "status": report.status,
        "handled_by": _to_actor_summary(report.handler),
        "handled_at": report.handled_at,
        "created_at": report.created_at,
    }
    return ReportResponse.model_validate(payload)


def to_report_page_response(
    page: ReportPage,
    *,
    target_by_report_id: dict[UUID, ReportTargetPreview | None] | None = None,
) -> GenericListResponse[ReportResponse]:
    target_by_report_id = target_by_report_id or {}
    return GenericListResponse[ReportResponse](
        items=[
            to_report_response(item, target=target_by_report_id.get(item.id)) for item in page.items
        ],
        next_cursor=page.next_cursor,
        limit=page.limit,
    )
