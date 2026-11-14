"""The rate limiter as plain ASGI middleware (load audit step 2, fix C).

It used to be ``@app.middleware("http")`` (Starlette ``BaseHTTPMiddleware``), which runs every
request through an extra task, memory streams and a re-wrapped response. These tests pin the
observable behaviour to what the old middleware produced: the same 429 bytes and headers (with
CORS), the refresh body still reaching the route intact (also when it arrives in chunks), other
bodies untouched, and OPTIONS never limited.
"""

from __future__ import annotations

import asyncio
import json

import pytest
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

from app.core.config import get_settings
from app.main import create_app

RATE_LIMIT_BODY = (
    b'{"success":false,"error":{"code":"RATE_LIMIT_EXCEEDED","message":"Too many requests."}}'
)


@pytest.fixture()
def limited_app(monkeypatch):
    for name, value in {
        "RATE_LIMIT_ENABLED": "true",
        "RATE_LIMIT_ANON_PER_MINUTE": "1",
        "RATE_LIMIT_PUBLIC_READ_PER_MINUTE": "1",
        "RATE_LIMIT_AUTH_PER_MINUTE": "50",
        "RATE_LIMIT_REFRESH_PER_MINUTE": "1",
        "RATE_LIMIT_REFRESH_IP_PER_MINUTE": "50",
    }.items():
        monkeypatch.setenv(name, value)
    get_settings.cache_clear()
    app = create_app()
    seen: list[bytes] = []

    # Stand-in routes placed before the real ones: they record the body the route receives.
    async def echo(request: Request) -> dict:
        body = await request.body()
        seen.append(body)
        return {"len": len(body)}

    app.router.add_api_route("/api/v1/auth/refresh", echo, methods=["POST"])
    app.router.add_api_route("/api/v1/feedback", echo, methods=["POST"])
    app.router.routes.insert(0, app.router.routes.pop())
    app.router.routes.insert(0, app.router.routes.pop())
    yield app, seen
    get_settings.cache_clear()


def call(app, method: str, path: str, *, headers=(), chunks=(b"",)) -> dict:
    """Drive the ASGI app directly and capture the raw response messages."""
    scope = {
        "type": "http",
        "asgi": {"version": "3.0"},
        "http_version": "1.1",
        "method": method,
        "scheme": "https",
        "path": path,
        "raw_path": path.encode(),
        "query_string": b"",
        "root_path": "",
        "headers": [(k.encode(), v.encode()) for k, v in headers],
        "client": ("203.0.113.7", 50000),
        "server": ("testserver", 443),
        "state": {},
    }
    incoming = [
        {"type": "http.request", "body": chunk, "more_body": i < len(chunks) - 1}
        for i, chunk in enumerate(chunks)
    ]
    sent: list[dict] = []

    async def receive():
        if incoming:
            return incoming.pop(0)
        await asyncio.sleep(3600)  # a client that stays connected
        return {"type": "http.disconnect"}

    async def send(message):
        sent.append(message)

    asyncio.run(app(scope, receive, send))
    start = next(m for m in sent if m["type"] == "http.response.start")
    body = b"".join(m.get("body", b"") for m in sent if m["type"] == "http.response.body")
    return {"status": start["status"], "headers": start["headers"], "body": body}


def test_the_rate_limiter_is_not_a_base_http_middleware(limited_app) -> None:
    app, _ = limited_app
    assert all(m.cls is not BaseHTTPMiddleware for m in app.user_middleware)


def test_a_limited_request_gets_the_same_429_bytes_and_headers(limited_app) -> None:
    app, _ = limited_app
    origin = ("origin", "http://localhost:3000")
    assert call(app, "GET", "/api/v1/health", headers=[origin])["status"] == 200
    limited = call(app, "GET", "/api/v1/health", headers=[origin])
    assert limited["status"] == 429
    assert limited["body"] == RATE_LIMIT_BODY
    # Exactly what BaseHTTPMiddleware sent (captured before the rewrite), CORS included.
    # Retry-After counts down from the window (60 s) to whole seconds, so it reads 59 or 60.
    headers = list(limited["headers"])
    assert headers[0][0] == b"retry-after" and headers[0][1] in {b"59", b"60"}
    assert headers[1:] == [
        (b"content-length", str(len(RATE_LIMIT_BODY)).encode()),
        (b"content-type", b"application/json"),
        (b"access-control-allow-origin", b"http://localhost:3000"),
        (b"vary", b"Origin"),
    ]


def test_a_refresh_body_reaches_the_route_intact_even_in_chunks(limited_app) -> None:
    app, seen = limited_app
    payload = json.dumps({"refresh_token": "session-" + "a" * 60}).encode()
    chunks = (payload[:10], payload[10:30], payload[30:])
    first = call(app, "POST", "/api/v1/auth/refresh", chunks=chunks)
    assert first["status"] == 200
    assert seen == [payload]
    # The session budget (1/min) still applies to the same refresh token.
    assert call(app, "POST", "/api/v1/auth/refresh", chunks=(payload,))["status"] == 429
    assert seen == [payload]


def test_an_unparsable_refresh_body_falls_back_to_the_ip_bucket(limited_app) -> None:
    app, seen = limited_app
    assert call(app, "POST", "/api/v1/auth/refresh", chunks=(b"not json",))["status"] == 200
    assert seen == [b"not json"]


def test_other_bodies_are_streamed_to_the_route_untouched(limited_app) -> None:
    app, seen = limited_app
    chunks = (b'{"message":', b' "hello', b'"}')
    response = call(app, "POST", "/api/v1/feedback", chunks=chunks)
    assert response["status"] == 200
    assert seen == [b"".join(chunks)]


def test_options_requests_are_never_limited(limited_app) -> None:
    app, _ = limited_app
    headers = [
        ("origin", "http://localhost:3000"),
        ("access-control-request-method", "GET"),
    ]
    statuses = [call(app, "OPTIONS", "/api/v1/health", headers=headers)["status"] for _ in range(3)]
    assert 429 not in statuses
