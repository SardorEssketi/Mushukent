from __future__ import annotations

from typing import Protocol
from uuid import UUID

from app.features.posts.domain.models import PostDetailRecord


class LikeRepository(Protocol):
    def lock_visible_post(
        self,
        post_id: UUID,
        *,
        viewer_user_id: UUID | None,
    ) -> PostDetailRecord | None: ...

    def create_like(self, post_id: UUID, user_id: UUID) -> bool: ...

    def delete_like(self, post_id: UUID, user_id: UUID) -> bool: ...

    def increment_post_like_count(self, post_id: UUID) -> None: ...

    def decrement_post_like_count(self, post_id: UUID) -> None: ...
