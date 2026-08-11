from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID

from app.features.cats.domain.models import GeoPoint
from app.features.posts.domain.models import PostAuthorSummary


@dataclass(slots=True)
class LostPetPhotoRecord:
    id: UUID
    photo_url: str
    thumb_url: str | None
    position: int


@dataclass(slots=True)
class LostPetRecord:
    id: UUID
    user_id: UUID | None
    pet_name: str
    owner_phone_number: str
    owner_telegram_username: str | None
    owner_phone_publication_consent: bool
    photo_url: str
    thumb_url: str | None
    photo_urls: list[str]
    photos: list[LostPetPhotoRecord]
    last_seen_location: GeoPoint
    additional_info: str | None
    is_resolved: bool
    is_public: bool
    comment_count: int
    created_at: datetime
    updated_at: datetime
    deleted_at: datetime | None
    author: PostAuthorSummary | None


@dataclass(slots=True)
class LostPetPage:
    items: list[LostPetRecord]
    next_cursor: str | None
    limit: int


@dataclass(slots=True)
class LostPetPhotoDraft:
    id: UUID
    photo_url: str
    thumb_url: str | None
    position: int


@dataclass(slots=True)
class LostPetCreateDraft:
    id: UUID
    user_id: UUID
    pet_name: str
    owner_phone_number: str
    owner_telegram_username: str | None
    owner_phone_publication_consent: bool
    last_seen_latitude: float
    last_seen_longitude: float
    additional_info: str | None
    photos: list[LostPetPhotoDraft]
