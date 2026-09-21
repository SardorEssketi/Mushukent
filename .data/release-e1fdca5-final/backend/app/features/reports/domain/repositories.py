from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.reports.domain.models import (
    ReportPage,
    ReportRecord,
    ReportStatus,
    ReportTargetType,
)


@dataclass(slots=True)
class ReportTargetExists:
    target_type: ReportTargetType
    target_id: UUID


class ReportRepository(Protocol):
    def create(self, draft) -> ReportRecord: ...

    def get_by_id(
        self,
        report_id: UUID,
        *,
        for_update: bool = False,
    ) -> ReportRecord | None: ...

    def find_open_duplicate(
        self,
        *,
        reporter_id: UUID,
        target_type: ReportTargetType,
        target_id: UUID,
    ) -> ReportRecord | None: ...

    def list_reports(
        self,
        *,
        status: ReportStatus | None,
        limit: int,
        cursor: str | None = None,
    ) -> ReportPage: ...

    def resolve(
        self,
        report_id: UUID,
        *,
        status: ReportStatus,
        handled_by: UUID,
        handled_at: datetime,
    ) -> ReportRecord | None: ...
