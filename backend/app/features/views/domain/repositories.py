from __future__ import annotations

from typing import Protocol
from uuid import UUID


class PostViewRepository(Protocol):
    def record(
        self, post_kind: str, post_id: UUID, *, user_id: UUID | None, guest_key: str | None
    ) -> bool: ...

    def increment_view_count(self, post_kind: str, post_id: UUID) -> int: ...
