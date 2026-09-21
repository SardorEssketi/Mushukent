from uuid import UUID

from fastapi import APIRouter, Depends, status

from app.core.dependencies import (
    get_comments_service,
    get_current_active_user,
    get_optional_current_user,
)
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.comments.application.schemas import (
    CommentCreate,
    CommentListQuery,
    CommentResponse,
    GenericListResponse,
)
from app.features.comments.application.service import CommentsService

router = APIRouter()


@router.post(
    "/posts/{post_id}/comments",
    response_model=ApiSuccess[CommentResponse],
    status_code=status.HTTP_201_CREATED,
)
def create_comment(
    post_id: UUID,
    payload: CommentCreate,
    current_user: AuthUser = Depends(get_current_active_user),
    comments_service: CommentsService = Depends(get_comments_service),
) -> ApiSuccess[CommentResponse]:
    return ApiSuccess(data=comments_service.create_comment(post_id, current_user, payload))


@router.post(
    "/lost-pets/{lost_pet_id}/comments",
    response_model=ApiSuccess[CommentResponse],
    status_code=status.HTTP_201_CREATED,
)
def create_lost_pet_comment(
    lost_pet_id: UUID,
    payload: CommentCreate,
    current_user: AuthUser = Depends(get_current_active_user),
    comments_service: CommentsService = Depends(get_comments_service),
) -> ApiSuccess[CommentResponse]:
    return ApiSuccess(
        data=comments_service.create_lost_pet_comment(lost_pet_id, current_user, payload)
    )


@router.post(
    "/adoption-posts/{adoption_post_id}/comments",
    response_model=ApiSuccess[CommentResponse],
    status_code=status.HTTP_201_CREATED,
)
def create_adoption_post_comment(
    adoption_post_id: UUID,
    payload: CommentCreate,
    current_user: AuthUser = Depends(get_current_active_user),
    comments_service: CommentsService = Depends(get_comments_service),
) -> ApiSuccess[CommentResponse]:
    return ApiSuccess(
        data=comments_service.create_adoption_post_comment(
            adoption_post_id,
            current_user,
            payload,
        )
    )


@router.get(
    "/posts/{post_id}/comments",
    response_model=ApiSuccess[GenericListResponse[CommentResponse]],
)
def list_comments(
    post_id: UUID,
    query: CommentListQuery = Depends(),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    comments_service: CommentsService = Depends(get_comments_service),
) -> ApiSuccess[GenericListResponse[CommentResponse]]:
    return ApiSuccess(
        data=comments_service.list_comments(
            post_id,
            current_user=current_user,
            limit=query.limit,
            cursor=query.cursor,
            order=query.order,
        )
    )


@router.get(
    "/lost-pets/{lost_pet_id}/comments",
    response_model=ApiSuccess[GenericListResponse[CommentResponse]],
)
def list_lost_pet_comments(
    lost_pet_id: UUID,
    query: CommentListQuery = Depends(),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    comments_service: CommentsService = Depends(get_comments_service),
) -> ApiSuccess[GenericListResponse[CommentResponse]]:
    return ApiSuccess(
        data=comments_service.list_lost_pet_comments(
            lost_pet_id,
            current_user=current_user,
            limit=query.limit,
            cursor=query.cursor,
            order=query.order,
        )
    )


@router.get(
    "/adoption-posts/{adoption_post_id}/comments",
    response_model=ApiSuccess[GenericListResponse[CommentResponse]],
)
def list_adoption_post_comments(
    adoption_post_id: UUID,
    query: CommentListQuery = Depends(),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    comments_service: CommentsService = Depends(get_comments_service),
) -> ApiSuccess[GenericListResponse[CommentResponse]]:
    return ApiSuccess(
        data=comments_service.list_adoption_post_comments(
            adoption_post_id,
            current_user=current_user,
            limit=query.limit,
            cursor=query.cursor,
            order=query.order,
        )
    )


@router.delete(
    "/comments/{comment_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_comment(
    comment_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    comments_service: CommentsService = Depends(get_comments_service),
):
    comments_service.delete_comment(comment_id, current_user)
    return None
