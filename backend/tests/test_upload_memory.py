"""Uploads must not be able to exhaust the API's memory (load audit LT-10, FIX-6).

Covers: header-only validation, one full decode per image at reduced JPEG scale, a pixel cap that
never rejects what the app produces (it resizes to <= 1920 px before upload), unchanged output
(dimensions, EXIF orientation, transparency, thumbnails, quality), one image-processing slot, and
one multipart upload in flight per user.
"""

from __future__ import annotations

import io
import math
import threading
import time

import pytest
from fastapi import FastAPI, Request
from fastapi.testclient import TestClient
from PIL import Image, ImageChops, ImageFile, ImageOps, ImageStat

from app.api.v1 import uploads
from app.core.storage import StorageValidationError
from app.core.upload_guard import UploadSingleFlightMiddleware
from app.infrastructure.storage import images
from app.infrastructure.storage.images import ImageProcessor

# ----------------------------------------------------------------------------- fixtures


def _jpeg(
    width: int, height: int, *, orientation: int | None = None, mode: str = "RGB", quality: int = 90
) -> bytes:
    image = Image.new(mode, (width, height), (40, 120, 200) if mode == "RGB" else 128)
    # A red marker in the stored top-left corner makes the EXIF orientation observable.
    marker = (255, 0, 0) if mode == "RGB" else 255
    image.paste(marker, (0, 0, max(1, width // 8), max(1, height // 8)))
    # Some texture so resampling differences show up in the comparison.
    for x in range(0, width, max(1, width // 40)):
        image.paste((0, 0, 0) if mode == "RGB" else 0, (x, 0, x + 1, height))
    buffer = io.BytesIO()
    exif = None
    if orientation is not None:
        exif = Image.Exif()
        exif[0x0112] = orientation
    image.save(buffer, "JPEG", quality=quality, **({"exif": exif} if exif else {}))
    return buffer.getvalue()


def _png(width: int, height: int, *, mode: str) -> bytes:
    if mode == "P":
        image = Image.new("P", (width, height), 1)
        image.putpalette([0, 0, 0, 255, 0, 0] + [0] * 762)
        image.info["transparency"] = 0
        image.paste(0, (0, 0, width // 2, height // 2))
    else:
        image = Image.new(mode, (width, height), (10, 200, 30, 255))
        image.paste((0, 0, 0, 0), (0, 0, width // 2, height // 2))
    buffer = io.BytesIO()
    image.save(buffer, "PNG", **({"transparency": 0} if mode == "P" else {}))
    return buffer.getvalue()


def _reference_observation(content: bytes) -> tuple[bytes, bytes]:
    """The pre-FIX-6 algorithm (full decode, EXIF transpose, LANCZOS fit), encoded with the same
    encoder and qualities as production."""
    with Image.open(io.BytesIO(content)) as image:
        image.load()
        transposed = ImageOps.exif_transpose(image)
        canonical = images._fit(transposed, 1920)
        thumb = images._fit(transposed, 480)
        return images._encode_jpeg(canonical, quality=85), images._encode_jpeg(thumb, quality=78)


def _reference_avatar(content: bytes) -> Image.Image:
    with Image.open(io.BytesIO(content)) as image:
        image.load()
        transposed = ImageOps.exif_transpose(image)
        return images._fit(transposed, 512).convert("RGB")


def _decode(content: bytes) -> Image.Image:
    with Image.open(io.BytesIO(content)) as image:
        image.load()
        return image.convert("RGB")


def _psnr(a: Image.Image, b: Image.Image) -> float:
    diff = ImageChops.difference(a, b)
    mse = sum(value * value for value in ImageStat.Stat(diff).rms) / 3
    return math.inf if mse == 0 else 20 * math.log10(255 / math.sqrt(mse))


APP_SIZED = [
    ("landscape 1920x1440", _jpeg(1920, 1440)),
    ("portrait EXIF orientation 6", _jpeg(1920, 1440, orientation=6)),
    ("grayscale 1600x1200", _jpeg(1600, 1200, mode="L")),
    ("small 640x480", _jpeg(640, 480)),
]

# ----------------------------------------------------------------------------- limits


def test_pixel_cap_accepts_everything_the_app_produces() -> None:
    processor = ImageProcessor()
    validated = processor.validate_upload(_jpeg(1920, 1920), content_type="image/jpeg")
    assert (validated.width, validated.height) == (1920, 1920)


def test_pixel_cap_rejects_oversized_images() -> None:
    assert images.Image.MAX_IMAGE_PIXELS == 8_000_000
    with pytest.raises(StorageValidationError):
        ImageProcessor().validate_upload(_jpeg(3300, 2500), content_type="image/jpeg")


def test_validation_reads_headers_only(monkeypatch) -> None:
    content = _jpeg(1920, 1440, orientation=6)
    decoded_sizes = _record_decodes(monkeypatch)
    validated = ImageProcessor().validate_upload(content, content_type="image/jpeg")
    assert decoded_sizes == []
    # Orientation-aware size without decoding.
    assert (validated.width, validated.height) == (1440, 1920)


def _record_decodes(monkeypatch) -> list[tuple[int, int]]:
    """Sizes of actual pixel decodes: ImageFile.load with pending tiles (later calls are no-ops)."""
    decoded_sizes: list[tuple[int, int]] = []
    original_load = ImageFile.ImageFile.load

    def recording_load(self):
        pending = bool(getattr(self, "tile", None))
        result = original_load(self)
        if pending:
            decoded_sizes.append(self.size)
        return result

    monkeypatch.setattr(ImageFile.ImageFile, "load", recording_load)
    return decoded_sizes


def test_observation_upload_is_decoded_once(monkeypatch) -> None:
    content = _jpeg(3000, 2400)  # 7.2 MP: allowed, larger than the app ever sends
    decoded_sizes = _record_decodes(monkeypatch)
    canonical, thumb = ImageProcessor().process_observation_image(
        content, content_type="image/jpeg"
    )
    assert decoded_sizes.count((3000, 2400)) == 1  # was 2: validation + processing
    assert (canonical.width, canonical.height) == (1920, 1536)
    assert (thumb.width, thumb.height) == (480, 384)


def test_avatar_jpeg_is_decoded_at_reduced_scale(monkeypatch) -> None:
    content = _jpeg(1920, 1440)
    decoded_sizes = _record_decodes(monkeypatch)
    result = ImageProcessor().process_avatar_image(content, content_type="image/jpeg")
    assert (1920, 1440) not in decoded_sizes
    assert (960, 720) in decoded_sizes
    assert (result.width, result.height) == (512, 384)


def test_malformed_and_truncated_images_are_still_rejected() -> None:
    processor = ImageProcessor()
    truncated = _jpeg(1920, 1440)[:5000]
    with pytest.raises(StorageValidationError):
        processor.process_observation_image(truncated, content_type="image/jpeg")
    with pytest.raises(StorageValidationError):
        processor.process_observation_image(
            b"\xff\xd8\xff" + b"0" * 2000, content_type="image/jpeg"
        )


# ----------------------------------------------------------------------------- output parity


@pytest.mark.parametrize(("label", "content"), APP_SIZED, ids=[label for label, _ in APP_SIZED])
def test_app_sized_output_is_byte_identical_to_the_previous_algorithm(
    label: str, content: bytes
) -> None:
    canonical, thumb = ImageProcessor().process_observation_image(content)
    expected_canonical, expected_thumb = _reference_observation(content)
    assert canonical.content == expected_canonical
    assert thumb.content == expected_thumb
    assert canonical.content_type == thumb.content_type == "image/jpeg"


def test_exif_orientation_is_applied() -> None:
    canonical, _ = ImageProcessor().process_observation_image(_jpeg(1920, 1440, orientation=6))
    image = _decode(canonical.content)
    assert image.size == (1440, 1920)
    # Orientation 6 rotates the stored top-left marker to the top-right.
    red, green, blue = image.getpixel((image.width - 5, 5))
    assert red > 200 and green < 80 and blue < 80


def test_large_input_output_is_byte_identical_to_the_previous_algorithm() -> None:
    # 3000 px is below 2x the 1920 target, so no reduced decode applies: same pixels, same bytes.
    content = _jpeg(3000, 2400)
    canonical, thumb = ImageProcessor().process_observation_image(content)
    assert (canonical.content, thumb.content) == _reference_observation(content)


def test_avatar_from_a_reduced_decode_stays_close_to_the_previous_algorithm() -> None:
    content = _jpeg(1920, 1440)
    result = ImageProcessor().process_avatar_image(content)
    expected = _reference_avatar(content)
    got = _decode(result.content)
    assert got.size == expected.size == (512, 384)
    assert _psnr(got, expected) > 30  # includes JPEG q85 encoding of the result


@pytest.mark.parametrize("mode", ["RGBA", "P"])
def test_transparent_avatars_stay_png(mode: str) -> None:
    result = ImageProcessor().process_avatar_image(_png(1024, 768, mode=mode))
    assert result.content_type == "image/png"
    assert (result.width, result.height) == (512, 384)
    with Image.open(io.BytesIO(result.content)) as image:
        assert image.mode in {"RGBA", "LA", "P"}


def test_opaque_avatar_is_jpeg_at_512() -> None:
    result = ImageProcessor().process_avatar_image(_jpeg(1920, 1440))
    assert (result.content_type, result.width, result.height) == ("image/jpeg", 512, 384)


# ----------------------------------------------------------------------------- concurrency


def test_one_image_processing_slot() -> None:
    assert uploads._upload_processing_limiter.total_tokens == 1


def _guarded_app(release: threading.Event, entered: threading.Event) -> TestClient:
    app = FastAPI()

    @app.post("/api/v1/posts")
    def create(request: Request) -> dict[str, str]:
        entered.set()
        release.wait(5)
        return {"ok": "yes"}

    @app.patch("/api/v1/posts/{post_id}")
    def update(post_id: str) -> dict[str, str]:
        return {"ok": post_id}

    app.add_middleware(
        UploadSingleFlightMiddleware,
        identify=lambda scope: dict(scope["headers"]).get(b"x-test-user", b"").decode() or None,
    )
    return TestClient(app)


def _multipart(user: str) -> dict:
    return {
        "headers": {"x-test-user": user},
        "files": [("photos", ("p.jpg", b"jpeg-bytes", "image/jpeg"))],
    }


def test_second_upload_from_the_same_user_is_rejected_while_one_is_in_flight() -> None:
    release, entered = threading.Event(), threading.Event()
    client = _guarded_app(release, entered)
    results: dict[str, int] = {}
    first = threading.Thread(
        target=lambda: results.update(
            first=client.post("/api/v1/posts", **_multipart("u1")).status_code
        )
    )
    first.start()
    assert entered.wait(5)
    second = client.post("/api/v1/posts", **_multipart("u1"))
    other_user = threading.Thread(
        target=lambda: results.update(
            other=client.post("/api/v1/posts", **_multipart("u2")).status_code
        )
    )
    other_user.start()
    time.sleep(0.2)
    json_edit = client.patch("/api/v1/posts/abc", headers={"x-test-user": "u1"}, json={"d": 1})
    release.set()
    first.join(5)
    other_user.join(5)
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "PUBLICATION_IN_PROGRESS"
    assert results == {"first": 200, "other": 200}
    assert json_edit.status_code == 200  # text-only edits are not uploads
    # The slot is released afterwards.
    release.set()
    assert client.post("/api/v1/posts", **_multipart("u1")).status_code == 200


def test_slot_is_released_when_the_upload_fails() -> None:
    app = FastAPI()

    @app.post("/api/v1/posts")
    def create() -> None:
        raise RuntimeError("storage down")

    app.add_middleware(UploadSingleFlightMiddleware, identify=lambda scope: "u1")
    client = TestClient(app, raise_server_exceptions=False)
    assert client.post("/api/v1/posts", **_multipart("u1")).status_code == 500
    assert client.post("/api/v1/posts", **_multipart("u1")).status_code == 500  # not 409
