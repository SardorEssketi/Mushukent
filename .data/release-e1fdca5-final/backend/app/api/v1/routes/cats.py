from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any, cast
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, UploadFile, status
from pydantic import ValidationError

from app.core.dependencies import (
    get_cats_service,
    get_current_active_user,
    get_optional_current_user,
    get_posts_service,
)
from app.core.security import api_error
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.cats.application.schemas import (
    CatCreateRequest,
    CatDetailResponse,
    CatListItem,
    CatListQuery,
    CatResponse,
    CatUpdateRequest,
    GenericListResponse,
)
from app.features.cats.application.service import CatsService
from app.features.cats.domain.models import ObservationSortOrder
from app.features.posts.application.schemas import (
    GenericListResponse as PostGenericListResponse,
)
from app.features.posts.application.schemas import (
    PostListItem,
    PostListQuery,
)
from app.features.posts.application.service import PostsService

router = APIRouter(prefix="/cats")


def _validation_details(errors: Sequence[object]) -> list[dict[str, Any]]:
    normalized: list[dict[str, Any]] = []
    for error in errors:
        if isinstance(error, dict):
            normalized.append(
                {
                    "loc": [str(part) for part in error.get("loc", ())],
                    "msg": str(error.get("msg", "Invalid value.")),
                    "type": str(error.get("type", "value_error")),
                }
            )
        else:
            normalized.append({"loc": [], "msg": "Invalid value.", "type": "value_error"})
    return normalized


async def _parse_cat_request(request: Request) -> tuple[dict[str, Any], UploadFile | None]:
    content_type = request.headers.get("content-type", "")
    if content_type.startswith("multipart/form-data"):
        form = await request.form()
        data: dict[str, Any] = dict(form)
        upload = data.pop("cover_photo", None)
        if upload is not None and hasattr(upload, "read") and hasattr(upload, "filename"):
            file = cast(UploadFile, upload)
        else:
            file = None
        canonical_location = data.get("canonical_location")
        if canonical_location is None:
            latitude = data.get("canonical_location_latitude") or data.get("latitude")
            longitude = data.get("canonical_location_longitude") or data.get("longitude")
            if latitude is not None and longitude is not None:
                data["canonical_location"] = {
                    "latitude": latitude,
                    "longitude": longitude,
                }
        elif isinstance(canonical_location, str):
            try:
                data["canonical_location"] = json.loads(canonical_location)
            except json.JSONDecodeError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"canonical_location": ["invalid"]},
                ) from exc
        return data, file

    try:
        payload = await request.json()
    except Exception as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details={"body": ["invalid_json"]},
        ) from exc
    return payload, None


def _parse_create_payload(data: dict[str, Any]) -> CatCreateRequest:
    try:
        return CatCreateRequest.model_validate(data)
    except ValidationError as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details=_validation_details(exc.errors()),
        ) from exc


def _parse_update_payload(data: dict[str, Any]) -> CatUpdateRequest:
    try:
        return CatUpdateRequest.model_validate(data)
    except ValidationError as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details=_validation_details(exc.errors()),
        ) from exc


@router.post(
    "",
    response_model=ApiSuccess[CatResponse],
    response_model_exclude_none=True,
    status_code=status.HTTP_201_CREATED,
)
async def create_cat(
    request: Request,
    current_user: AuthUser = Depends(get_current_active_user),
    cats_service: CatsService = Depends(get_cats_service),
) -> ApiSuccess[CatResponse]:
    data, upload = await _parse_cat_request(request)
    payload = _parse_create_payload(data)
    content = await upload.read() if upload is not None else None
    return ApiSuccess(
        data=cats_service.create_cat(
            current_user,
            payload,
            cover_photo_content=content,
            cover_photo_content_type=upload.content_type if upload is not None else None,
            cover_photo_filename=upload.filename if upload is not None else None,
        )
    )


@router.patch(
    "/{cat_id}",
    response_model=ApiSuccess[CatResponse],
    response_model_exclude_none=True,
)
async def update_cat(
    cat_id: UUID,
    request: Request,
    current_user: AuthUser = Depends(get_current_active_user),
    cats_service: CatsService = Depends(get_cats_service),
) -> ApiSuccess[CatResponse]:
    data, upload = await _parse_cat_request(request)
    payload = _parse_update_payload(data)
    content = await upload.read() if upload is not None else None
    return ApiSuccess(
        data=cats_service.update_cat(
            current_user,
            cat_id,
            payload,
            cover_photo_content=content,
            cover_photo_content_type=upload.content_type if upload is not None else None,
            cover_photo_filename=upload.filename if upload is not None else None,
        )
    )


@router.get(
    "/{cat_id}",
    response_model=ApiSuccess[CatDetailResponse],
    response_model_exclude_none=True,
)
def read_cat(
    cat_id: UUID,
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    sort: ObservationSortOrder = Query(default=ObservationSortOrder.LATEST),
    cats_service: CatsService = Depends(get_cats_service),
) -> ApiSuccess[CatDetailResponse]:
    return ApiSuccess(data=cats_service.get_cat(cat_id, limit=limit, cursor=cursor, order=sort))


@router.get(
    "",
    response_model=ApiSuccess[GenericListResponse[CatListItem]],
    response_model_exclude_none=True,
)
def list_cats(
    filter_by: str = Query(default="recently_added", alias="filter"),
    latitude: float | None = Query(default=None, alias="lat"),
    longitude: float | None = Query(default=None, alias="lon"),
    radius_meters: int | None = Query(default=None),
    bbox: str | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    cats_service: CatsService = Depends(get_cats_service),
) -> ApiSuccess[GenericListResponse[CatListItem]]:
    try:
        query = CatListQuery.model_validate(
            {
                "filter_by": filter_by,
                "latitude": latitude,
                "longitude": longitude,
                "radius_meters": radius_meters,
                "bbox": bbox,
                "limit": limit,
                "cursor": cursor,
            }
        )
    except ValidationError as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details=_validation_details(exc.errors()),
        ) from exc
    return ApiSuccess(data=cats_service.list_cats(query))


@router.get(
    "/{cat_id}/posts",
    response_model=ApiSuccess[PostGenericListResponse[PostListItem]],
    response_model_exclude_none=True,
)
def read_cat_posts(
    cat_id: UUID,
    query: PostListQuery = Depends(),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    posts_service: PostsService = Depends(get_posts_service),
) -> ApiSuccess[PostGenericListResponse[PostListItem]]:
    return ApiSuccess(
        data=posts_service.list_posts_by_cat(
            cat_id,
            current_user=current_user,
            limit=query.limit,
            cursor=query.cursor,
            sort=query.sort,
        )
    )
