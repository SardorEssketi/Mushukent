from __future__ import annotations

import json
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, File, Form, Query, UploadFile, status
from pydantic import ValidationError

from app.api.v1.uploads import read_image_uploads, run_upload_processing
from app.core.dependencies import get_current_active_user, get_lost_pets_service
from app.core.security import api_error
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.lost_pets.application.schemas import (
    LostPetCreateRequest,
    LostPetListItem,
    LostPetMapListItem,
    LostPetResponse,
)
from app.features.lost_pets.application.service import LostPetsService
from app.features.posts.application.schemas import GenericListResponse

router = APIRouter(prefix="/lost-pets")


def _parse_create_payload(
    last_seen_location: str,
    pet_name: str,
    additional_info: str | None,
    owner_phone_publication_consent: bool,
) -> LostPetCreateRequest:
    try:
        location = json.loads(last_seen_location)
    except json.JSONDecodeError as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details={"last_seen_location": ["invalid_json"]},
        ) from exc
    try:
        return LostPetCreateRequest.model_validate(
            {
                "last_seen_location": location,
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
    response_model=ApiSuccess[LostPetResponse],
    status_code=status.HTTP_201_CREATED,
    response_model_exclude_none=True,
)
async def create_lost_pet(
    last_seen_location: str = Form(...),
    pet_name: str = Form(...),
    additional_info: str | None = Form(default=None),
    owner_phone_publication_consent: bool = Form(...),
    photos: list[UploadFile] = File(...),
    current_user: AuthUser = Depends(get_current_active_user),
    lost_pets_service: LostPetsService = Depends(get_lost_pets_service),
) -> ApiSuccess[LostPetResponse]:
    payload = _parse_create_payload(
        last_seen_location,
        pet_name,
        additional_info,
        owner_phone_publication_consent,
    )
    photo_payloads = await read_image_uploads(photos, purpose="lost_pet_create")
    return ApiSuccess(
        data=await run_upload_processing(
            lost_pets_service.create_lost_pet,
            current_user,
            payload,
            photos=photo_payloads,
        )
    )


@router.get(
    "",
    response_model=ApiSuccess[GenericListResponse[LostPetListItem]],
    response_model_exclude_none=True,
)
def list_lost_pets(
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    latitude: float | None = Query(default=None, alias="lat"),
    longitude: float | None = Query(default=None, alias="lon"),
    radius_meters: int | None = Query(default=None, ge=1, le=5000),
    bbox: str | None = Query(default=None),
    valid_for_map: bool = Query(default=False),
    lost_pets_service: LostPetsService = Depends(get_lost_pets_service),
) -> ApiSuccess[GenericListResponse[LostPetListItem]]:
    return ApiSuccess(
        data=lost_pets_service.list_lost_pets(
            limit=limit,
            cursor=cursor,
            latitude=latitude,
            longitude=longitude,
            radius_meters=radius_meters,
            bbox=bbox,
            valid_for_map=valid_for_map,
        )
    )


@router.get(
    "/map",
    response_model=ApiSuccess[GenericListResponse[LostPetMapListItem]],
    response_model_exclude_none=True,
)
def list_lost_pet_map_markers(
    bbox: str = Query(...),
    limit: int = Query(default=100, ge=1, le=100),
    lost_pets_service: LostPetsService = Depends(get_lost_pets_service),
) -> ApiSuccess[GenericListResponse[LostPetMapListItem]]:
    return ApiSuccess(data=lost_pets_service.list_map_markers(limit=limit, bbox=bbox))


@router.get(
    "/{lost_pet_id}",
    response_model=ApiSuccess[LostPetResponse],
    response_model_exclude_none=True,
)
def get_lost_pet(
    lost_pet_id: UUID,
    lost_pets_service: LostPetsService = Depends(get_lost_pets_service),
) -> ApiSuccess[LostPetResponse]:
    return ApiSuccess(data=lost_pets_service.get_lost_pet(lost_pet_id))
