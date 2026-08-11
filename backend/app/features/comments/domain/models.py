from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID


class CommentOrder(StrEnum):
    ASC = "asc"
    DESC = "desc"


@dataclass(slots=True)
class CommentUserSummary:
    id: UUID | None
    name: str | None


@dataclass(slots=True)
class CommentRecord:
    id: UUID
    post_id: UUID | None
    lost_pet_id: UUID | None
    adoption_post_id: UUID | None
    user_id: UUID | None
    content: str
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    user: CommentUserSummary | None


@dataclass(slots=True)
class CommentPage:
    items: list[CommentRecord]
    next_cursor: str | None
    limit: int
