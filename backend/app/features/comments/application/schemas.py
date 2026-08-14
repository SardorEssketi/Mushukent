from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.features.comments.domain.models import CommentOrder, CommentPage, CommentRecord

T = TypeVar("T")


class GenericListResponse(BaseModel, Generic[T]):
    model_config = ConfigDict(from_attributes=True)

    items: list[T]
    next_cursor: str | None = None
    limit: int


class CommentUser(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID | None = None
    name: str | None = None
    avatar_url: str | None = None


class CommentCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    content: str = Field(min_length=1, max_length=1000)

    @model_validator(mode="after")
    def _validate_content(self) -> "CommentCreate":
        if not self.content.strip():
            raise ValueError("Comment content must not be blank.")
        return self


class CommentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    post_id: UUID | None = None
    lost_pet_id: UUID | None = None
    adoption_post_id: UUID | None = None
    user: CommentUser | None = None
    content: str
    created_at: datetime


class CommentListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None
    order: CommentOrder = CommentOrder.ASC


def to_comment_response(comment: CommentRecord) -> CommentResponse:
    return CommentResponse.model_validate(comment, from_attributes=True)


def to_comment_page_response(page: CommentPage) -> GenericListResponse[CommentResponse]:
    return GenericListResponse[CommentResponse](
        items=[CommentResponse.model_validate(item, from_attributes=True) for item in page.items],
        next_cursor=page.next_cursor,
        limit=page.limit,
    )
