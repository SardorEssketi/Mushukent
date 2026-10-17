from __future__ import annotations

import re
from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.features.adoption_posts.domain.models import AdoptionPostPage, AdoptionPostRecord
from app.features.posts.application.schemas import GenericListResponse, PostAuthor


class AdoptionPostCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    pet_name: str = Field(min_length=1, max_length=100)
    additional_info: str | None = Field(default=None, max_length=2000)
    # Explicit agreement to the contact-visibility wording. None = an older client that has no
    # checkbox.
    owner_contact_consent: bool | None = None


class AdoptionPostUpdateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    pet_name: str | None = Field(default=None, min_length=1, max_length=100)
    additional_info: str | None = Field(default=None, max_length=2000)
    owner_phone_number: str | None = Field(default=None, max_length=32)
    owner_telegram_username: str | None = Field(default=None, max_length=32)

    @field_validator("owner_telegram_username")
    @classmethod
    def _validate_telegram(cls, value: str | None) -> str | None:
        if value and not re.fullmatch(r"@?[A-Za-z0-9_]{5,32}", value):
            raise ValueError("Invalid Telegram username.")
        return value

    @model_validator(mode="after")
    def _validate_explicit_values(self) -> "AdoptionPostUpdateRequest":
        if "pet_name" in self.model_fields_set and not self.pet_name:
            raise ValueError("pet_name must be provided.")
        if "owner_phone_number" in self.model_fields_set and not self.owner_phone_number:
            raise ValueError("owner_phone_number must be provided.")
        return self


class AdoptionFollowUpItem(BaseModel):
    id: UUID
    adoption_post_id: UUID
    pet_name: str
    due_at: datetime


class AdoptionFollowUpAnswer(BaseModel):
    model_config = ConfigDict(extra="forbid")

    answer: Literal["yes", "no"]


class AdoptionResolutionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    is_resolved: bool


class AdoptionPostListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    item_type: str = "adoption"
    id: UUID
    author: PostAuthor | None = None
    pet_name: str
    # Contact details are only included on the detail endpoint for signed-in viewers (see
    # docs/CONTACT_PRIVACY.md); list, feed and anonymous responses carry `contact_available`.
    owner_phone_number: str | None = None
    owner_telegram_username: str | None = None
    owner_phone_publication_consent: bool
    contact_available: bool = False
    photo_url: str
    thumb_url: str | None = None
    photo_urls: list[str]
    additional_info: str | None = None
    is_public: bool = True
    is_resolved: bool = False
    comment_count: int = 0
    created_at: datetime


class AdoptionPostResponse(AdoptionPostListItem):
    owner_phone_number: str | None


def contact_is_available(item: AdoptionPostRecord) -> bool:
    return (
        not item.is_resolved
        and item.user_id is not None
        and bool(item.owner_phone_number)
        and item.owner_phone_number != "[deleted]"
    )


def to_adoption_post_response(
    item: AdoptionPostRecord, *, include_contact: bool = True
) -> AdoptionPostResponse:
    response = AdoptionPostResponse.model_validate(item, from_attributes=True)
    update: dict[str, object] = {"contact_available": contact_is_available(item)}
    if not include_contact:
        update.update(owner_phone_number=None, owner_telegram_username=None)
    return response.model_copy(update=update)


def to_adoption_post_list_item(item: AdoptionPostRecord) -> AdoptionPostListItem:
    """List/feed representation: never carries phone or Telegram, only `contact_available`."""
    return AdoptionPostListItem.model_validate(item, from_attributes=True).model_copy(
        update={
            "owner_phone_number": None,
            "owner_telegram_username": None,
            "contact_available": contact_is_available(item),
        }
    )


def to_adoption_post_page_response(
    page: AdoptionPostPage,
) -> GenericListResponse[AdoptionPostListItem]:
    return GenericListResponse[AdoptionPostListItem](
        items=[to_adoption_post_list_item(item) for item in page.items],
        next_cursor=page.next_cursor,
        limit=page.limit,
    )
