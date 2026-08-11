from __future__ import annotations

from dataclasses import dataclass, field
from datetime import UTC, datetime
from uuid import UUID


@dataclass(slots=True)
class AuthUser:
    id: UUID
    email: str
    password_hash: str | None
    name: str | None = None
    avatar_url: str | None = None
    phone_number: str | None = None
    telegram_username: str | None = None
    preferred_language: str = "en"
    allow_public_activity_view: bool = True
    bio: str | None = None
    accepted_terms_version: str | None = None
    accepted_privacy_version: str | None = None
    accepted_legal_at: datetime | None = None
    email_verified: bool = False
    is_active: bool = True
    is_moderator: bool = False
    registered_at: datetime = field(default_factory=lambda: datetime.now(UTC))
    last_login_at: datetime | None = None
