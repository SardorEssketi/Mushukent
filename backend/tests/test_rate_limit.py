from __future__ import annotations

from fastapi.testclient import TestClient
from starlette.requests import Request

from app.core.config import get_settings
from app.core.rate_limit import (
    FixedWindowRateLimiter,
    InMemoryRateLimitStore,
    _client_ip,
    _rate_limit_key_and_limit,
)
from app.main import create_app


def test_anonymous_rate_limit_returns_documented_error(monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_ENABLED", "true")
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
    monkeypatch.setenv("RATE_LIMIT_ENABLED", "true")
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
    monkeypatch.setenv("RATE_LIMIT_ENABLED", "true")
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
    monkeypatch.setenv("RATE_LIMIT_ENABLED", "true")
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


def test_all_image_upload_routes_use_upload_limit(monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_UPLOAD_PER_MINUTE", "7")
    settings = get_settings()
    try:
        for method, path in (
            ("POST", "/api/v1/posts"),
            ("PATCH", "/api/v1/posts/11111111-1111-4111-8111-111111111111"),
            ("POST", "/api/v1/lost-pets"),
            ("POST", "/api/v1/adoption-posts"),
            ("POST", "/api/v1/cats"),
            ("POST", "/api/v1/users/me/avatar"),
        ):
            request = Request(
                {
                    "type": "http",
                    "method": method,
                    "path": path,
                    "headers": [(b"authorization", b"Bearer test-token")],
                    "client": ("203.0.113.10", 12345),
                    "server": ("testserver", 80),
                    "scheme": "http",
                    "query_string": b"",
                }
            )
            key, limit = _rate_limit_key_and_limit(request, settings)
            assert key.startswith("upload:")
            assert limit == 7
    finally:
        get_settings.cache_clear()


def test_forwarded_for_is_ignored_from_untrusted_client(monkeypatch) -> None:
    monkeypatch.setenv("TRUSTED_PROXY_CIDRS", "172.16.0.0/12")
    settings = get_settings()
    try:
        request = Request(
            {
                "type": "http",
                "method": "GET",
                "path": "/api/v1/health",
                "headers": [(b"x-forwarded-for", b"198.51.100.99")],
                "client": ("203.0.113.10", 12345),
                "server": ("testserver", 80),
                "scheme": "http",
                "query_string": b"",
            }
        )
        assert _client_ip(request, settings) == "203.0.113.10"
    finally:
        get_settings.cache_clear()


def test_forwarded_for_uses_nearest_untrusted_address(monkeypatch) -> None:
    monkeypatch.setenv("TRUSTED_PROXY_CIDRS", "172.16.0.0/12")
    settings = get_settings()
    try:
        request = Request(
            {
                "type": "http",
                "method": "GET",
                "path": "/api/v1/health",
                "headers": [(b"x-forwarded-for", b"198.51.100.99, 203.0.113.10")],
                "client": ("172.18.0.3", 12345),
                "server": ("testserver", 80),
                "scheme": "http",
                "query_string": b"",
            }
        )
        assert _client_ip(request, settings) == "203.0.113.10"
    finally:
        get_settings.cache_clear()
