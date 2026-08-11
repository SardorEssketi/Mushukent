from __future__ import annotations

import io
import os
from datetime import UTC, datetime
from uuid import UUID, uuid4

import boto3
import pytest
from botocore.stub import Stubber
from PIL import Image

from app.core.storage import StorageOperationError, StorageValidationError, StoredObject
from app.infrastructure.storage.images import (
    MAX_UPLOAD_SIZE_BYTES,
    ImageProcessor,
    sanitize_original_filename,
)
from app.infrastructure.storage.keys import MediaKeyFactory, MediaKind, MediaVariant
from app.infrastructure.storage.r2 import R2ObjectStorage, R2StorageConfig
from app.infrastructure.storage.service import MediaStorageService, UploadPurpose


def _make_jpeg(*, size: tuple[int, int] = (64, 48), orientation: int | None = None) -> bytes:
    image = Image.new("RGB", size, (220, 20, 60))
    buffer = io.BytesIO()
    if orientation is not None:
        exif = image.getexif()
        exif[274] = orientation
        image.save(buffer, format="JPEG", exif=exif)
    else:
        image.save(buffer, format="JPEG")
    return buffer.getvalue()


def _make_png(*, size: tuple[int, int] = (48, 48), alpha: bool = False) -> bytes:
    mode = "RGBA" if alpha else "RGB"
    color = (0, 128, 255, 0) if alpha else (0, 128, 255)
    image = Image.new(mode, size, color)
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


class MemoryObjectStorage:
    def __init__(self, *, fail_on_upload: int | None = None) -> None:
        self.fail_on_upload = fail_on_upload
        self.upload_calls = 0
        self.objects: dict[str, StoredObject] = {}
        self.blobs: dict[str, bytes] = {}
        self.deleted_keys: list[str] = []

    def upload(
        self,
        *,
        key: str,
        content: bytes,
        content_type: str,
        metadata: dict[str, str] | None = None,
        cache_control: str | None = None,
    ) -> StoredObject:
        self.upload_calls += 1
        if self.fail_on_upload == self.upload_calls:
            raise StorageOperationError("storage provider failure")
        stored = StoredObject(
            key=key,
            url=f"https://media.example/{key}",
            content_type=content_type,
            size_bytes=len(content),
            etag="etag",
        )
        self.objects[key] = stored
        self.blobs[key] = content
        return stored

    def delete(self, key: str) -> None:
        self.deleted_keys.append(key)
        self.objects.pop(key, None)
        self.blobs.pop(key, None)

    def exists(self, key: str) -> bool:
        return key in self.objects

    def public_url(self, key: str) -> str:
        return f"https://media.example/{key}"


def test_valid_image_upload_and_metadata_removal() -> None:
    storage = MemoryObjectStorage()
    service = MediaStorageService(storage=storage)
    content = _make_jpeg(size=(80, 60), orientation=6)

    result = service.upload_image(
        purpose=UploadPurpose.USER_AVATAR,
        entity_id=uuid4(),
        content=content,
        content_type="image/jpeg",
        original_filename="avatar.jpg",
    )

    assert result.thumbnail is None
    assert result.canonical.content_type == "image/jpeg"
    assert result.canonical.url.startswith("https://media.example/users/avatars/")

    output = Image.open(io.BytesIO(storage.blobs[result.canonical.key]))
    assert output.getexif() == {}
    assert output.size == (60, 80)


def test_invalid_mime_type_rejected() -> None:
    processor = ImageProcessor()
    content = _make_jpeg()

    with pytest.raises(StorageValidationError):
        processor.validate_upload(
            content,
            content_type="image/png",
            original_filename="avatar.png",
        )


def test_invalid_file_signature_rejected() -> None:
    processor = ImageProcessor()

    with pytest.raises(StorageValidationError):
        processor.validate_upload(
            b"not-an-image",
            content_type="image/jpeg",
            original_filename="avatar.jpg",
        )


def test_oversized_file_rejected() -> None:
    processor = ImageProcessor()
    content = b"\xff\xd8\xff" + b"0" * (MAX_UPLOAD_SIZE_BYTES + 1)

    with pytest.raises(StorageValidationError):
        processor.validate_upload(
            content,
            content_type="image/jpeg",
            original_filename="avatar.jpg",
        )


def test_empty_file_rejected() -> None:
    processor = ImageProcessor()

    with pytest.raises(StorageValidationError):
        processor.validate_upload(b"", content_type="image/jpeg", original_filename="avatar.jpg")


def test_unsafe_filename_or_path_input_rejected() -> None:
    processor = ImageProcessor()
    content = _make_png()

    with pytest.raises(StorageValidationError):
        processor.validate_upload(
            content,
            content_type="image/png",
            original_filename="../avatar.png",
        )

    assert sanitize_original_filename("avatar.png") == "avatar.png"


def test_object_key_uniqueness() -> None:
    factory = MediaKeyFactory()
    timestamp = datetime(2026, 7, 24, tzinfo=UTC)
    entity_id = UUID("11111111-1111-4111-8111-111111111111")
    keys = {
        factory.build(
            kind=MediaKind.AVATAR,
            entity_id=entity_id,
            extension=".jpg",
            variant=MediaVariant.ORIGINAL,
            timestamp=timestamp,
        )
        for _ in range(20)
    }

    assert len(keys) == 20
    assert all(key.startswith("users/avatars/2026/07/24/") for key in keys)


def test_decompression_bomb_guard(monkeypatch: pytest.MonkeyPatch) -> None:
    processor = ImageProcessor()
    monkeypatch.setattr(Image, "MAX_IMAGE_PIXELS", 100)
    content = _make_png(size=(20, 20))

    with pytest.raises(StorageValidationError):
        processor.validate_upload(
            content,
            content_type="image/png",
            original_filename="bomb.png",
        )


def test_cleanup_after_partial_failure() -> None:
    storage = MemoryObjectStorage(fail_on_upload=2)
    service = MediaStorageService(storage=storage)
    content = _make_jpeg()

    with pytest.raises(StorageOperationError):
        service.upload_image(
            purpose=UploadPurpose.POST_OBSERVATION,
            entity_id=uuid4(),
            content=content,
            content_type="image/jpeg",
            original_filename="observation.jpg",
        )

    assert storage.objects == {}
    assert len(storage.deleted_keys) == 1


def test_deletion_is_idempotent() -> None:
    storage = MemoryObjectStorage()
    service = MediaStorageService(storage=storage)

    service.delete_object("missing/object.jpg")
    service.delete_object("missing/object.jpg")

    assert storage.deleted_keys == ["missing/object.jpg", "missing/object.jpg"]


def test_r2_adapter_with_stubbed_client() -> None:
    client = boto3.client(
        "s3",
        endpoint_url="https://1234567890.r2.cloudflarestorage.com",
        aws_access_key_id="access",
        aws_secret_access_key="secret",
        region_name="auto",
    )
    stubber = Stubber(client)

    config = R2StorageConfig(
        account_id="1234567890",
        access_key_id="access",
        secret_access_key="secret",
        bucket="mushukistan-media",
        public_base_url="https://media.example.com",
    )
    storage = R2ObjectStorage(config, client=client)

    stubber.add_response(
        "put_object",
        {"ETag": '"etag"'},
        {
            "Bucket": "mushukistan-media",
            "Key": "users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg",
            "Body": b"payload",
            "ContentType": "image/jpeg",
            "Metadata": {"purpose": "avatar", "variant": "original"},
            "CacheControl": "public, max-age=31536000, immutable",
        },
    )
    stubber.add_response(
        "head_object",
        {"ContentLength": 7},
        {
            "Bucket": "mushukistan-media",
            "Key": "users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg",
        },
    )
    stubber.add_response(
        "delete_object",
        {},
        {
            "Bucket": "mushukistan-media",
            "Key": "users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg",
        },
    )
    stubber.add_client_error(
        "delete_object",
        service_error_code="NoSuchKey",
        service_message="missing",
        expected_params={
            "Bucket": "mushukistan-media",
            "Key": "users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg",
        },
    )

    with stubber:
        uploaded = storage.upload(
            key="users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg",
            content=b"payload",
            content_type="image/jpeg",
            metadata={"purpose": "avatar", "variant": "original"},
            cache_control="public, max-age=31536000, immutable",
        )
        assert uploaded.url == (
            "https://media.example.com/users/avatars/2026/07/24/"
            "avatar_uuid_20260724T120000Z_deadbeef.jpg"
        )
        assert (
            storage.exists("users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg")
            is True
        )
        storage.delete("users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg")
        storage.delete("users/avatars/2026/07/24/avatar_uuid_20260724T120000Z_deadbeef.jpg")


@pytest.mark.integration
def test_optional_live_r2_smoke() -> None:
    if not all(
        os.getenv(name)
        for name in ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET")
    ):
        pytest.skip("R2 credentials are not available for live smoke testing.")

    config = R2StorageConfig(
        account_id=os.environ["R2_ACCOUNT_ID"],
        access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        bucket=os.environ["R2_BUCKET"],
        public_base_url=os.getenv("R2_PUBLIC_BASE_URL") or None,
    )
    storage = R2ObjectStorage(config)
    key = f"tests/smoke/{uuid4().hex}/smoke.png"
    content = _make_png(size=(8, 8))

    try:
        uploaded = storage.upload(
            key=key,
            content=content,
            content_type="image/png",
            metadata={"purpose": "smoke", "variant": "original"},
            cache_control="no-cache",
        )
        assert uploaded.key == key
        assert storage.exists(key) is True
    finally:
        storage.delete(key)
