from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from enum import StrEnum
from secrets import token_hex
from uuid import UUID


class MediaKind(StrEnum):
    POST = "post"
    AVATAR = "avatar"
    CAT_COVER = "cat_cover"
    LOST_PET = "lost_pet"
    ADOPTION = "adoption"


class MediaVariant(StrEnum):
    ORIGINAL = "original"
    THUMBNAIL = "thumb"
    COVER = "cover"


@dataclass(slots=True)
class MediaKeyFactory:
    def build(
        self,
        *,
        kind: MediaKind,
        entity_id: UUID,
        extension: str,
        variant: MediaVariant = MediaVariant.ORIGINAL,
        timestamp: datetime | None = None,
    ) -> str:
        now = timestamp or datetime.now(UTC)
        date_prefix = now.strftime("%Y/%m/%d")
        stamp = now.strftime("%Y%m%dT%H%M%SZ")
        nonce = token_hex(4)
        suffix = "_thumb" if variant == MediaVariant.THUMBNAIL else ""
        stem = {
            MediaKind.POST: "post",
            MediaKind.AVATAR: "avatar",
            MediaKind.CAT_COVER: "cat",
            MediaKind.LOST_PET: "lost_pet",
            MediaKind.ADOPTION: "adoption",
        }[kind]
        folder = {
            MediaKind.POST: "posts/original",
            MediaKind.AVATAR: "users/avatars",
            MediaKind.CAT_COVER: "cats/covers",
            MediaKind.LOST_PET: "lost-pets/original",
            MediaKind.ADOPTION: "adoption/original",
        }[kind]
        if variant == MediaVariant.THUMBNAIL:
            folder = {
                MediaKind.LOST_PET: "lost-pets/thumbs",
                MediaKind.ADOPTION: "adoption/thumbs",
            }.get(kind, "posts/thumbs")

        return (
            f"{folder}/{date_prefix}/"
            f"{stem}_{entity_id}_{stamp}_{nonce}{suffix}.{extension.lower().lstrip('.')}"
        )
