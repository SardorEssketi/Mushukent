from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from typing import Protocol
from uuid import UUID


class Role(StrEnum):
    USER = "user"
    MODERATOR = "moderator"


@dataclass(frozen=True, slots=True)
class AuthenticatedPrincipal:
    user_id: UUID
    role: Role = Role.USER
    email: str | None = None
    is_active: bool = True


@dataclass(frozen=True, slots=True)
class GoogleIdTokenClaims:
    email: str | None
    iss: str
    aud: str
    exp: datetime
    sub: str | None = None
    name: str | None = None
    email_verified: bool = False
    raw: dict[str, object] | None = None

    @property
    def is_expired(self) -> bool:
        return self.exp <= datetime.now(UTC)


class PasswordHasher(Protocol):
    def hash_password(self, password: str) -> str: ...

    def verify_password(self, password: str, password_hash: str) -> bool: ...


class AccessTokenService(Protocol):
    def issue_access_token(self, principal: AuthenticatedPrincipal) -> str: ...

    def decode_access_token(self, token: str) -> AuthenticatedPrincipal: ...


class GoogleIdTokenVerifier(Protocol):
    def verify(self, id_token: str) -> GoogleIdTokenClaims: ...


class AuthenticationService(Protocol):
    """Authentication contract for the application layer."""

    def register(self, email: str, password: str, name: str | None = None): ...

    def authenticate_with_password(self, email: str, password: str): ...

    def authenticate_with_google_id_token(self, id_token: str): ...

    def resolve_bearer_token(self, token: str) -> AuthenticatedPrincipal: ...
