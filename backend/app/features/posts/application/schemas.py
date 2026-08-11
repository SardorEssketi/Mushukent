from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import AnyHttpUrl, BaseModel, ConfigDict, Field, field_validator, model_validator

from app.features.cats.domain.models import CatStatus, GeoPoint
from app.features.posts.domain.models import (
    PostDetailRecord,
    PostPage,
    PostRecord,
    PostSortOrder,
)

T = TypeVar("T")


class GenericListResponse(BaseModel, Generic[T]):
    model_config = ConfigDict(from_attributes=True)

    items: list[T]
    next_cursor: str | None = None
    limit: int


class PostAuthor(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID | None = None
    name: str | None = None
    avatar_url: str | None = None


class PostCat(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None = None
    cover_photo_url: str | None = None
    status: CatStatus = CatStatus.UNKNOWN


class PostListItem(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    item_type: str = "observation"
    id: UUID
    cat: PostCat
    author: PostAuthor | None = None
    photo_url: str
    thumb_url: str | None = None
    photo_urls: list[str] = Field(default_factory=list)
    description: str | None = None
    status: CatStatus | None = None
    location: GeoPoint | None = None
    created_at: datetime
    like_count: int = 0
    comment_count: int = 0


class PostResponse(PostListItem):
    is_liked_by_me: bool = False


class PostNewCat(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str | None = Field(default=None, max_length=100)
    status: CatStatus = CatStatus.UNKNOWN
    canonical_location: GeoPoint | None = None

    @model_validator(mode="after")
    def _validate_name(self) -> "PostNewCat":
        if self.name is not None and not self.name.strip():
            raise ValueError("Cat name must not be blank.")
        return self

    @field_validator("canonical_location")
    @classmethod
    def _validate_canonical_location(cls, value: GeoPoint | None) -> GeoPoint | None:
        if value is None:
            return value
        if not -90 <= float(value.latitude) <= 90 or not -180 <= float(value.longitude) <= 180:
            raise ValueError("Invalid canonical_location coordinates.")
        return value

    @field_validator("status")
    @classmethod
    def _validate_status(cls, value: CatStatus) -> CatStatus:
        if value == CatStatus.FEED:
            raise ValueError("Feed is not a valid cat status.")
        return value


class _PostCreateBase(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    cat_id: UUID | None = None
    new_cat: PostNewCat | None = None
    description: str | None = Field(default=None, max_length=2000)
    status: CatStatus | None = None
    location: GeoPoint | None = None
    is_public: bool = True
    photo_url: AnyHttpUrl | None = None

    @model_validator(mode="after")
    def _validate_payload(self) -> "_PostCreateBase":
        if self.cat_id is None and self.new_cat is None:
            raise ValueError("Either cat_id or new_cat must be provided.")
        if self.cat_id is not None and self.new_cat is not None:
            raise ValueError("Provide either cat_id or new_cat, not both.")
        return self

    @field_validator("location")
    @classmethod
    def _validate_location(cls, value: GeoPoint | None) -> GeoPoint | None:
        if value is None:
            return value
        if not -90 <= float(value.latitude) <= 90 or not -180 <= float(value.longitude) <= 180:
            raise ValueError("Invalid location coordinates.")
        return value

    @field_validator("status")
    @classmethod
    def _validate_status(cls, value: CatStatus | None) -> CatStatus | None:
        if value == CatStatus.FEED:
            raise ValueError("Feed is not a valid cat status.")
        return value


class PostCreateJSONRequest(_PostCreateBase):
    photo_url: AnyHttpUrl


class PostCreateMultipartRequest(_PostCreateBase):
    photo_url: AnyHttpUrl | None = None


class PostListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None
    sort: PostSortOrder = PostSortOrder.LATEST


def to_post_response(post: PostDetailRecord) -> PostResponse:
    return PostResponse.model_validate(post, from_attributes=True)


def to_post_list_response(
    items: list[PostRecord],
    *,
    next_cursor: str | None,
    limit: int,
) -> GenericListResponse[PostListItem]:
    return GenericListResponse[PostListItem](
        items=[PostListItem.model_validate(item, from_attributes=True) for item in items],
        next_cursor=next_cursor,
        limit=limit,
    )


def to_post_page_response(page: PostPage) -> GenericListResponse[PostListItem]:
    return to_post_list_response(page.items, next_cursor=page.next_cursor, limit=page.limit)
