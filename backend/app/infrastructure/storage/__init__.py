"""Storage adapter implementations package."""

from app.infrastructure.storage.images import (
    ALLOWED_EXTENSIONS,
    ALLOWED_MIME_TYPES,
    MAX_UPLOAD_SIZE_BYTES,
    ImageProcessor,
    ProcessedImage,
    ValidatedImage,
    sanitize_original_filename,
)
from app.infrastructure.storage.keys import MediaKeyFactory, MediaKind, MediaVariant
from app.infrastructure.storage.r2 import R2ObjectStorage, R2StorageConfig, build_object_storage
from app.infrastructure.storage.service import MediaStorageService, StoredMedia, UploadPurpose

__all__ = [
    "ALLOWED_EXTENSIONS",
    "ALLOWED_MIME_TYPES",
    "ImageProcessor",
    "MAX_UPLOAD_SIZE_BYTES",
    "MediaKeyFactory",
    "MediaKind",
    "MediaStorageService",
    "MediaVariant",
    "ProcessedImage",
    "R2ObjectStorage",
    "R2StorageConfig",
    "StoredMedia",
    "UploadPurpose",
    "ValidatedImage",
    "build_object_storage",
    "sanitize_original_filename",
]
