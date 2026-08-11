from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.auth.domain.models import AuthUser


class AuthUserRepository(Protocol):
    def get_by_id(self, user_id: UUID) -> AuthUser | None: ...

    def get_by_email(self, email: str) -> AuthUser | None: ...

    def create(
        self,
        *,
        email: str,
        password_hash: str | None,
        name: str | None = None,
        preferred_language: str = "en",
        email_verified: bool = False,
        is_moderator: bool = False,
        accepted_terms_version: str | None = None,
        accepted_privacy_version: str | None = None,
        accepted_legal_at: datetime | None = None,
    ) -> AuthUser: ...

    def save(self, user: AuthUser) -> AuthUser: ...

    def update_last_login_at(self, user_id: UUID, last_login_at: datetime) -> AuthUser | None: ...

    def mark_email_verified(self, user_id: UUID) -> AuthUser | None: ...
