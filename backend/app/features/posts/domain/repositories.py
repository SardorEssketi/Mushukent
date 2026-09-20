from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.cats.domain.models import CatStatus
from app.features.posts.domain.models import (
    CatObservationStats,
    PostDetailRecord,
    PostHistoryRecord,
    PostPage,
    PostSortOrder,
)


@dataclass(slots=True)
class PostPhotoDraft:
    id: UUID
    photo_url: str
    thumb_url: str | None
    position: int


@dataclass(slots=True)
class PostCreateDraft:
    id: UUID
    cat_id: UUID
    user_id: UUID | None
    photo_url: str
    thumb_url: str | None
    photos: list[PostPhotoDraft]
    description: str | None
    location_latitude: float | None
    location_longitude: float | None
    status: CatStatus | None
    is_public: bool


@dataclass(slots=True)
class PostUpdateDraft:
    description: str | None
    location_latitude: float | None
    location_longitude: float | None
    status: CatStatus | None
    is_public: bool
    photos: list[PostPhotoDraft] | None = None


class PostRepository(Protocol):
    def create(self, draft: PostCreateDraft) -> PostDetailRecord: ...

    def get_by_id(
        self,
        post_id: UUID,
        *,
        include_deleted: bool = False,
        viewer_user_id: UUID | None = None,
        for_update: bool = False,
    ) -> PostDetailRecord | None: ...

    def list_for_user(
        self,
        user_id: UUID,
        *,
        limit: int,
        cursor: str | None,
        sort: PostSortOrder,
        include_private: bool,
        require_visible_cat: bool,
        viewer_user_id: UUID | None = None,
    ) -> PostPage: ...

    def list_for_cat(
        self,
        cat_id: UUID,
        *,
        limit: int,
        cursor: str | None,
        sort: PostSortOrder,
        include_private: bool,
        require_visible_cat: bool,
        viewer_user_id: UUID | None = None,
    ) -> PostPage: ...

    def mark_deleted(
        self,
        post_id: UUID,
        *,
        deleted_at: datetime,
        deleted_by: UUID | None,
    ) -> bool: ...

    def update(self, post_id: UUID, draft: PostUpdateDraft) -> PostDetailRecord: ...

    def add_history(
        self,
        *,
        post_id: UUID,
        actor_id: UUID | None,
        action: str,
        before: dict[str, object],
        after: dict[str, object],
    ) -> None: ...

    def list_history(self, post_id: UUID) -> list[PostHistoryRecord]: ...

    def recalculate_cat_stats(self, cat_id: UUID) -> CatObservationStats: ...
