from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import AnyHttpUrl, BaseModel, ConfigDict, Field, field_validator, model_validator

from app.features.cats.domain.models import (
    CatDetailRecord,
    CatListFilter,
    CatRecord,
    CatStatus,
    CatSummary,
    GeoPoint,
    PostListItem,
)

T = TypeVar("T")


class GenericListResponse(BaseModel, Generic[T]):
    model_config = ConfigDict(from_attributes=True)

    items: list[T]
    next_cursor: str | None = None
    limit: int


class CatListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None = None
    status: CatStatus
    cover_photo_url: str | None = None
    canonical_location: GeoPoint | None = None
    last_seen_at: datetime | None = None
    total_observations: int = 0
    distance_meters: float | None = None


class PostAuthor(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID | None = None
    name: str | None = None
    avatar_url: str | None = None


class PostCatSummary(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None = None
    status: CatStatus
    cover_photo_url: str | None = None
    canonical_location: GeoPoint | None = None
    last_seen_at: datetime | None = None
    total_observations: int = 0
    distance_meters: float | None = None


class PostListItemResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    cat: PostCatSummary
    author: PostAuthor | None = None
    photo_url: str
    thumb_url: str | None = None
    description: str | None = None
    location: GeoPoint | None = None
    created_at: datetime
    like_count: int = 0
    comment_count: int = 0


class CatResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None = None
    status: CatStatus
    cover_photo_url: str | None = None
    canonical_location: GeoPoint | None = None
    created_at: datetime | None = None


class CatDetailResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None = None
    status: CatStatus
    cover_photo_url: str | None = None
    first_seen_at: datetime | None = None
    last_seen_at: datetime | None = None
    total_observations: int = 0
    total_contributors: int = 0
    total_likes: int = 0
    observation_history: GenericListResponse[PostListItemResponse]


class CatCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str | None = Field(default=None, max_length=100)
    status: CatStatus = CatStatus.UNKNOWN
    approximate_age_smallyears: int | None = Field(default=None, ge=0, le=60)
    cover_photo_url: AnyHttpUrl | None = None
    canonical_location: GeoPoint | None = None

    @field_validator("canonical_location")
    @classmethod
    def _validate_location(cls, value: GeoPoint | None) -> GeoPoint | None:
        if value is None:
            return value
        latitude = getattr(value, "latitude", None)
        longitude = getattr(value, "longitude", None)
        if latitude is None or longitude is None:
            raise ValueError("Invalid canonical_location coordinates.")
        if not -90 <= float(latitude) <= 90 or not -180 <= float(longitude) <= 180:
            raise ValueError("Invalid canonical_location coordinates.")
        return value

    @field_validator("status")
    @classmethod
    def _validate_status(cls, value: CatStatus) -> CatStatus:
        if value == CatStatus.FEED:
            raise ValueError("Feed is not a valid cat status.")
        return value

    @model_validator(mode="after")
    def _normalize_name(self) -> "CatCreateRequest":
        if self.name is not None and not self.name.strip():
            raise ValueError("Cat name must not be blank.")
        return self


class CatUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str | None = Field(default=None, max_length=100)
    status: CatStatus | None = None
    approximate_age_smallyears: int | None = Field(default=None, ge=0, le=60)
    cover_photo_url: AnyHttpUrl | None = None
    canonical_location: GeoPoint | None = None
    merged_into: UUID | None = None

    @field_validator("canonical_location")
    @classmethod
    def _validate_location(cls, value: GeoPoint | None) -> GeoPoint | None:
        if value is None:
            return value
        latitude = getattr(value, "latitude", None)
        longitude = getattr(value, "longitude", None)
        if latitude is None or longitude is None:
            raise ValueError("Invalid canonical_location coordinates.")
        if not -90 <= float(latitude) <= 90 or not -180 <= float(longitude) <= 180:
            raise ValueError("Invalid canonical_location coordinates.")
        return value

    @field_validator("status")
    @classmethod
    def _validate_status(cls, value: CatStatus | None) -> CatStatus | None:
        if value == CatStatus.FEED:
            raise ValueError("Feed is not a valid cat status.")
        return value

    @model_validator(mode="after")
    def _validate_update(self) -> "CatUpdateRequest":
        if (
            self.name is None
            and self.status is None
            and self.approximate_age_smallyears is None
            and self.cover_photo_url is None
            and self.canonical_location is None
            and self.merged_into is None
        ):
            raise ValueError("At least one cat field must be provided.")
        if self.name is not None and not self.name.strip():
            raise ValueError("Cat name must not be blank.")
        return self


class CatListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    filter_by: CatListFilter = CatListFilter.RECENTLY_ADDED
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, le=180)
    radius_meters: int | None = Field(default=None, ge=1)
    bbox: str | None = None
    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None

    @model_validator(mode="after")
    def _validate_geo(self) -> "CatListQuery":
        if self.filter_by == CatListFilter.NEARBY:
            if self.latitude is None or self.longitude is None or self.radius_meters is None:
                raise ValueError("Nearby filter requires latitude, longitude and radius_meters.")
        if self.radius_meters is not None and self.radius_meters <= 0:
            raise ValueError("radius_meters must be positive.")
        return self


def to_cat_response(cat: CatRecord) -> CatResponse:
    return CatResponse.model_validate(cat, from_attributes=True)


def to_cat_detail_response(
    cat: CatDetailRecord,
    *,
    history: list[PostListItem],
    next_cursor: str | None,
    limit: int,
) -> CatDetailResponse:
    observation_history = GenericListResponse[PostListItemResponse](
        items=[PostListItemResponse.model_validate(item, from_attributes=True) for item in history],
        next_cursor=next_cursor,
        limit=limit,
    )
    return CatDetailResponse.model_validate(
        {
            "id": cat.id,
            "name": cat.name,
            "status": cat.status,
            "cover_photo_url": cat.cover_photo_url,
            "first_seen_at": cat.first_seen_at,
            "last_seen_at": cat.last_seen_at,
            "total_observations": cat.total_observations,
            "total_contributors": cat.total_contributors,
            "total_likes": cat.total_likes,
            "observation_history": observation_history,
        }
    )


def to_cat_list_response(
    items: list[CatSummary],
    *,
    next_cursor: str | None,
    limit: int,
) -> GenericListResponse[CatListItem]:
    return GenericListResponse[CatListItem](
        items=[CatListItem.model_validate(item, from_attributes=True) for item in items],
        next_cursor=next_cursor,
        limit=limit,
    )


CatCreate = CatCreateRequest
CatUpdate = CatUpdateRequest
