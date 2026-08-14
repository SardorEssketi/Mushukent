from __future__ import annotations

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core import errors
from app.core.errors import register_error_handlers


class _FakeLogger:
    def __init__(self) -> None:
        self.calls: list[dict[str, object]] = []

    def error(self, event: str, **kwargs: object) -> None:
        self.calls.append({"event": event, **kwargs})


def test_unhandled_exception_logs_traceback_without_exposing_it(monkeypatch) -> None:
    fake_logger = _FakeLogger()
    monkeypatch.setattr(errors, "logger", fake_logger)

    app = FastAPI()
    register_error_handlers(app)

    @app.get("/boom")
    def boom() -> None:
        raise RuntimeError("database password leaked in exception")

    with TestClient(app, raise_server_exceptions=False) as client:
        response = client.get("/boom")

    assert response.status_code == 500
    assert response.json() == {
        "success": False,
        "error": {
            "code": "INTERNAL_SERVER_ERROR",
            "message": "An unexpected error occurred.",
        },
    }
    assert fake_logger.calls
    log_call = fake_logger.calls[0]
    assert log_call["event"] == "unhandled_exception"
    assert log_call["method"] == "GET"
    assert log_call["path"] == "/boom"
    exc_info = log_call["exc_info"]
    assert isinstance(exc_info, tuple)
    assert exc_info[0] is RuntimeError
    assert isinstance(exc_info[1], RuntimeError)
    assert exc_info[2] is not None
