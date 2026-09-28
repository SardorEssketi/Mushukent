from __future__ import annotations

import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.features.cats.domain.models import GeoPoint
from app.features.lost_pets.domain.models import LostPetMapPage, LostPetPage, LostPetRecord
from app.features.posts.application.schemas import GenericListResponse, PostAuthor


class LostPetCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    last_seen_location: GeoPoint
    pet_name: str = Field(min_length=1, max_length=100)
    additional_info: str | None = Field(default=None, max_length=2000)
    owner_phone_publication_consent: bool = False

    @field_validator("last_seen_location")
    @classmethod
    def _validate_last_seen_location(cls, value: GeoPoint) -> GeoPoint:
        if not -90 <= float(value.latitude) <= 90 or not -180 <= float(value.longitude) <= 180:
            raise ValueError("Invalid last_seen_location coordinates.")
        return value


class LostPetUpdateRequest(BaseModel):
    """Mutable public Lost Pet fields; ownership and resolution stay internal."""

    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    last_seen_location: GeoPoint | None = None
    pet_name: str | None = Field(default=None, min_length=1, max_length=100)
    additional_info: str | None = Field(default=None, max_length=2000)
    owner_phone_number: str | None = Field(default=None, max_length=32)
    owner_telegram_username: str | None = Field(default=None, max_length=32)

    @field_validator("last_seen_location")
    @classmethod
    def _validate_last_seen_location(cls, value: GeoPoint | None) -> GeoPoint | None:
        if value is not None and (
            not -90 <= float(value.latitude) <= 90
            or not -180 <= float(value.longitude) <= 180
        ):
            raise ValueError("Invalid last_seen_location coordinates.")
        return value

    @field_validator("owner_telegram_username")
    @classmethod
    def _validate_telegram_username(cls, value: str | None) -> str | None:
        if value is not None and value and not re.fullmatch(r"[A-Za-z0-9_]{5,32}", value):
            raise ValueError("Invalid Telegram username.")
        return value

    @model_validator(mode="after")
    def _validate_explicit_values(self) -> "LostPetUpdateRequest":
        if "last_seen_location" in self.model_fields_set and self.last_seen_location is None:
            raise ValueError("last_seen_location must be provided.")
        if "owner_phone_number" in self.model_fields_set and not self.owner_phone_number:
            raise ValueError("owner_phone_number must not be empty.")
        return self


class LostPetListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    item_type: str = "lost_pet"
    id: UUID
    author: PostAuthor | None = None
    pet_name: str
    owner_phone_number: str
    owner_telegram_username: str | None = None
    owner_phone_publication_consent: bool
    photo_url: str
    thumb_url: str | None = None
    photo_urls: list[str]
    last_seen_location: GeoPoint
    additional_info: str | None = None
    is_resolved: bool = False
    comment_count: int = 0
    created_at: datetime


class LostPetResponse(LostPetListItem):
    pass


class LostPetMapListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    item_type: str = "lost_pet"
    id: UUID
    pet_name: str
    last_seen_location: GeoPoint
    is_resolved: bool = False
    created_at: datetime


class LostPetFollowUpItem(BaseModel):
    id: UUID
    lost_pet_id: UUID
    pet_name: str
    due_at: datetime


class LostPetFollowUpAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answer: Literal["yes", "no"]


def to_lost_pet_response(item: LostPetRecord) -> LostPetResponse:
    return LostPetResponse.model_validate(item, from_attributes=True)


def to_lost_pet_page_response(page: LostPetPage) -> GenericListResponse[LostPetListItem]:
    return GenericListResponse[LostPetListItem](
        items=[LostPetListItem.model_validate(item, from_attributes=True) for item in page.items],
        next_cursor=page.next_cursor,
        limit=page.limit,
    )


def to_lost_pet_map_page_response(
    page: LostPetMapPage,
) -> GenericListResponse[LostPetMapListItem]:
    return GenericListResponse[LostPetMapListItem](
        items=[
            LostPetMapListItem.model_validate(item, from_attributes=True) for item in page.items
        ],
        next_cursor=None,
        limit=page.limit,
    )
