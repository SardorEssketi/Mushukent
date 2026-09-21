from __future__ import annotations

from datetime import datetime
from typing import Protocol
from uuid import UUID

from app.features.auth.domain.models import AuthRefreshSession, AuthUser


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

    def create_refresh_session(
        self,
        *,
        user_id: UUID,
        token_hash: str,
        expires_at: datetime,
    ) -> AuthRefreshSession: ...

    def get_refresh_session_by_hash(self, token_hash: str) -> AuthRefreshSession | None: ...

    def rotate_refresh_session(
        self,
        session_id: UUID,
        *,
        new_token_hash: str,
        expires_at: datetime,
        used_at: datetime,
    ) -> AuthRefreshSession | None: ...

    def revoke_refresh_session(self, token_hash: str, revoked_at: datetime) -> None: ...

    def revoke_user_refresh_sessions(self, user_id: UUID, revoked_at: datetime) -> None: ...
