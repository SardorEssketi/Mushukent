from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.core.dependencies import get_moderation_service, require_moderator
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.moderation.application.service import ModerationService
from app.features.reports.application.schemas import (
    GenericListResponse,
    ReportHandleRequest,
    ReportListQuery,
    ReportResponse,
)

router = APIRouter(prefix="/moderation")


@router.get(
    "/reports",
    response_model=ApiSuccess[GenericListResponse[ReportResponse]],
    response_model_exclude_none=True,
)
def list_reports(
    query: ReportListQuery = Depends(),
    current_user: AuthUser = Depends(require_moderator),
    moderation_service: ModerationService = Depends(get_moderation_service),
) -> ApiSuccess[GenericListResponse[ReportResponse]]:
    return ApiSuccess(data=moderation_service.list_reports(query, current_user=current_user))


@router.patch(
    "/reports/{report_id}",
    response_model=ApiSuccess[ReportResponse],
    response_model_exclude_none=True,
)
def handle_report(
    report_id: UUID,
    payload: ReportHandleRequest,
    current_user: AuthUser = Depends(require_moderator),
    moderation_service: ModerationService = Depends(get_moderation_service),
) -> ApiSuccess[ReportResponse]:
    return ApiSuccess(
        data=moderation_service.handle_report(
            report_id,
            current_user=current_user,
            payload=payload,
        )
    )


@router.delete(
    "/posts/{post_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_post(
    post_id: UUID,
    current_user: AuthUser = Depends(require_moderator),
    moderation_service: ModerationService = Depends(get_moderation_service),
):
    moderation_service.delete_post(post_id, current_user=current_user)
    return None
