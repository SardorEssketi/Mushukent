from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.core.dependencies import get_current_active_user, get_likes_service
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.likes.application.schemas import LikeResponse
from app.features.likes.application.service import LikesService

router = APIRouter(prefix="/posts")


@router.post(
    "/{post_id}/likes",
    response_model=ApiSuccess[LikeResponse],
    status_code=status.HTTP_200_OK,
)
def like_post(
    post_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    likes_service: LikesService = Depends(get_likes_service),
) -> ApiSuccess[LikeResponse]:
    return ApiSuccess(data=likes_service.like_post(post_id, current_user))


@router.delete(
    "/{post_id}/likes",
    status_code=status.HTTP_204_NO_CONTENT,
)
def unlike_post(
    post_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    likes_service: LikesService = Depends(get_likes_service),
):
    likes_service.unlike_post(post_id, current_user)
    return None
