from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

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
        return self.root_dir / self.bucket_name / Path(key)

    def _public_key(self, key: str) -> str:
        return f"{self.bucket_name}/{key.replace('\\', '/')}"
