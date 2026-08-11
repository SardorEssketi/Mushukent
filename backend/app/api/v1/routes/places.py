from __future__ import annotations

from collections.abc import Sequence
from typing import Any

from fastapi import APIRouter, Depends, Query
from pydantic import ValidationError

from app.core.dependencies import get_places_service
from app.core.security import api_error
from app.features.auth.application.schemas import ApiSuccess
from app.features.places.application.schemas import (
    GenericListResponse,
    PlaceListItem,
    PlaceListQuery,
)
from app.features.places.application.service import PlacesService
from app.features.places.domain.models import PlaceCategory

router = APIRouter(prefix="/places")


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


@router.get(
    "",
    response_model=ApiSuccess[GenericListResponse[PlaceListItem]],
    response_model_exclude_none=True,
)
def list_places(
    category: list[PlaceCategory] | None = Query(default=None),
    latitude: float | None = Query(default=None, alias="lat"),
    longitude: float | None = Query(default=None, alias="lon"),
    radius_meters: int | None = Query(default=None),
    bbox: str | None = Query(default=None),
    limit: int = Query(default=100, ge=1, le=200),
    places_service: PlacesService = Depends(get_places_service),
) -> ApiSuccess[GenericListResponse[PlaceListItem]]:
    try:
        query = PlaceListQuery.model_validate(
            {
                "categories": category,
                "latitude": latitude,
                "longitude": longitude,
                "radius_meters": radius_meters,
                "bbox": bbox,
                "limit": limit,
            }
        )
    except ValidationError as exc:
        raise api_error(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details=_validation_details(exc.errors()),
        ) from exc
    return ApiSuccess(data=places_service.list_places(query))
