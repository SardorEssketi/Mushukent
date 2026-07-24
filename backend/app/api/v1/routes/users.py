from uuid import UUID

from fastapi import APIRouter, Depends

from app.core.dependencies import get_current_active_user, get_users_service
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.users.application.schemas import UserProfile, UserPublic, UserUpdate
from app.features.users.application.service import UsersService

router = APIRouter(prefix="/users")


@router.get(
    "/me",
    response_model=ApiSuccess[UserProfile],
    response_model_exclude_none=True,
)
def read_me(
    current_user: AuthUser = Depends(get_current_active_user),
    users_service: UsersService = Depends(get_users_service),
) -> ApiSuccess[UserProfile]:
    return ApiSuccess(data=users_service.get_me(current_user))


@router.patch(
    "/me",
    response_model=ApiSuccess[UserProfile],
    response_model_exclude_none=True,
)
def update_me(
    payload: UserUpdate,
    current_user: AuthUser = Depends(get_current_active_user),
    users_service: UsersService = Depends(get_users_service),
) -> ApiSuccess[UserProfile]:
    return ApiSuccess(data=users_service.update_me(current_user, payload))


@router.get(
    "/{user_id}",
    response_model=ApiSuccess[UserPublic],
    response_model_exclude_none=True,
)
def read_public_profile(
    user_id: UUID,
    users_service: UsersService = Depends(get_users_service),
) -> ApiSuccess[UserPublic]:
    return ApiSuccess(data=users_service.get_public_profile(user_id))
