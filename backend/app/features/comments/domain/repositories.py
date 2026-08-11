from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.comments.domain.models import CommentOrder, CommentPage, CommentRecord
from app.features.posts.domain.models import PostDetailRecord


class CommentCreateDraft:
    def __init__(
        self,
        *,
        post_id: UUID | None,
        lost_pet_id: UUID | None = None,
        adoption_post_id: UUID | None = None,
        user_id: UUID,
        content: str,
    ) -> None:
        self.post_id = post_id
        self.lost_pet_id = lost_pet_id
        self.adoption_post_id = adoption_post_id
        self.user_id = user_id
        self.content = content


class CommentRepository(Protocol):
    def lock_visible_post(
        self,
        post_id: UUID,
        *,
        viewer_user_id: UUID | None,
    ) -> PostDetailRecord | None: ...

    def lost_pet_exists(self, lost_pet_id: UUID) -> bool: ...

    def adoption_post_exists(self, adoption_post_id: UUID) -> bool: ...

    def create(self, draft: CommentCreateDraft) -> CommentRecord: ...

    def get_by_id(
        self,
        comment_id: UUID,
        *,
        include_deleted: bool = False,
        for_update: bool = False,
    ) -> CommentRecord | None: ...

    def list_for_post(
        self,
        post_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> CommentPage: ...

    def list_for_lost_pet(
        self,
        lost_pet_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> CommentPage: ...

    def list_for_adoption_post(
        self,
        adoption_post_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> CommentPage: ...

    def list_for_user(
        self,
        user_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.DESC,
        include_private: bool,
    ) -> CommentPage: ...

    def mark_deleted(self, comment_id: UUID, *, deleted_at: datetime) -> bool: ...

    def increment_post_comment_count(self, post_id: UUID) -> None: ...

    def decrement_post_comment_count(self, post_id: UUID) -> None: ...

    def increment_lost_pet_comment_count(self, lost_pet_id: UUID) -> None: ...

    def decrement_lost_pet_comment_count(self, lost_pet_id: UUID) -> None: ...

    def increment_adoption_post_comment_count(self, adoption_post_id: UUID) -> None: ...

    def decrement_adoption_post_comment_count(self, adoption_post_id: UUID) -> None: ...
