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
    bio: str | None = None
    email_verified: bool = False
    is_active: bool = True
    is_moderator: bool = False
    registered_at: datetime = field(default_factory=lambda: datetime.now(UTC))
    last_login_at: datetime | None = None
