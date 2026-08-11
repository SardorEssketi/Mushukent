from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class StorageError(RuntimeError):
    """Base error for storage foundation failures."""


class StorageConfigurationError(StorageError):
    """Raised when storage is missing or misconfigured."""


class StorageValidationError(StorageError):
    """Raised when input media fails validation."""


class StorageOperationError(StorageError):
    """Raised when a storage backend operation fails."""


@dataclass(slots=True)
class StoredObject:
    key: str
    url: str
    content_type: str
    size_bytes: int
    etag: str | None = None


class ObjectStorage(Protocol):
    bucket_name: str

    def upload(
        self,
        *,
        key: str,
        content: bytes,
        content_type: str,
        metadata: dict[str, str] | None = None,
        cache_control: str | None = None,
    ) -> StoredObject: ...

    def delete(self, key: str) -> None: ...

    def exists(self, key: str) -> bool: ...

    def public_url(self, key: str) -> str: ...
