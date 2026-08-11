from __future__ import annotations

import io
from dataclasses import dataclass
from typing import Final

from PIL import Image, ImageFile, ImageOps, UnidentifiedImageError

from app.core.storage import StorageValidationError

Image.MAX_IMAGE_PIXELS = 25_000_000
ImageFile.LOAD_TRUNCATED_IMAGES = False

MAX_UPLOAD_SIZE_BYTES: Final = 10 * 1024 * 1024
ALLOWED_MIME_TYPES: Final = {"image/jpeg", "image/png"}
ALLOWED_EXTENSIONS: Final = {".jpg", ".jpeg", ".png"}


@dataclass(slots=True)
class ValidatedImage:
    original_size_bytes: int
    format: str
    content_type: str
    extension: str
    width: int
    height: int
    has_transparency: bool


@dataclass(slots=True)
class ProcessedImage:
    content: bytes
    content_type: str
    extension: str
    width: int
    height: int


def sanitize_original_filename(filename: str | None) -> str | None:
    if filename is None:
        return None

    candidate = filename.strip()
    if not candidate:
        return None
    if candidate != candidate.replace("\\", "/").split("/")[-1]:
        raise StorageValidationError("Unsafe filename.")
    if candidate.startswith(".") or ".." in candidate or ":" in candidate:
        raise StorageValidationError("Unsafe filename.")

    return candidate


def _detect_signature(data: bytes) -> tuple[str, str]:
    if data.startswith(b"\xff\xd8\xff"):
        return "jpeg", ".jpg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "png", ".png"
    raise StorageValidationError("Unsupported image signature.")


def _has_alpha(image: Image.Image) -> bool:
    if image.mode in {"RGBA", "LA"}:
        return True
    if image.mode == "P" and "transparency" in image.info:
        return True
    return False


def _fit(image: Image.Image, longest_side: int) -> Image.Image:
    copy = image.copy()
    copy.thumbnail((longest_side, longest_side), Image.Resampling.LANCZOS)
    return copy


def _encode_jpeg(image: Image.Image, *, quality: int) -> bytes:
    working = image
    if working.mode not in {"RGB", "L"}:
        if _has_alpha(working):
            background = Image.new("RGB", working.size, (255, 255, 255))
            background.paste(working.convert("RGBA"), mask=working.convert("RGBA").split()[-1])
            working = background
        else:
            working = working.convert("RGB")

    buffer = io.BytesIO()
    working.save(buffer, format="JPEG", quality=quality, optimize=True, progressive=True)
    return buffer.getvalue()


def _encode_png(image: Image.Image) -> bytes:
    working = image
    if working.mode not in {"RGBA", "LA", "P"}:
        working = working.convert("RGBA")

    buffer = io.BytesIO()
    working.save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()


@dataclass(slots=True)
class ImageProcessor:
    max_upload_size_bytes: int = MAX_UPLOAD_SIZE_BYTES
    observation_longest_side: int = 1920
    thumbnail_longest_side: int = 480
    avatar_longest_side: int = 512
    observation_quality: int = 85
    thumbnail_quality: int = 78
    avatar_quality: int = 85

    def validate_upload(
        self,
        content: bytes,
        *,
        content_type: str | None = None,
        original_filename: str | None = None,
    ) -> ValidatedImage:
        if not content:
            raise StorageValidationError("Image file is empty.")
        if len(content) > self.max_upload_size_bytes:
            raise StorageValidationError("Image file exceeds the 10 MB limit.")
        if content_type is not None and content_type not in ALLOWED_MIME_TYPES:
            raise StorageValidationError("Unsupported image content type.")

        safe_filename = sanitize_original_filename(original_filename)
        if safe_filename is not None:
            lowered = safe_filename.casefold()
            if not any(lowered.endswith(ext) for ext in ALLOWED_EXTENSIONS):
                raise StorageValidationError("Unsupported image file extension.")

        format_name, extension = _detect_signature(content)
        if content_type == "image/jpeg" and format_name != "jpeg":
            raise StorageValidationError("Image content type does not match the file signature.")
        if content_type == "image/png" and format_name != "png":
            raise StorageValidationError("Image content type does not match the file signature.")

        if safe_filename is not None:
            suffix = safe_filename.rsplit(".", maxsplit=1)[-1].casefold()
            if suffix in {"jpg", "jpeg"} and format_name != "jpeg":
                raise StorageValidationError(
                    "Image file extension does not match the file signature."
                )
            if suffix == "png" and format_name != "png":
                raise StorageValidationError(
                    "Image file extension does not match the file signature."
                )

        try:
            with Image.open(io.BytesIO(content)) as image:
                image.load()
                transposed: Image.Image = ImageOps.exif_transpose(image)
                width, height = transposed.size
                if width <= 0 or height <= 0:
                    raise StorageValidationError("Image dimensions are invalid.")
                return ValidatedImage(
                    original_size_bytes=len(content),
                    format=format_name,
                    content_type=f"image/{format_name}",
                    extension=extension,
                    width=width,
                    height=height,
                    has_transparency=_has_alpha(transposed),
                )
        except StorageValidationError:
            raise
        except (OSError, UnidentifiedImageError, ValueError, Image.DecompressionBombError) as exc:
            raise StorageValidationError("Unsupported or malformed image.") from exc

    def process_observation_image(
        self,
        content: bytes,
        *,
        content_type: str | None = None,
        original_filename: str | None = None,
    ) -> tuple[ProcessedImage, ProcessedImage]:
        self.validate_upload(
            content,
            content_type=content_type,
            original_filename=original_filename,
        )

        with Image.open(io.BytesIO(content)) as image:
            image.load()
            transposed: Image.Image = ImageOps.exif_transpose(image)
            canonical = _fit(transposed, self.observation_longest_side)
            thumb = _fit(transposed, self.thumbnail_longest_side)
            return (
                ProcessedImage(
                    content=_encode_jpeg(canonical, quality=self.observation_quality),
                    content_type="image/jpeg",
                    extension=".jpg",
                    width=canonical.width,
                    height=canonical.height,
                ),
                ProcessedImage(
                    content=_encode_jpeg(thumb, quality=self.thumbnail_quality),
                    content_type="image/jpeg",
                    extension=".jpg",
                    width=thumb.width,
                    height=thumb.height,
                ),
            )

    def process_avatar_image(
        self,
        content: bytes,
        *,
        content_type: str | None = None,
        original_filename: str | None = None,
    ) -> ProcessedImage:
        validated = self.validate_upload(
            content,
            content_type=content_type,
            original_filename=original_filename,
        )

        with Image.open(io.BytesIO(content)) as image:
            image.load()
            transposed: Image.Image = ImageOps.exif_transpose(image)
            canonical = _fit(transposed, self.avatar_longest_side)
            if validated.has_transparency:
                return ProcessedImage(
                    content=_encode_png(canonical),
                    content_type="image/png",
                    extension=".png",
                    width=canonical.width,
                    height=canonical.height,
                )
            return ProcessedImage(
                content=_encode_jpeg(canonical, quality=self.avatar_quality),
                content_type="image/jpeg",
                extension=".jpg",
                width=canonical.width,
                height=canonical.height,
            )
