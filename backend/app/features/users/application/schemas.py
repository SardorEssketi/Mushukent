from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import (
    AnyHttpUrl,
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
    model_validator,
)

T = TypeVar("T")


class ApiSuccess(BaseModel, Generic[T]):
    success: bool = True
    data: T


class UserProfile(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: EmailStr
    name: str | None = None
    avatar_url: str | None = None
    phone_number: str | None = None
    telegram_username: str | None = None
    preferred_language: str = "en"
    allow_public_activity_view: bool = True
    bio: str | None = None
    registered_at: datetime
    observation_count: int = 0
    total_likes_received: int = 0
    comment_count: int = 0


class UserPublic(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str | None = None
    avatar_url: str | None = None
    registered_at: datetime
    observation_count: int = 0
    comment_count: int = 0
    allow_public_activity_view: bool = True


class UserUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str | None = Field(default=None, max_length=100)
    bio: str | None = Field(default=None, max_length=1000)
    phone_number: str | None = Field(default=None, max_length=32)
    telegram_username: str | None = Field(
        default=None, max_length=32, pattern=r"^[A-Za-z0-9_]{5,32}$|^$"
    )
    preferred_language: str | None = Field(default=None, pattern="^(en|uz|ru)$")
    allow_public_activity_view: bool | None = None
    avatar_url: AnyHttpUrl | None = None

    @model_validator(mode="after")
    def _require_at_least_one_field(self) -> "UserUpdate":
        if (
            self.name is None
            and self.bio is None
            and self.phone_number is None
            and self.telegram_username is None
            and self.preferred_language is None
            and self.allow_public_activity_view is None
            and self.avatar_url is None
        ):
            raise ValueError("At least one profile field must be provided.")
        return self


UserProfileResponse = ApiSuccess[UserProfile]
UserPublicResponse = ApiSuccess[UserPublic]
