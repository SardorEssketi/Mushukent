from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

from app.features.cats.domain.models import GeoPoint
from app.features.lost_pets.domain.models import LostPetPage, LostPetRecord
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


def to_lost_pet_response(item: LostPetRecord) -> LostPetResponse:
    return LostPetResponse.model_validate(item, from_attributes=True)


def to_lost_pet_page_response(page: LostPetPage) -> GenericListResponse[LostPetListItem]:
    return GenericListResponse[LostPetListItem](
        items=[LostPetListItem.model_validate(item, from_attributes=True) for item in page.items],
        next_cursor=page.next_cursor,
        limit=page.limit,
    )
