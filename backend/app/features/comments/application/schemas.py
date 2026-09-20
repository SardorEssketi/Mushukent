from __future__ import annotations

from datetime import datetime, timedelta
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
    parent_comment_id: UUID | None = None

    @model_validator(mode="after")
    def _validate_content(self) -> "CommentCreate":
        if not self.content.strip():
            raise ValueError("Comment content must not be blank.")
        return self


class CommentUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    content: str = Field(min_length=1, max_length=1000)

    @model_validator(mode="after")
    def _validate_content(self) -> "CommentUpdate":
        if not self.content.strip():
            raise ValueError("Comment content must not be blank.")
        return self


class CommentResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    post_id: UUID | None = None
    lost_pet_id: UUID | None = None
    adoption_post_id: UUID | None = None
    parent_comment_id: UUID | None = None
    user: CommentUser | None = None
    content: str
    created_at: datetime
    edited_at: datetime | None = None
    edit_until: datetime


class CommentListQuery(BaseModel):
    model_config = ConfigDict(extra="forbid")

    limit: int = Field(default=20, ge=1, le=100)
    cursor: str | None = None
    order: CommentOrder = CommentOrder.ASC


def to_comment_response(
    comment: CommentRecord,
    *,
    edit_window_minutes: int,
) -> CommentResponse:
    return CommentResponse(
        id=comment.id,
        post_id=comment.post_id,
        lost_pet_id=comment.lost_pet_id,
        adoption_post_id=comment.adoption_post_id,
        parent_comment_id=comment.parent_comment_id,
        user=(
            CommentUser.model_validate(comment.user, from_attributes=True)
            if comment.user is not None
            else None
        ),
        content=comment.content,
        created_at=comment.created_at,
        edited_at=comment.edited_at,
        edit_until=comment.created_at + timedelta(minutes=edit_window_minutes),
    )


def to_comment_page_response(
    page: CommentPage,
    *,
    edit_window_minutes: int,
) -> GenericListResponse[CommentResponse]:
    return GenericListResponse[CommentResponse](
        items=[
            to_comment_response(item, edit_window_minutes=edit_window_minutes)
            for item in page.items
        ],
        next_cursor=page.next_cursor,
        limit=page.limit,
    )
