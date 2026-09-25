from __future__ import annotations

from collections.abc import Callable
from functools import partial

from anyio import CapacityLimiter, to_thread
from fastapi import UploadFile
from structlog import get_logger

from app.core.security import api_error
from app.infrastructure.storage.images import MAX_UPLOAD_SIZE_BYTES

logger = get_logger(__name__)
_upload_processing_limiter = CapacityLimiter(2)


async def run_upload_processing[
    ResultT
](function: Callable[..., ResultT], *args: object, **kwargs: object,) -> ResultT:
    call = partial(function, *args, **kwargs)
    return await to_thread.run_sync(call, limiter=_upload_processing_limiter)


async def read_image_upload(
    upload: UploadFile,
    *,
    purpose: str,
    index: int = 0,
) -> tuple[bytes, str | None, str | None]:
    content = await upload.read(MAX_UPLOAD_SIZE_BYTES + 1)
    if len(content) > MAX_UPLOAD_SIZE_BYTES:
        logger.info(
            "image_upload_rejected",
            purpose=purpose,
            index=index,
            reason="file_too_large",
            bytes_read=len(content),
            content_type=upload.content_type,
        )
        raise api_error(
            413,
            "PAYLOAD_TOO_LARGE",
            "The selected image is too large. Each image must be 10 MB or less.",
        )
    return content, upload.content_type, upload.filename


async def read_image_uploads(
    uploads: list[UploadFile],
    *,
    purpose: str,
    max_files: int = 5,
) -> list[tuple[bytes, str | None, str | None]]:
    if len(uploads) > max_files:
        logger.info(
            "image_upload_rejected",
            purpose=purpose,
            reason="too_many_files",
            file_count=len(uploads),
            max_files=max_files,
        )
        raise api_error(
            400,
            "INVALID_PAYLOAD",
            f"Up to {max_files} images are allowed.",
        )

    payloads: list[tuple[bytes, str | None, str | None]] = []
    for index, upload in enumerate(uploads):
        payloads.append(await read_image_upload(upload, purpose=purpose, index=index))
    return payloads
