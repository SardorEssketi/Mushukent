from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path, PurePosixPath, PureWindowsPath
from urllib.parse import quote, unquote

from app.core.storage import ObjectStorage, StorageOperationError, StoredObject


@dataclass(slots=True)
class LocalFileObjectStorage(ObjectStorage):
    root_dir: Path
    bucket_name: str

    def __init__(self, root_dir: str | Path, *, bucket_name: str = "mushukistan-media") -> None:
        self.root_dir = Path(root_dir).expanduser().resolve()
        self.bucket_name = bucket_name
        self.root_dir.mkdir(parents=True, exist_ok=True)

    def upload(
        self,
        *,
        key: str,
        content: bytes,
        content_type: str,
        metadata: dict[str, str] | None = None,
        cache_control: str | None = None,
    ) -> StoredObject:
        path = self._resolve_path(key)
        path.parent.mkdir(parents=True, exist_ok=True)
        try:
            path.write_bytes(content)
        except OSError as exc:
            raise StorageOperationError("Failed to write object to local storage.") from exc

        return StoredObject(
            key=key,
            url=self.public_url(key),
            content_type=content_type,
            size_bytes=len(content),
            etag=None,
        )

    def delete(self, key: str) -> None:
        path = self._resolve_path(key)
        if not path.exists():
            return
        try:
            path.unlink()
        except OSError as exc:
            raise StorageOperationError("Failed to delete object from local storage.") from exc

    def exists(self, key: str) -> bool:
        return self._resolve_path(key).exists()

    def public_url(self, key: str) -> str:
        return f"/media/{quote(self._public_key(key), safe='/')}"

    def _resolve_path(self, key: str) -> Path:
        if not key or "\x00" in key:
            raise StorageOperationError("Invalid local storage key.")

        decoded_key = unquote(key).replace("\\", "/")
        if PurePosixPath(decoded_key).is_absolute() or PureWindowsPath(decoded_key).drive:
            raise StorageOperationError("Local storage key must be relative.")
        key_path = Path(decoded_key)
        bucket_root = (self.root_dir / self.bucket_name).resolve()
        candidate = (bucket_root / key_path).resolve()
        try:
            candidate.relative_to(bucket_root)
        except ValueError as exc:
            raise StorageOperationError("Local storage key escapes the media root.") from exc
        if candidate == bucket_root:
            raise StorageOperationError("Invalid local storage key.")
        return candidate

    def _public_key(self, key: str) -> str:
        return f"{self.bucket_name}/{key.replace('\\', '/')}"
