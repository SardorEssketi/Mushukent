from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.features.auth.domain.models import AuthUser

T = TypeVar("T")
CURRENT_TERMS_VERSION = "2026-08-01"
CURRENT_PRIVACY_VERSION = "2026-08-01"


class ApiSuccess(BaseModel, Generic[T]):
    success: bool = True
    data: T


class AuthRegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    name: str | None = Field(default=None, max_length=100)
    preferred_language: str = Field(default="en", pattern="^(en|uz|ru)$")
    accept_terms: bool = Field(default=False)
    accept_privacy: bool = Field(default=False)


class AuthLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class GoogleLoginRequest(BaseModel):
    id_token: str = Field(min_length=1)
    accept_terms: bool = Field(default=False)
    accept_privacy: bool = Field(default=False)


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
        )


class AuthLoginData(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int
    user: UserPublic


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
