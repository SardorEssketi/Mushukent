from collections.abc import Sequence
from typing import Any

from fastapi import APIRouter, Depends, Query
from pydantic import ValidationError

from app.core.dependencies import get_feed_service, get_optional_current_user
from app.core.security import api_error
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.feed.application.schemas import FeedListItem, FeedQuery
from app.features.feed.application.service import FeedService
from app.features.posts.application.schemas import GenericListResponse

router = APIRouter(prefix="/feed")


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
    response_model=ApiSuccess[GenericListResponse[FeedListItem]],
    response_model_exclude_none=True,
)
def read_feed(
    filter_by: str = Query(default="recent", alias="filter"),
    latitude: float | None = Query(default=None, alias="lat"),
    longitude: float | None = Query(default=None, alias="lon"),
    radius_meters: int | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    cursor: str | None = Query(default=None),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    feed_service: FeedService = Depends(get_feed_service),
) -> ApiSuccess[GenericListResponse[FeedListItem]]:
    try:
        query = FeedQuery.model_validate(
            {
                "filter": filter_by,
                "lat": latitude,
                "lon": longitude,
                "radius_meters": radius_meters,
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
    return ApiSuccess(data=feed_service.list_feed(query, current_user=current_user))
