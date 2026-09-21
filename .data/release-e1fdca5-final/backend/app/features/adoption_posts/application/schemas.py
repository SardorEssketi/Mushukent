from __future__ import annotations

from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.features.adoption_posts.domain.models import AdoptionPostPage, AdoptionPostRecord
from app.features.posts.application.schemas import GenericListResponse, PostAuthor


class AdoptionPostCreateRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    pet_name: str = Field(min_length=1, max_length=100)
    additional_info: str | None = Field(default=None, max_length=2000)
    owner_phone_publication_consent: bool = False


class AdoptionPostListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    item_type: str = "adoption"
    id: UUID
    author: PostAuthor | None = None
    pet_name: str
    owner_phone_number: str
    owner_telegram_username: str | None = None
    owner_phone_publication_consent: bool
    photo_url: str
    thumb_url: str | None = None
    photo_urls: list[str]
    additional_info: str | None = None
    is_public: bool = True
    comment_count: int = 0
    created_at: datetime


class AdoptionPostResponse(AdoptionPostListItem):
    pass


def to_adoption_post_response(item: AdoptionPostRecord) -> AdoptionPostResponse:
    return AdoptionPostResponse.model_validate(item, from_attributes=True)


def to_adoption_post_page_response(
    page: AdoptionPostPage,
) -> GenericListResponse[AdoptionPostListItem]:
    return GenericListResponse[AdoptionPostListItem](
        items=[
            AdoptionPostListItem.model_validate(item, from_attributes=True) for item in page.items
        ],
        next_cursor=page.next_cursor,
        limit=page.limit,
    )
