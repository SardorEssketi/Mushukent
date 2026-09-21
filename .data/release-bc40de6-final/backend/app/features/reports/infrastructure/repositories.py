from __future__ import annotations

import base64
import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import and_, or_, select, update
from sqlalchemy.orm import Session, aliased

from app.features.reports.domain.models import (
    ReportPage,
    ReportRecord,
    ReportStatus,
    ReportTargetType,
    ReportUserSummary,
)
from app.features.reports.domain.repositories import ReportRepository
from app.infrastructure.db.models import schema


class SqlAlchemyReportRepository(ReportRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, draft) -> ReportRecord:
        model = schema.Report(
            id=uuid4(),
            reporter_id=draft.reporter_id,
            target_type=schema.ReportTargetType(draft.target_type.value),
            target_id=draft.target_id,
            reason=draft.reason,
            metadata_json=draft.metadata,
        )
        self.session.add(model)
        self.session.flush()
        record = self.get_by_id(model.id)
        if record is None:
            raise RuntimeError("Created report could not be loaded.")
        return record

    def get_by_id(
        self,
        report_id: UUID,
        *,
        for_update: bool = False,
    ) -> ReportRecord | None:
        statement = self._statement().where(schema.Report.id == report_id)
        if for_update:
            statement = statement.with_for_update(of=schema.Report)
        row = self.session.execute(statement).mappings().first()
        return self._row_to_record(row) if row is not None else None

    def find_open_duplicate(
        self,
        *,
        reporter_id: UUID,
        target_type: ReportTargetType,
        target_id: UUID,
    ) -> ReportRecord | None:
        statement = self._statement().where(
            schema.Report.reporter_id == reporter_id,
            schema.Report.target_type == schema.ReportTargetType(target_type.value),
            schema.Report.target_id == target_id,
            schema.Report.status == schema.ReportStatus.OPEN,
        )
        row = self.session.execute(statement).mappings().first()
        return self._row_to_record(row) if row is not None else None

    def list_reports(
        self,
        *,
        status: ReportStatus | None,
        limit: int,
        cursor: str | None = None,
    ) -> ReportPage:
        statement = self._statement()
        if status is not None:
            statement = statement.where(schema.Report.status == schema.ReportStatus(status.value))
        payload = self._decode_cursor(cursor) if cursor is not None else None
        if payload is not None:
            cursor_created_at = payload["created_at"]
            cursor_id = UUID(payload["id"])
            statement = statement.where(
                or_(
                    schema.Report.created_at < cursor_created_at,
                    and_(
                        schema.Report.created_at == cursor_created_at,
                        schema.Report.id < cursor_id,
                    ),
                )
            )
        statement = statement.order_by(
            schema.Report.created_at.desc(), schema.Report.id.desc()
        ).limit(limit + 1)
        rows = self.session.execute(statement).mappings().all()
        items = [self._row_to_record(row) for row in rows[:limit]]
        next_cursor = (
            self._encode_cursor(rows[limit - 1]["created_at"], rows[limit - 1]["report_id"])
            if len(rows) > limit
            else None
        )
        return ReportPage(items=items, next_cursor=next_cursor, limit=limit)

    def resolve(
        self,
        report_id: UUID,
        *,
        status: ReportStatus,
        handled_by: UUID,
        handled_at: datetime,
    ) -> ReportRecord | None:
        result = self.session.execute(
            update(schema.Report)
            .where(schema.Report.id == report_id, schema.Report.status == schema.ReportStatus.OPEN)
            .values(
                status=schema.ReportStatus(status.value),
                handled_by=handled_by,
                handled_at=handled_at,
            )
            .returning(schema.Report.id)
        ).first()
        if result is None:
            return None
        return self.get_by_id(report_id)

    def _statement(self):
        reporter_user = aliased(schema.User)
        handler_user = aliased(schema.User)
        return (
            select(
                schema.Report.id.label("report_id"),
                schema.Report.reporter_id.label("reporter_id"),
                schema.Report.target_type.label("target_type"),
                schema.Report.target_id.label("target_id"),
                schema.Report.reason.label("reason"),
                schema.Report.metadata_json.label("metadata_json"),
                schema.Report.status.label("status"),
                schema.Report.handled_by.label("handled_by"),
                schema.Report.handled_at.label("handled_at"),
                schema.Report.created_at.label("created_at"),
                reporter_user.id.label("reporter_user_id"),
                reporter_user.name.label("reporter_name"),
                reporter_user.avatar_url.label("reporter_avatar_url"),
                handler_user.id.label("handler_user_id"),
                handler_user.name.label("handler_name"),
                handler_user.avatar_url.label("handler_avatar_url"),
            )
            .select_from(schema.Report)
            .outerjoin(reporter_user, schema.Report.reporter_id == reporter_user.id)
            .outerjoin(handler_user, schema.Report.handled_by == handler_user.id)
        )

    def _row_to_record(self, row: Any) -> ReportRecord:
        reporter_id = row["reporter_user_id"]
        handler_id = row["handler_user_id"]
        return ReportRecord(
            id=row["report_id"],
            reporter_id=row["reporter_id"],
            target_type=ReportTargetType(row["target_type"]),
            target_id=row["target_id"],
            reason=row["reason"],
            metadata=row["metadata_json"],
            status=ReportStatus(row["status"]),
            handled_by=row["handled_by"],
            handled_at=row["handled_at"],
            created_at=row["created_at"],
            reporter=(
                ReportUserSummary(
                    id=reporter_id,
                    name=row["reporter_name"],
                    avatar_url=row["reporter_avatar_url"],
                )
                if reporter_id is not None
                else None
            ),
            handler=(
                ReportUserSummary(
                    id=handler_id,
                    name=row["handler_name"],
                    avatar_url=row["handler_avatar_url"],
                )
                if handler_id is not None
                else None
            ),
        )

    def _decode_cursor(self, cursor: str) -> dict[str, Any]:
        try:
            raw = base64.urlsafe_b64decode(cursor.encode("utf-8")).decode("utf-8")
            payload = json.loads(raw)
            created_at_value = payload["created_at"]
            if isinstance(created_at_value, str):
                payload["created_at"] = datetime.fromisoformat(
                    created_at_value.replace("Z", "+00:00")
                )
            else:
                raise ValueError
            UUID(str(payload["id"]))
            return payload
        except Exception as exc:  # pragma: no cover - defensive cursor handling
            raise ValueError("Invalid cursor.") from exc

    def _encode_cursor(self, created_at: datetime, report_id: UUID) -> str:
        payload = {
            "created_at": created_at.astimezone(UTC).isoformat().replace("+00:00", "Z"),
            "id": str(report_id),
        }
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("utf-8")
