from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.features.cats.domain.models import GeoPoint
from app.features.places.domain.models import PlaceCategory, PlaceSource, PlaceSummary

T = TypeVar("T")


class GenericListResponse(BaseModel, Generic[T]):
    model_config = ConfigDict(from_attributes=True)

    items: list[T]
    next_cursor: str | None = None
    limit: int


class PlaceListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    category: PlaceCategory
    location: GeoPoint
    address: str | None = None
    phone: str | None = None
    website: str | None = None
    opening_hours: str | None = None
    source: PlaceSource
    source_id: str | None = None
    verified_at: datetime | None = None
    distance_meters: float | None = None


class PlaceListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    categories: list[PlaceCategory] | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    radius_meters: int | None = Field(default=None, ge=1)
    bbox: str | None = None
    limit: int = Field(default=100, ge=1, le=200)

    @model_validator(mode="after")
    def _validate_geo(self) -> "PlaceListQuery":
        if self.radius_meters is not None and (self.latitude is None or self.longitude is None):
            raise ValueError("Nearby places require latitude and longitude.")
        return self


def to_place_list_response(
    items: list[PlaceSummary],
    *,
    next_cursor: str | None,
    limit: int,
) -> GenericListResponse[PlaceListItem]:
    return GenericListResponse[PlaceListItem](
        items=[PlaceListItem.model_validate(item, from_attributes=True) for item in items],
        next_cursor=next_cursor,
        limit=limit,
    )
