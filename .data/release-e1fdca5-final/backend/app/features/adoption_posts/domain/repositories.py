from __future__ import annotations

from typing import Protocol
from uuid import UUID

from app.features.adoption_posts.domain.models import (
    AdoptionPostCreateDraft,
    AdoptionPostPage,
    AdoptionPostRecord,
)


class AdoptionPostRepository(Protocol):
    def create(self, draft: AdoptionPostCreateDraft) -> AdoptionPostRecord: ...

    def get_by_id(self, adoption_post_id: UUID) -> AdoptionPostRecord | None: ...

    def list_public(
        self,
        *,
        limit: int,
        cursor: str | None = None,
    ) -> AdoptionPostPage: ...
