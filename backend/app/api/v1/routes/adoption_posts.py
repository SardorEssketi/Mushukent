from __future__ import annotations

from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile, status
from pydantic import ValidationError

from app.core.dependencies import get_adoption_posts_service, get_current_active_user
from app.core.security import api_error
from app.features.adoption_posts.application.schemas import (
    AdoptionPostCreateRequest,
    AdoptionPostListItem,
    AdoptionPostResponse,
)
from app.features.adoption_posts.application.service import AdoptionPostsService
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.posts.application.schemas import GenericListResponse

router = APIRouter(prefix="/adoption-posts")


def _parse_create_payload(
    pet_name: str,
    additional_info: str | None,
    owner_phone_publication_consent: bool,
) -> AdoptionPostCreateRequest:
    try:
        return AdoptionPostCreateRequest.model_validate(
            {
                "pet_name": pet_name,
                "additional_info": additional_info,
                "owner_phone_publication_consent": owner_phone_publication_consent,
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
    owner_phone_publication_consent: bool = Form(...),
    photos: list[UploadFile] = File(...),
    current_user: AuthUser = Depends(get_current_active_user),
    adoption_posts_service: AdoptionPostsService = Depends(get_adoption_posts_service),
) -> ApiSuccess[AdoptionPostResponse]:
    payload = _parse_create_payload(
        pet_name,
        additional_info,
        owner_phone_publication_consent,
    )
    photo_payloads = [(await photo.read(), photo.content_type, photo.filename) for photo in photos]
    return ApiSuccess(
        data=adoption_posts_service.create_adoption_post(
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
