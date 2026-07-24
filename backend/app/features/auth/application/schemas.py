from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field

from app.features.auth.domain.models import AuthUser

T = TypeVar("T")


class ApiSuccess(BaseModel, Generic[T]):
    success: bool = True
    data: T


class AuthRegisterRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)
    name: str | None = Field(default=None, max_length=100)


class AuthLoginRequest(BaseModel):
    email: EmailStr
    password: str = Field(min_length=8, max_length=128)


class GoogleLoginRequest(BaseModel):
    id_token: str = Field(min_length=1)


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    name: str | None = None
    avatar_url: str | None = None
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
            bio=user.bio,
            registered_at=user.registered_at,
        )


class AuthLoginData(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    expires_in: int
    user: UserPublic


class GoogleLoginResponseData(AuthLoginData):
    pass


class LogoutResponse(BaseModel):
    success: bool = True


AuthRegister = AuthRegisterRequest
AuthLogin = AuthLoginRequest
AuthLoginResponse = ApiSuccess[AuthLoginData]
GoogleLoginResponse = ApiSuccess[GoogleLoginResponseData]
UserProfile = UserPublic
