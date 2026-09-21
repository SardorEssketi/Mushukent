from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.posts.domain.models import PostPage


class FeedRepository(Protocol):
    def list_feed(
        self,
        *,
        limit: int,
        cursor: str | None,
        filter_by: str,
        popular_period: str,
        viewer_user_id: UUID | None,
        viewer_is_moderator: bool,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
    ) -> PostPage: ...

    def mark_deleted(
        self,
        post_id: UUID,
        *,
        deleted_at: datetime,
        deleted_by: UUID | None,
    ) -> bool: ...
