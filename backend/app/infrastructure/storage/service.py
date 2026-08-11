from __future__ import annotations

from dataclasses import dataclass, field
from enum import StrEnum
from urllib.parse import urlparse
from uuid import UUID

from structlog import get_logger

from app.core.storage import (
    ObjectStorage,
    StorageOperationError,
    StorageValidationError,
    StoredObject,
)
from app.infrastructure.storage.images import ImageProcessor, ProcessedImage
from app.infrastructure.storage.keys import MediaKeyFactory, MediaKind, MediaVariant

logger = get_logger(__name__)


class UploadPurpose(StrEnum):
    POST_OBSERVATION = "post_observation"
    USER_AVATAR = "user_avatar"
    CAT_COVER = "cat_cover"
    LOST_PET = "lost_pet"
    ADOPTION = "adoption"


@dataclass(slots=True)
class StoredMedia:
    canonical: StoredObject
    thumbnail: StoredObject | None = None


@dataclass(slots=True)
class MediaStorageService:
    storage: ObjectStorage
    processor: ImageProcessor = field(default_factory=ImageProcessor)
    key_factory: MediaKeyFactory = field(default_factory=MediaKeyFactory)

    def upload_image(
        self,
        *,
        purpose: UploadPurpose,
        entity_id: UUID,
        content: bytes,
        content_type: str | None = None,
        original_filename: str | None = None,
    ) -> StoredMedia:
        try:
            if purpose in {
                UploadPurpose.POST_OBSERVATION,
                UploadPurpose.LOST_PET,
                UploadPurpose.ADOPTION,
            }:
                canonical_image, thumbnail_image = self.processor.process_observation_image(
                    content,
                    content_type=content_type,
                    original_filename=original_filename,
                )
                canonical_kind = (
                    MediaKind.LOST_PET
                    if purpose == UploadPurpose.LOST_PET
                    else MediaKind.ADOPTION if purpose == UploadPurpose.ADOPTION else MediaKind.POST
                )
                canonical_variant = MediaVariant.ORIGINAL
                thumbnail_variant = MediaVariant.THUMBNAIL
                canonical = self._upload_variant(
                    entity_id=entity_id,
                    image=canonical_image,
                    kind=canonical_kind,
                    variant=canonical_variant,
                )
                try:
                    thumbnail = self._upload_variant(
                        entity_id=entity_id,
                        image=thumbnail_image,
                        kind=canonical_kind,
                        variant=thumbnail_variant,
                    )
                except Exception as exc:
                    self._best_effort_cleanup(canonical.key)
                    raise StorageOperationError("Failed to upload thumbnail image.") from exc
                return StoredMedia(canonical=canonical, thumbnail=thumbnail)

            image = self.processor.process_avatar_image(
                content,
                content_type=content_type,
                original_filename=original_filename,
            )
            kind = {
                UploadPurpose.USER_AVATAR: MediaKind.AVATAR,
                UploadPurpose.CAT_COVER: MediaKind.CAT_COVER,
            }[purpose]
            canonical = self._upload_variant(
                entity_id=entity_id,
                image=image,
                kind=kind,
                variant=MediaVariant.ORIGINAL,
            )
            return StoredMedia(canonical=canonical)
        except StorageValidationError:
            raise
        except StorageOperationError:
            raise
        except Exception as exc:  # pragma: no cover - defensive safety net
            logger.exception("Unexpected media upload failure", purpose=purpose.value)
            raise StorageOperationError("Image upload failed.") from exc

    def object_exists(self, key: str) -> bool:
        return self.storage.exists(key)

    def delete_object(self, key: str) -> None:
        try:
            self.storage.delete(key)
        except StorageOperationError:
            logger.warning("Best-effort media delete failed", key=key)
            raise

    def delete_media_url(self, url: str | None) -> None:
        key = self._key_from_public_url(url)
        if key is None:
            return
        self.delete_object(key)

    def _key_from_public_url(self, url: str | None) -> str | None:
        if not url:
            return None
        parsed = urlparse(url)
        path = parsed.path if parsed.scheme else url
        marker = f"/{self.storage.bucket_name}/"
        if marker in path:
            return path.split(marker, 1)[1].lstrip("/")
        known_prefixes = (
            "posts/",
            "users/avatars/",
            "cats/covers/",
            "lost-pets/",
            "adoption/",
        )
        normalized = path.lstrip("/")
        for prefix in known_prefixes:
            if normalized.startswith(prefix):
                return normalized
        return None

    def _upload_variant(
        self,
        *,
        entity_id: UUID,
        image: ProcessedImage,
        kind: MediaKind,
        variant: MediaVariant,
    ) -> StoredObject:
        key = self.key_factory.build(
            kind=kind,
            entity_id=entity_id,
            extension=image.extension,
            variant=variant,
        )
        return self.storage.upload(
            key=key,
            content=image.content,
            content_type=image.content_type,
            metadata={
                "purpose": kind.value,
                "variant": variant.value,
            },
            cache_control="public, max-age=31536000, immutable",
        )

    def _best_effort_cleanup(self, key: str) -> None:
        try:
            self.storage.delete(key)
        except StorageOperationError:
            logger.warning("Cleanup after media upload failure failed", key=key)
