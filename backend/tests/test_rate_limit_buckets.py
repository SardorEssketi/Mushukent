"""Rate-limit buckets that work behind carrier NAT (load audit LT-08, FIX-7).

* read-only public GETs (map lost-pet pins, detail pages, comments, a cat's posts) use the
  public-read bucket instead of the 30/min anonymous one;
* view telemetry has its own bucket and no longer competes with real reads;
* POST /auth/refresh is keyed by the refresh session, with a per-IP backstop; login and
  register stay per IP.
The numeric per-IP ceilings are unchanged.
"""

from __future__ import annotations

from uuid import uuid4

import pytest
from fastapi.testclient import TestClient
from starlette.requests import Request

from app.core.config import get_settings
from app.core.rate_limit import _rate_limit_key_and_limit
from app.main import create_app


def _request(method: str, path: str) -> Request:
    return Request(
        {
            "type": "http",
            "method": method,
            "path": path,
            "headers": [],
            "client": ("203.0.113.10", 12345),
            "server": ("testserver", 80),
            "scheme": "http",
            "query_string": b"",
        }
    )


@pytest.fixture()
def settings(monkeypatch):
    for name, value in {
        "RATE_LIMIT_ENABLED": "true",
        "RATE_LIMIT_ANON_PER_MINUTE": "30",
        "RATE_LIMIT_PUBLIC_READ_PER_MINUTE": "180",
        "RATE_LIMIT_AUTH_PER_MINUTE": "10",
        "RATE_LIMIT_USER_PER_MINUTE": "60",
        "RATE_LIMIT_UPLOAD_PER_MINUTE": "10",
    }.items():
        monkeypatch.setenv(name, value)
    get_settings.cache_clear()
    yield get_settings()
    get_settings.cache_clear()


ID = str(uuid4())


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/lost-pets/map",
        f"/api/v1/posts/{ID}",
        f"/api/v1/posts/{ID}/comments",
        f"/api/v1/cats/{ID}",
        f"/api/v1/cats/{ID}/posts",
        f"/api/v1/lost-pets/{ID}",
        f"/api/v1/lost-pets/{ID}/comments",
        f"/api/v1/adoption-posts/{ID}",
        f"/api/v1/adoption-posts/{ID}/comments",
        f"/api/v1/places/{ID}",
    ],
)
def test_read_only_public_gets_use_the_public_read_bucket(settings, path: str) -> None:
    key, limit = _rate_limit_key_and_limit(_request("GET", path), settings)
    assert key == "public-read:ip:203.0.113.10"
    assert limit == 180


@pytest.mark.parametrize(
    "path",
    ["/api/v1/views/seen", f"/api/v1/posts/{ID}/views", f"/api/v1/lost-pets/{ID}/views"],
)
def test_view_telemetry_has_its_own_bucket(settings, path: str) -> None:
    key, limit = _rate_limit_key_and_limit(_request("POST", path), settings)
    assert key == "telemetry:ip:203.0.113.10"
    assert limit == 30  # defaults to the anonymous ceiling for guests (configurable)


def test_writes_and_private_reads_keep_their_buckets(settings) -> None:
    assert _rate_limit_key_and_limit(_request("POST", f"/api/v1/posts/{ID}/comments"), settings)[
        0
    ] == ("anon:ip:203.0.113.10")
    assert _rate_limit_key_and_limit(_request("GET", "/api/v1/notifications"), settings)[0] == (
        "anon:ip:203.0.113.10"
    )
    assert _rate_limit_key_and_limit(_request("POST", "/api/v1/auth/login"), settings) == (
        "auth:ip:203.0.113.10",
        10,
    )


def test_refresh_is_limited_per_session_not_per_ip(settings, monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_REFRESH_PER_MINUTE", "2")
    get_settings.cache_clear()
    app = create_app()
    with TestClient(app) as client:
        same = [
            client.post("/api/v1/auth/refresh", json={"refresh_token": "session-a-" + "x" * 40})
            for _ in range(3)
        ]
        # Ten other sessions behind the same address are not affected by session A's limit,
        # and not by the 10/min per-IP auth limit either.
        others = [
            client.post("/api/v1/auth/refresh", json={"refresh_token": f"session-{n}-" + "y" * 40})
            for n in range(12)
        ]
        login = [client.post("/api/v1/auth/login", json={}) for _ in range(11)]
    assert [response.status_code for response in same][:2] != [429, 429]
    assert same[2].status_code == 429
    assert all(response.status_code != 429 for response in others)
    assert login[-1].status_code == 429  # login stays per IP


def test_refresh_has_a_per_ip_backstop(settings, monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_REFRESH_IP_PER_MINUTE", "5")
    get_settings.cache_clear()
    app = create_app()
    with TestClient(app) as client:
        codes = [
            client.post(
                "/api/v1/auth/refresh", json={"refresh_token": f"t-{n}-" + "z" * 40}
            ).status_code
            for n in range(7)
        ]
    assert codes[:5].count(429) == 0
    assert codes[5:] == [429, 429]
