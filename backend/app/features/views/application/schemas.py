from __future__ import annotations

from typing import Literal
from uuid import UUID

from pydantic import BaseModel, Field

PostKind = Literal["post", "lost_pet", "adoption"]

# The app sends at most 20; a small cap also limits what one request can add.
MAX_SEEN_BATCH = 20


class PostViewResponse(BaseModel):
    view_count: int
    counted: bool


class PostViewTarget(BaseModel):
    kind: PostKind
    id: UUID


class PostViewBatchRequest(BaseModel):
    items: list[PostViewTarget] = Field(min_length=1, max_length=MAX_SEEN_BATCH)


class PostViewBatchItem(BaseModel):
    kind: PostKind
    id: UUID
    view_count: int
    counted: bool


class PostViewBatchResponse(BaseModel):
    items: list[PostViewBatchItem]
