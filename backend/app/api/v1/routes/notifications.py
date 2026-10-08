from uuid import UUID

from fastapi import APIRouter, Depends, Query, status

from app.core.dependencies import get_current_active_user, get_notification_service
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.notifications.application.schemas import (
    DeviceTokenRequest,
    MarkAllResult,
    NotificationPage,
    PreferencePatch,
    PreferenceResponse,
    UnreadCount,
)
from app.features.notifications.application.service import NotificationService

router = APIRouter(prefix="/notifications")


@router.get("", response_model=ApiSuccess[NotificationPage])
def list_notifications(
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = None,
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> ApiSuccess[NotificationPage]:
    return ApiSuccess(data=service.list_notifications(user.id, limit, cursor))


@router.get("/unread-count", response_model=ApiSuccess[UnreadCount])
def unread_count(
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> ApiSuccess[UnreadCount]:
    return ApiSuccess(data=UnreadCount(count=service.unread_count(user.id)))


@router.get("/preferences", response_model=ApiSuccess[PreferenceResponse])
def get_preferences(
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> ApiSuccess[PreferenceResponse]:
    return ApiSuccess(data=service.preferences(user.id))


@router.patch("/preferences", response_model=ApiSuccess[PreferenceResponse])
def update_preferences(
    patch: PreferencePatch,
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> ApiSuccess[PreferenceResponse]:
    return ApiSuccess(data=service.update_preferences(user.id, patch))


@router.post("/activity", status_code=status.HTTP_204_NO_CONTENT)
def record_activity(
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> None:
    service.record_activity(user.id)


@router.post("/devices", status_code=status.HTTP_204_NO_CONTENT)
def register_device(
    payload: DeviceTokenRequest,
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> None:
    service.register_device(user.id, payload.token, payload.previous_token)


@router.post("/devices/unregister", status_code=status.HTTP_204_NO_CONTENT)
def unregister_device(
    payload: DeviceTokenRequest,
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> None:
    service.unregister_device(user.id, payload.token)


@router.post("/read-all", response_model=ApiSuccess[MarkAllResult])
def mark_all_read(
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> ApiSuccess[MarkAllResult]:
    return ApiSuccess(data=MarkAllResult(marked=service.mark_all_read(user.id)))


@router.post("/{notification_id}/read", status_code=status.HTTP_204_NO_CONTENT)
def mark_read(
    notification_id: UUID,
    user: AuthUser = Depends(get_current_active_user),
    service: NotificationService = Depends(get_notification_service),
) -> None:
    service.mark_read(user.id, notification_id)
