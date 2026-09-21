from fastapi import APIRouter, Depends, status

from app.core.dependencies import get_current_active_user, get_reports_service
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.reports.application.schemas import ReportCreate, ReportResponse
from app.features.reports.application.service import ReportsService

router = APIRouter()


@router.post(
    "/reports",
    response_model=ApiSuccess[ReportResponse],
    response_model_exclude_none=True,
    status_code=status.HTTP_201_CREATED,
)
def create_report(
    payload: ReportCreate,
    current_user: AuthUser = Depends(get_current_active_user),
    reports_service: ReportsService = Depends(get_reports_service),
) -> ApiSuccess[ReportResponse]:
    return ApiSuccess(data=reports_service.create_report(current_user, payload))
