from __future__ import annotations

import asyncio
import io
from threading import Event, Lock

import pytest
from fastapi import HTTPException, UploadFile
from starlette.datastructures import Headers

from app.api.v1.uploads import (
    read_image_upload,
    read_image_uploads,
    run_upload_processing,
)
from app.infrastructure.storage.images import MAX_UPLOAD_SIZE_BYTES


def _upload(content: bytes, *, filename: str = "cat.jpg") -> UploadFile:
    return UploadFile(
        file=io.BytesIO(content),
        filename=filename,
        headers=Headers({"content-type": "image/jpeg"}),
    )


def test_bounded_reader_accepts_image_at_limit() -> None:
    content = b"x" * MAX_UPLOAD_SIZE_BYTES

    result = asyncio.run(read_image_upload(_upload(content), purpose="test"))

    assert result == (content, "image/jpeg", "cat.jpg")


def test_bounded_reader_rejects_oversized_image() -> None:
    content = b"x" * (MAX_UPLOAD_SIZE_BYTES + 1)

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(read_image_upload(_upload(content), purpose="test"))

    assert exc_info.value.status_code == 413
    assert exc_info.value.detail["error"]["code"] == "PAYLOAD_TOO_LARGE"


def test_file_count_is_rejected_before_any_file_is_read() -> None:
    uploads = [_upload(b"photo") for _ in range(6)]

    with pytest.raises(HTTPException) as exc_info:
        asyncio.run(read_image_uploads(uploads, purpose="test", max_files=5))

    assert exc_info.value.status_code == 400
    assert all(upload.file.tell() == 0 for upload in uploads)


def test_upload_processing_limits_blocking_concurrency() -> None:
    lock = Lock()
    release = Event()
    two_started = Event()
    active = 0
    maximum_active = 0

    def process_upload() -> None:
        nonlocal active, maximum_active
        with lock:
            active += 1
            maximum_active = max(maximum_active, active)
            if active == 2:
                two_started.set()
        try:
            assert release.wait(timeout=2)
        finally:
            with lock:
                active -= 1

    async def run_requests() -> None:
        tasks = [asyncio.create_task(run_upload_processing(process_upload)) for _ in range(3)]
        assert await asyncio.to_thread(two_started.wait, 1)
        await asyncio.sleep(0.05)
        assert maximum_active == 2
        release.set()
        await asyncio.gather(*tasks)

    asyncio.run(run_requests())
    assert maximum_active == 2
