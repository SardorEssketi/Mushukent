from __future__ import annotations

from typing import Protocol
from uuid import UUID

from app.features.auth.domain.models import AuthUser


class UserProfileRepository(Protocol):
    def get_by_id(self, user_id: UUID) -> AuthUser | None: ...

    def save(self, user: AuthUser) -> AuthUser: ...

    def count_observations(self, user_id: UUID) -> int: ...

    def count_likes_received(self, user_id: UUID) -> int: ...

    def count_comments(self, user_id: UUID) -> int: ...
