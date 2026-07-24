from __future__ import annotations

from datetime import datetime
from typing import Generic, TypeVar
from uuid import UUID

from pydantic import AnyHttpUrl, BaseModel, ConfigDict, EmailStr, Field, model_validator

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


class UserUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    name: str | None = Field(default=None, max_length=100)
    bio: str | None = Field(default=None, max_length=1000)
    avatar_url: AnyHttpUrl | None = None

    @model_validator(mode="after")
    def _require_at_least_one_field(self) -> "UserUpdate":
        if self.name is None and self.bio is None and self.avatar_url is None:
            raise ValueError("At least one profile field must be provided.")
        return self


UserProfileResponse = ApiSuccess[UserProfile]
UserPublicResponse = ApiSuccess[UserPublic]
