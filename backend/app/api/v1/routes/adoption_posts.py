from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Query, Request, UploadFile, status
from pydantic import ValidationError

from app.api.v1.uploads import read_image_uploads, run_upload_processing
from app.core.dependencies import get_adoption_posts_service, get_current_active_user
from app.core.security import api_error
from app.features.adoption_posts.application.schemas import (
    AdoptionFollowUpAnswer,
    AdoptionFollowUpItem,
    AdoptionPostCreateRequest,
    AdoptionPostListItem,
    AdoptionPostResponse,
    AdoptionPostUpdateRequest,
)
from app.features.adoption_posts.application.service import AdoptionPostsService
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.posts.application.schemas import GenericListResponse

router = APIRouter(prefix="/adoption-posts")


def _parse_create_payload(
    pet_name: str,
    additional_info: str | None,
) -> AdoptionPostCreateRequest:
    try:
        return AdoptionPostCreateRequest.model_validate(
            {
                "pet_name": pet_name,
                "additional_info": additional_info,
            }
        )
    except ValidationError as exc:
        details: dict[str, Any] = {"body": exc.errors()}
        raise api_error(422, "VALIDATION_ERROR", "Validation failed.", details=details) from exc


@router.post(
    "",
    response_model=ApiSuccess[AdoptionPostResponse],
    status_code=status.HTTP_201_CREATED,
    response_model_exclude_none=True,
)
async def create_adoption_post(
    pet_name: str = Form(...),
    additional_info: str | None = Form(default=None),
    photos: list[UploadFile] = File(...),
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[AdoptionPostResponse]:
    payload = _parse_create_payload(
        pet_name,
        additional_info,
    )
    photo_payloads = await read_image_uploads(photos, purpose="adoption_create")
    return ApiSuccess(
        data=await run_upload_processing(
            adoption_posts_service.create_adoption_post,
            current_user,
            payload,
            photos=photo_payloads,
        )
    )


@router.get(
    "",
    response_model=ApiSuccess[GenericListResponse[AdoptionPostListItem]],
    response_model_exclude_none=True,
)
def list_adoption_posts(
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[GenericListResponse[AdoptionPostListItem]]:
    return ApiSuccess(
        data=adoption_posts_service.list_adoption_posts(
            limit=limit,
            cursor=cursor,
        )
    )


@router.get("/mine", response_model=ApiSuccess[GenericListResponse[AdoptionPostListItem]])
def list_my_adoption_posts(
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[GenericListResponse[AdoptionPostListItem]]:
    return ApiSuccess(
        data=adoption_posts_service.list_my_adoption_posts(current_user, limit=limit, cursor=cursor)
    )


@router.get("/follow-ups/due", response_model=ApiSuccess[list[AdoptionFollowUpItem]])
def list_due_follow_ups(
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[list[AdoptionFollowUpItem]]:
    return ApiSuccess(data=adoption_posts_service.list_due_follow_ups(current_user))


@router.post("/follow-ups/{follow_up_id}/answer", response_model=ApiSuccess[AdoptionPostResponse])
def answer_follow_up(
    follow_up_id: UUID,
    payload: AdoptionFollowUpAnswer,
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[AdoptionPostResponse]:
    return ApiSuccess(
        data=adoption_posts_service.answer_follow_up(follow_up_id, current_user, payload)
    )


@router.post("/{adoption_post_id}/contact", status_code=status.HTTP_204_NO_CONTENT)
def contact_owner(
    adoption_post_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> None:
    adoption_posts_service.contact_owner(adoption_post_id, current_user)


@router.patch(
    "/{adoption_post_id}",
    response_model=ApiSuccess[AdoptionPostResponse],
    response_model_exclude_none=True,
)
async def update_adoption_post(
    adoption_post_id: UUID,
    request: Request,
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[AdoptionPostResponse]:
    if request.headers.get("content-type", "").startswith("multipart/form-data"):
        form = await request.form()
        data: dict[str, Any] = dict(form)
        uploads = [item for item in form.getlist("photos") if hasattr(item, "read")]
        data.pop("photos", None)
    else:
        try:
            data = await request.json()
        except Exception as exc:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"body": ["invalid_json"]},
            ) from exc
        if not isinstance(data, dict):
            raise api_error(422, "VALIDATION_ERROR", "Validation failed.")
        uploads = []
    try:
        payload = AdoptionPostUpdateRequest.model_validate(data)
    except ValidationError as exc:
        raise api_error(
            422, "VALIDATION_ERROR", "Validation failed.", details={"body": exc.errors()}
        ) from exc
    photo_payloads = await read_image_uploads(uploads, purpose="adoption_update")
    return ApiSuccess(
        data=await run_upload_processing(
            adoption_posts_service.update_adoption_post,
            adoption_post_id,
            current_user,
            payload,
            photos=photo_payloads,
        )
    )


@router.delete("/{adoption_post_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_adoption_post(
    adoption_post_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> None:
    adoption_posts_service.delete_adoption_post(adoption_post_id, current_user)


@router.get(
    "/{adoption_post_id}",
    response_model=ApiSuccess[AdoptionPostResponse],
    response_model_exclude_none=True,
)
def get_adoption_post(
    adoption_post_id: UUID,
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[AdoptionPostResponse]:
    return ApiSuccess(data=adoption_posts_service.get_adoption_post(adoption_post_id))
