from __future__ import annotations

from dataclasses import dataclass
from urllib.parse import quote

import boto3
from botocore.exceptions import ClientError

from app.core.config import Settings
from app.core.storage import (
    ObjectStorage,
    StorageConfigurationError,
    StorageOperationError,
    StoredObject,
)
from app.infrastructure.storage.local import LocalFileObjectStorage


@dataclass(slots=True)
class R2StorageConfig:
    account_id: str
    access_key_id: str
    secret_access_key: str
    bucket: str
    public_base_url: str | None = None
    region_name: str = "auto"

    @classmethod
    def from_settings(cls, settings: Settings) -> R2StorageConfig:
        if (
            not settings.r2_account_id
            or not settings.r2_access_key_id
            or not settings.r2_secret_access_key
        ):
            raise StorageConfigurationError(
                "Cloudflare R2 is not configured. Set R2_ACCOUNT_ID, R2_ACCESS_KEY_ID and "
                "R2_SECRET_ACCESS_KEY."
            )
        return cls(
            account_id=settings.r2_account_id,
            access_key_id=settings.r2_access_key_id,
            secret_access_key=settings.r2_secret_access_key,
            bucket=settings.r2_bucket,
            public_base_url=settings.r2_public_base_url or None,
        )

    @property
    def endpoint_url(self) -> str:
        return f"https://{self.account_id}.r2.cloudflarestorage.com"


class R2ObjectStorage(ObjectStorage):
    def __init__(self, config: R2StorageConfig, *, client=None) -> None:
        self.config = config
        self.bucket_name = config.bucket
        self._client = client or boto3.client(
            "s3",
            region_name=config.region_name,
            endpoint_url=config.endpoint_url,
            aws_access_key_id=config.access_key_id,
            aws_secret_access_key=config.secret_access_key,
        )

    @classmethod
    def from_settings(cls, settings: Settings, *, client=None) -> R2ObjectStorage:
        return cls(R2StorageConfig.from_settings(settings), client=client)

    def upload(
        self,
        *,
        key: str,
        content: bytes,
        content_type: str,
        metadata: dict[str, str] | None = None,
        cache_control: str | None = None,
    ) -> StoredObject:
        try:
            response = self._client.put_object(
                Bucket=self.bucket_name,
                Key=key,
                Body=content,
                ContentType=content_type,
                Metadata=metadata or {},
                CacheControl=cache_control,
            )
        except ClientError as exc:
            raise StorageOperationError("Failed to upload object to Cloudflare R2.") from exc

        return StoredObject(
            key=key,
            url=self.public_url(key),
            content_type=content_type,
            size_bytes=len(content),
            etag=response.get("ETag"),
        )

    def delete(self, key: str) -> None:
        try:
            self._client.delete_object(Bucket=self.bucket_name, Key=key)
        except ClientError as exc:
            error_code = str(exc.response.get("Error", {}).get("Code", ""))
            if error_code in {"404", "NoSuchKey", "NotFound"}:
                return
            raise StorageOperationError("Failed to delete object from Cloudflare R2.") from exc

    def exists(self, key: str) -> bool:
        try:
            self._client.head_object(Bucket=self.bucket_name, Key=key)
            return True
        except ClientError as exc:
            error_code = str(exc.response.get("Error", {}).get("Code", ""))
            if error_code in {"404", "NoSuchKey", "NotFound"}:
                return False
            raise StorageOperationError("Failed to check whether object exists.") from exc

    def public_url(self, key: str) -> str:
        base_url = self.config.public_base_url or self.config.endpoint_url.replace(
            "https://", f"https://{self.bucket_name}."
        )
        return f"{base_url.rstrip('/')}/{quote(key, safe='/')}"


def build_object_storage(settings: Settings) -> ObjectStorage | None:
    configured_values = [
        settings.r2_account_id,
        settings.r2_access_key_id,
        settings.r2_secret_access_key,
    ]
    if any(configured_values) and not all(configured_values):
        raise StorageConfigurationError(
            "Cloudflare R2 configuration is incomplete. Set R2_ACCOUNT_ID, "
            "R2_ACCESS_KEY_ID and R2_SECRET_ACCESS_KEY together."
        )
    if not all(configured_values):
        if settings.app_env.casefold() in {"production", "staging"}:
            raise StorageConfigurationError(
                "Cloudflare R2 is required in production and staging environments."
            )
        return LocalFileObjectStorage(
            settings.media_storage_root,
            bucket_name=settings.r2_bucket,
        )
    return R2ObjectStorage.from_settings(settings)
