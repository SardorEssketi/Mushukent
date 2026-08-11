from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.features.posts.domain.models import PostAuthorSummary


@dataclass(slots=True)
class AdoptionPostPhotoRecord:
    id: UUID
    photo_url: str
    thumb_url: str | None
    position: int


@dataclass(slots=True)
class AdoptionPostRecord:
    id: UUID
    user_id: UUID | None
    pet_name: str
    owner_phone_number: str
    owner_telegram_username: str | None
    owner_phone_publication_consent: bool
    photo_url: str
    thumb_url: str | None
    photo_urls: list[str]
    photos: list[AdoptionPostPhotoRecord]
    additional_info: str | None
    is_public: bool
    comment_count: int
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    author: PostAuthorSummary | None


@dataclass(slots=True)
class AdoptionPostPage:
    items: list[AdoptionPostRecord]
    next_cursor: str | None
    limit: int


@dataclass(slots=True)
class AdoptionPostPhotoDraft:
    id: UUID
    photo_url: str
    thumb_url: str | None
    position: int


@dataclass(slots=True)
class AdoptionPostCreateDraft:
    id: UUID
    user_id: UUID
    pet_name: str
    owner_phone_number: str
    owner_telegram_username: str | None
    owner_phone_publication_consent: bool
    additional_info: str | None
    photos: list[AdoptionPostPhotoDraft]
