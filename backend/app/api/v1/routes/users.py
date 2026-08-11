from uuid import UUID

from fastapi import APIRouter, Depends, File, UploadFile, status

from app.core.dependencies import (
    get_comments_service,
    get_current_active_user,
    get_optional_current_user,
    get_posts_service,
    get_users_service,
)
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.comments.application.schemas import (
    CommentListQuery,
    CommentResponse,
)
from app.features.comments.application.schemas import (
    GenericListResponse as CommentListResponse,
)
from app.features.comments.application.service import CommentsService
from app.features.posts.application.schemas import GenericListResponse, PostListItem, PostListQuery
from app.features.posts.application.service import PostsService
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


@router.delete(
    "/me",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_me(
    current_user: AuthUser = Depends(get_current_active_user),
    users_service: UsersService = Depends(get_users_service),
):
    users_service.delete_me(current_user)
    return None


@router.post(
    "/{user_id}/block",
    status_code=status.HTTP_204_NO_CONTENT,
)
def block_user(
    user_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    users_service: UsersService = Depends(get_users_service),
):
    users_service.block_user(current_user, user_id)
    return None


@router.delete(
    "/{user_id}/block",
    status_code=status.HTTP_204_NO_CONTENT,
)
def unblock_user(
    user_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    users_service: UsersService = Depends(get_users_service),
):
    users_service.unblock_user(current_user, user_id)
    return None


@router.post(
    "/me/avatar",
    response_model=ApiSuccess[UserProfile],
    response_model_exclude_none=True,
)
async def update_my_avatar(
    avatar: UploadFile = File(...),
    current_user: AuthUser = Depends(get_current_active_user),
    users_service: UsersService = Depends(get_users_service),
) -> ApiSuccess[UserProfile]:
    content = await avatar.read()
    return ApiSuccess(
        data=users_service.update_avatar(
            current_user,
            content=content,
            content_type=avatar.content_type,
            filename=avatar.filename,
        )
    )


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


@router.get(
    "/{user_id}/posts",
    response_model=ApiSuccess[GenericListResponse[PostListItem]],
    response_model_exclude_none=True,
)
def read_user_posts(
    user_id: UUID,
    query: PostListQuery = Depends(),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    posts_service: PostsService = Depends(get_posts_service),
) -> ApiSuccess[GenericListResponse[PostListItem]]:
    return ApiSuccess(
        data=posts_service.list_posts_by_user(
            user_id,
            current_user=current_user,
            limit=query.limit,
            cursor=query.cursor,
            sort=query.sort,
        )
    )


@router.get(
    "/{user_id}/comments",
    response_model=ApiSuccess[CommentListResponse[CommentResponse]],
    response_model_exclude_none=True,
)
def read_user_comments(
    user_id: UUID,
    query: CommentListQuery = Depends(),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    comments_service: CommentsService = Depends(get_comments_service),
) -> ApiSuccess[CommentListResponse[CommentResponse]]:
    return ApiSuccess(
        data=comments_service.list_comments_by_user(
            user_id,
            current_user=current_user,
            limit=query.limit,
            cursor=query.cursor,
            order=query.order,
        )
    )
