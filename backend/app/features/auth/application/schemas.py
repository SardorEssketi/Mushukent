from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator

from app.features.auth.domain.models import AuthUser

T = TypeVar("T")
# Must equal the "Version:" of docs/legal/TERMS_OF_SERVICE.md and PRIVACY_POLICY.md (guarded by
# tests/test_legal_consistency.py). Changing them asks returning users to accept again.
CURRENT_TERMS_VERSION = "2026-10-15"
CURRENT_PRIVACY_VERSION = "2026-10-15"


class ApiSuccess(BaseModel, Generic[T]):
    success: bool = True
    data: T


class AuthRegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    name: str = Field(min_length=1, max_length=100)
    preferred_language: str = Field(default="en", pattern="^(en|uz|ru)$")
    accept_terms: bool = Field(default=False)
    accept_privacy: bool = Field(default=False)

    @field_validator("name")
    @classmethod
    def _validate_name(cls, value: str) -> str:
        name = value.strip()
        if not name:
            raise ValueError("Name is required.")
        return name


class AuthLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class GoogleLoginRequest(BaseModel):
    id_token: str = Field(min_length=1)
    password: str | None = Field(default=None, min_length=1, max_length=128)
    accept_terms: bool = Field(default=False)
    accept_privacy: bool = Field(default=False)


class LegalAcceptRequest(BaseModel):
    """Explicit acceptance of the documents the user was shown (identified by version)."""

    model_config = ConfigDict(extra="forbid")

    accept_terms: bool
    accept_privacy: bool
    terms_version: str = Field(min_length=1, max_length=32)
    privacy_version: str = Field(min_length=1, max_length=32)


def legal_acceptance_required(user: AuthUser) -> bool:
    return not (
        user.accepted_terms_version == CURRENT_TERMS_VERSION
        and user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
        and user.accepted_legal_at is not None
    )


class SignInMethods(BaseModel):
    has_password: bool
    google_connected: bool
    email_verified: bool


class _NewPasswordFields(BaseModel):
    model_config = ConfigDict(extra="forbid")

    new_password: str = Field(min_length=8, max_length=128)
    confirm_password: str = Field(min_length=8, max_length=128)


class ChangePasswordRequest(_NewPasswordFields):
    current_password: str = Field(min_length=1, max_length=128)


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    name: str | None = None
    avatar_url: str | None = None
    telegram_username: str | None = None
    preferred_language: str = "en"
    allow_public_activity_view: bool = True
    bio: str | None = None
    registered_at: datetime
    observation_count: int | None = None
    total_likes_received: int | None = None
    comment_count: int | None = None
    is_moderator: bool = False
    # True until the user has explicitly accepted the current Terms and Privacy Policy.
    legal_acceptance_required: bool = False
    current_terms_version: str = CURRENT_TERMS_VERSION
    current_privacy_version: str = CURRENT_PRIVACY_VERSION

    @classmethod
    def from_auth_user(cls, user: AuthUser) -> "UserPublic":
        return cls(
            id=user.id,
            email=user.email,
            name=user.name,
            avatar_url=user.avatar_url,
            telegram_username=user.telegram_username,
            preferred_language=user.preferred_language,
            allow_public_activity_view=user.allow_public_activity_view,
            bio=user.bio,
            registered_at=user.registered_at,
            is_moderator=user.is_moderator,
            legal_acceptance_required=legal_acceptance_required(user),
        )


class AuthLoginData(BaseModel):
    access_token: str
    refresh_token: str | None = None
    token_type: str = "Bearer"
    expires_in: int
    user: UserPublic


class RefreshTokenRequest(BaseModel):
    refresh_token: str = Field(min_length=1)


class LogoutRequest(BaseModel):
    refresh_token: str | None = Field(default=None)


class VerificationTokenData(BaseModel):
    verification_required: bool = True
    email: EmailStr
    dev_verification_token: str | None = None


class VerifyEmailRequest(BaseModel):
    token: str = Field(min_length=1)


class ResendVerificationRequest(BaseModel):
    email: EmailStr


class VerifyEmailData(BaseModel):
    verified: bool = True
    email: EmailStr


class GoogleLoginResponseData(AuthLoginData):
    pass


class LogoutResponse(BaseModel):
    success: bool = True


AuthRegister = AuthRegisterRequest
AuthLogin = AuthLoginRequest
AuthLoginResponse = ApiSuccess[AuthLoginData]
GoogleLoginResponse = ApiSuccess[GoogleLoginResponseData]
UserProfile = UserPublic
AuthRegisterResponse = ApiSuccess[VerificationTokenData]
ResendVerificationResponse = ApiSuccess[VerificationTokenData]
VerifyEmailResponse = ApiSuccess[VerifyEmailData]
