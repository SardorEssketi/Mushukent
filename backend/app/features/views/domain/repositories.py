from __future__ import annotations

from typing import Protocol
from uuid import UUID


class PostViewRepository(Protocol):
    def record(
        self, post_kind: str, post_id: UUID, *, user_id: UUID | None, guest_key: str | None
    ) -> bool: ...

    def increment_view_count(self, post_kind: str, post_id: UUID) -> int: ...

    def visible_targets(
        self,
        post_kind: str,
        post_ids: list[UUID],
        *,
        viewer_user_id: UUID | None,
        viewer_is_moderator: bool,
    ) -> dict[UUID, tuple[UUID | None, int]]: ...

    def record_many(
        self, targets: list[tuple[str, UUID]], *, user_id: UUID | None, guest_key: str | None
    ) -> set[tuple[str, UUID]]: ...

    def increment_view_counts(self, post_kind: str, post_ids: list[UUID]) -> dict[UUID, int]: ...
