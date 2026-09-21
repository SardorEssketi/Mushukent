from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any, cast
from uuid import UUID

from fastapi import APIRouter, Depends, Request, UploadFile, status
from pydantic import ValidationError

from app.core.dependencies import (
    get_current_active_user,
    get_optional_current_user,
    get_posts_service,
)
from app.core.security import api_error
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.posts.application.schemas import (
    PostCreateJSONRequest,
    PostCreateMultipartRequest,
    PostResponse,
)
from app.features.posts.application.service import PostsService

router = APIRouter(prefix="/posts")


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


def _apply_flat_location_fields(data: dict[str, Any]) -> dict[str, Any]:
    if data.get("location") is None:
        latitude = data.pop("latitude", None)
        longitude = data.pop("longitude", None)
        if latitude is not None and longitude is not None:
            data["location"] = {"latitude": latitude, "longitude": longitude}
    return data


def _apply_new_cat_fields(data: dict[str, Any]) -> dict[str, Any]:
    new_cat = data.get("new_cat")
    if new_cat is None:
        name = data.pop("new_cat_name", None)
        status = data.pop("new_cat_status", None)
        canonical_location = data.pop("new_cat_canonical_location", None)
        if name is not None or status is not None or canonical_location is not None:
            new_cat = {}
            if name is not None:
                new_cat["name"] = name
            if status is not None:
                new_cat["status"] = status
            if canonical_location is not None:
                new_cat["canonical_location"] = canonical_location
            data["new_cat"] = new_cat
    elif isinstance(new_cat, str):
        try:
            data["new_cat"] = json.loads(new_cat)
        except json.JSONDecodeError as exc:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"new_cat": ["invalid"]},
            ) from exc
    return data


async def _parse_post_request(
    request: Request,
) -> tuple[dict[str, Any], list[UploadFile], bool]:
    content_type = request.headers.get("content-type", "")
    if content_type.startswith("multipart/form-data"):
        form = await request.form()
        data: dict[str, Any] = dict(form)
        uploads = [
            cast(UploadFile, item)
            for item in [*form.getlist("photo"), *form.getlist("photos")]
            if hasattr(item, "read")
        ]
        data.pop("photo", None)
        data.pop("photos", None)
        if isinstance(data.get("location"), str):
            try:
                data["location"] = json.loads(data["location"])
            except json.JSONDecodeError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"location": ["invalid"]},
                ) from exc
        data = _apply_flat_location_fields(data)
        data = _apply_new_cat_fields(data)
        return data, uploads, False

    try:
        payload = await request.json()
    except Exception as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details={"body": ["invalid_json"]},
        ) from exc
    payload = _apply_new_cat_fields(_apply_flat_location_fields(dict(payload)))
    return payload, [], True


def _parse_json_payload(data: dict[str, Any]) -> PostCreateJSONRequest:
    try:
        return PostCreateJSONRequest.model_validate(data)
    except ValidationError as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details=_validation_details(exc.errors()),
        ) from exc


def _parse_multipart_payload(data: dict[str, Any]) -> PostCreateMultipartRequest:
    try:
        return PostCreateMultipartRequest.model_validate(data)
    except ValidationError as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details=_validation_details(exc.errors()),
        ) from exc


@router.post(
    "",
    response_model=ApiSuccess[PostResponse],
    response_model_exclude_none=True,
    status_code=status.HTTP_201_CREATED,
)
async def create_post(
    request: Request,
    current_user: AuthUser = Depends(get_current_active_user),
    posts_service: PostsService = Depends(get_posts_service),
) -> ApiSuccess[PostResponse]:
    data, uploads, is_json = await _parse_post_request(request)
    payload = _parse_json_payload(data) if is_json else _parse_multipart_payload(data)
    photo_payloads = [
        (await upload.read(), upload.content_type, upload.filename) for upload in uploads
    ]
    return ApiSuccess(
        data=posts_service.create_post(
            current_user,
            payload,
            photos=photo_payloads,
        )
    )


@router.get(
    "/{post_id}",
    response_model=ApiSuccess[PostResponse],
    response_model_exclude_none=True,
)
def read_post(
    post_id: UUID,
    current_user: AuthUser | None = Depends(get_optional_current_user),
    posts_service: PostsService = Depends(get_posts_service),
) -> ApiSuccess[PostResponse]:
    return ApiSuccess(data=posts_service.get_post(post_id, current_user=current_user))


@router.delete(
    "/{post_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
def delete_post(
    post_id: UUID,
    current_user: AuthUser = Depends(get_current_active_user),
    posts_service: PostsService = Depends(get_posts_service),
):
    posts_service.delete_post(post_id, current_user)
    return None
