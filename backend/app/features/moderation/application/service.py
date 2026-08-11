from __future__ import annotations

from typing import Protocol
from uuid import UUID

from app.features.auth.domain.models import AuthUser
from app.features.posts.application.service import PostsService
from app.features.reports.application.schemas import (
    GenericListResponse,
    ReportHandleRequest,
    ReportListQuery,
    ReportResponse,
)
from app.features.reports.application.service import ReportsService


class PostsServiceFactory(Protocol):
    def __call__(self) -> PostsService: ...


class ModerationService:
    def __init__(
        self,
        *,
        reports_service: ReportsService,
        posts_service_factory: PostsServiceFactory,
    ) -> None:
        self.reports_service = reports_service
        self.posts_service_factory = posts_service_factory

    def list_reports(
        self,
        query: ReportListQuery,
        *,
        current_user: AuthUser,
    ) -> GenericListResponse[ReportResponse]:
        return self.reports_service.list_reports(query, user=current_user)

    def handle_report(
        self,
        report_id: UUID,
        *,
        current_user: AuthUser,
        payload: ReportHandleRequest,
    ) -> ReportResponse:
        return self.reports_service.handle_report(report_id, current_user, payload)

    def delete_post(self, post_id: UUID, *, current_user: AuthUser) -> None:
        self.posts_service_factory().delete_post(post_id, current_user)
