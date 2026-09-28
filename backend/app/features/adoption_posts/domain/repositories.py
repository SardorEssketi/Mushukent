from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.adoption_posts.domain.models import (
    AdoptionFollowUpRecord,
    AdoptionPostCreateDraft,
    AdoptionPostPage,
    AdoptionPostRecord,
    AdoptionPostUpdateDraft,
)


class AdoptionPostRepository(Protocol):
    def create(self, draft: AdoptionPostCreateDraft) -> AdoptionPostRecord: ...

    def get_by_id(
        self, adoption_post_id: UUID, *, for_update: bool = False, include_deleted: bool = False
    ) -> AdoptionPostRecord | None: ...

    def get_by_ids(
        self, adoption_post_ids: list[UUID], *, active_only: bool = False
    ) -> list[AdoptionPostRecord]: ...

    def update(
        self, adoption_post_id: UUID, draft: AdoptionPostUpdateDraft
    ) -> AdoptionPostRecord: ...

    def soft_delete(self, adoption_post_id: UUID, deleted_at: datetime) -> None: ...

    def record_contact(self, adoption_post_id: UUID, contacting_user_id: UUID) -> bool: ...

    def list_due_follow_ups(
        self, owner_id: UUID, now: datetime
    ) -> list[AdoptionFollowUpRecord]: ...

    def answer_follow_up(
        self, follow_up_id: UUID, owner_id: UUID, answer_yes: bool, now: datetime
    ) -> tuple[str, UUID | None]: ...

    def list_owned(
        self, owner_id: UUID, *, limit: int, cursor: str | None = None
    ) -> AdoptionPostPage: ...

    def list_public(
        self,
        *,
        limit: int,
        cursor: str | None = None,
    ) -> AdoptionPostPage: ...
