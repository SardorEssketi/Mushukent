from __future__ import annotations

from fastapi.testclient import TestClient
from starlette.requests import Request

from app.core.config import get_settings
from app.core.rate_limit import (
    FixedWindowRateLimiter,
    InMemoryRateLimitStore,
    _rate_limit_key_and_limit,
)
from app.main import create_app


def test_anonymous_rate_limit_returns_documented_error(monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_ANON_PER_MINUTE", "1")
    monkeypatch.setenv("RATE_LIMIT_AUTH_PER_MINUTE", "10")
    monkeypatch.setenv("RATE_LIMIT_UPLOAD_PER_MINUTE", "10")
    monkeypatch.setenv("RATE_LIMIT_USER_PER_MINUTE", "10")
    get_settings.cache_clear()

    try:
        app = create_app()
        with TestClient(app) as client:
            first_response = client.get("/api/v1/health")
            second_response = client.get("/api/v1/health")

        assert first_response.status_code == 200
        assert second_response.status_code == 429
        assert second_response.headers["Retry-After"]
        assert second_response.json() == {
            "success": False,
            "error": {
                "code": "RATE_LIMIT_EXCEEDED",
                "message": "Too many requests.",
            },
        }
    finally:
        get_settings.cache_clear()


def test_auth_endpoints_use_stricter_rate_limit(monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_ANON_PER_MINUTE", "100")
    monkeypatch.setenv("RATE_LIMIT_AUTH_PER_MINUTE", "1")
    monkeypatch.setenv("RATE_LIMIT_UPLOAD_PER_MINUTE", "100")
    monkeypatch.setenv("RATE_LIMIT_USER_PER_MINUTE", "100")
    get_settings.cache_clear()

    try:
        app = create_app()
        with TestClient(app) as client:
            first_response = client.post("/api/v1/auth/login", json={})
            second_response = client.post("/api/v1/auth/login", json={})

        assert first_response.status_code == 422
        assert second_response.status_code == 429
        assert second_response.json()["error"]["code"] == "RATE_LIMIT_EXCEEDED"
    finally:
        get_settings.cache_clear()


def test_public_read_endpoints_use_public_read_rate_limit(monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_ANON_PER_MINUTE", "1")
    monkeypatch.setenv("RATE_LIMIT_PUBLIC_READ_PER_MINUTE", "2")
    monkeypatch.setenv("RATE_LIMIT_AUTH_PER_MINUTE", "10")
    monkeypatch.setenv("RATE_LIMIT_UPLOAD_PER_MINUTE", "10")
    monkeypatch.setenv("RATE_LIMIT_USER_PER_MINUTE", "10")
    get_settings.cache_clear()

    try:
        settings = get_settings()
        request = Request(
            {
                "type": "http",
                "method": "GET",
                "path": "/api/v1/cats",
                "headers": [],
                "client": ("203.0.113.10", 12345),
                "server": ("testserver", 80),
                "scheme": "http",
                "query_string": b"",
            }
        )

        key, limit = _rate_limit_key_and_limit(request, settings)

        assert key == "public-read:ip:203.0.113.10"
        assert limit == 2
    finally:
        get_settings.cache_clear()


def test_options_requests_are_not_rate_limited(monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_ANON_PER_MINUTE", "1")
    monkeypatch.setenv("RATE_LIMIT_PUBLIC_READ_PER_MINUTE", "1")
    monkeypatch.setenv("RATE_LIMIT_AUTH_PER_MINUTE", "1")
    monkeypatch.setenv("RATE_LIMIT_UPLOAD_PER_MINUTE", "1")
    monkeypatch.setenv("RATE_LIMIT_USER_PER_MINUTE", "1")
    get_settings.cache_clear()

    try:
        app = create_app()
        with TestClient(app) as client:
            first_response = client.options("/api/v1/cats")
            second_response = client.options("/api/v1/cats")

        assert first_response.status_code != 429
        assert second_response.status_code != 429
    finally:
        get_settings.cache_clear()


def test_rate_limiter_uses_replaceable_store() -> None:
    now = 100.0
    limiter = FixedWindowRateLimiter(
        store=InMemoryRateLimitStore(),
        window_seconds=60,
        clock=lambda: now,
    )

    assert limiter.check(key="auth:ip:test", limit=1).allowed is True
    blocked = limiter.check(key="auth:ip:test", limit=1)

    assert blocked.allowed is False
    assert blocked.retry_after_seconds == 60
