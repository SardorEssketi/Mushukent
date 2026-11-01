"""Exercise the actual Uvicorn exception logger without a DB or external storage."""

import io
import logging
import socket
from contextlib import contextmanager
from threading import Thread
from time import monotonic, sleep
from unittest.mock import Mock
from uuid import uuid4

import httpx
import pytest
import uvicorn
from fastapi import FastAPI
from PIL import Image
from sqlalchemy.exc import SQLAlchemyError
from starlette.responses import StreamingResponse

from app.core.errors import register_error_handlers
from app.core.publication_diagnostics import PublicationDiagnosticsMiddleware
from app.infrastructure.storage.service import MediaStorageService, UploadPurpose

MARKERS = (
    "SYNTHETIC_PRIVATE_POST_TEXT",
    "synthetic-private-filename.jpg",
    "+998901112233",
    "SYNTHETIC_BEARER_CREDENTIAL",
)
PRIVATE = " | ".join(MARKERS)


@contextmanager
def local_server(app):
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    port = listener.getsockname()[1]
    server = uvicorn.Server(uvicorn.Config(app, lifespan="off", log_config=None, access_log=False))
    thread = Thread(target=lambda: server.run(sockets=[listener]), daemon=True)
    thread.start()
    try:
        deadline = monotonic() + 5
        while not server.started and monotonic() < deadline:
            sleep(0.01)
        assert server.started
        with httpx.Client(base_url=f"http://127.0.0.1:{port}", timeout=3) as client:
            yield client
    finally:
        server.should_exit = True
        thread.join(5)
        listener.close()
        assert not thread.is_alive()


def application():
    app = FastAPI()
    register_error_handlers(app)
    app.add_middleware(PublicationDiagnosticsMiddleware)
    return app


def assert_private_absent(capsys, caplog):
    captured = capsys.readouterr()
    logs = captured.out + captured.err + caplog.text
    for marker in MARKERS:
        assert marker not in logs
    return logs


@pytest.mark.parametrize(
    "method,path",
    [("POST", f"/api/v1/{kind}") for kind in ("posts", "lost-pets", "adoption-posts")]
    + [("PATCH", f"/api/v1/{kind}/{uuid4()}") for kind in ("posts", "lost-pets", "adoption-posts")]
    + [("GET", f"/api/v1/publication-operations/{uuid4()}")],
)
@pytest.mark.parametrize("source", ["database", "media"])
def test_publication_exceptions_are_private_in_app_stderr_and_uvicorn(
    method, path, source, capsys, caplog
):
    app = application()
    storage = Mock()
    storage.upload.side_effect = RuntimeError(PRIVATE)
    media = MediaStorageService(storage=storage)
    buffer = io.BytesIO()
    Image.new("RGB", (16, 16)).save(buffer, format="JPEG")

    def fail():
        if source == "database":
            raise SQLAlchemyError(PRIVATE)
        media.upload_image(
            purpose=UploadPurpose.POST_OBSERVATION,
            entity_id=uuid4(),
            content=buffer.getvalue(),
            content_type="image/jpeg",
            original_filename=MARKERS[1],
        )

    app.add_api_route(path, fail, methods=[method])
    request_id = str(uuid4())
    with caplog.at_level(logging.ERROR, logger="uvicorn.error"), local_server(app) as client:
        response = client.request(method, path, headers={"X-Request-ID": request_id})
        assert response.status_code == 500
        assert response.headers["X-Request-ID"] == request_id
        assert response.json()["error"]["code"] == "INTERNAL_SERVER_ERROR"
    logs = assert_private_absent(capsys, caplog)
    assert request_id in logs
    assert ("SQLAlchemyError" if source == "database" else "StorageOperationError") in logs


def test_started_response_raises_only_sanitized_exception_to_uvicorn(capsys, caplog):
    app = application()

    async def chunks():
        yield b"partial"
        raise RuntimeError(PRIVATE)

    @app.post("/api/v1/posts")
    async def fail():
        return StreamingResponse(chunks())

    with caplog.at_level(logging.ERROR, logger="uvicorn.error"), local_server(app) as client:
        with pytest.raises(httpx.RemoteProtocolError):
            client.post("/api/v1/posts")
    logs = assert_private_absent(capsys, caplog)
    assert "PublicationResponseAborted" in logs


def test_unrelated_errors_keep_their_existing_server_diagnostics(capsys, caplog):
    app = application()

    @app.get("/unrelated")
    def fail():
        raise RuntimeError("SYNTHETIC_UNRELATED_ERROR")

    with caplog.at_level(logging.ERROR, logger="uvicorn.error"), local_server(app) as client:
        assert client.get("/unrelated").status_code == 500
    assert "SYNTHETIC_UNRELATED_ERROR" in caplog.text
