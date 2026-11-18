"""Production nginx configuration (infrastructure/nginx/default.conf): FIX-9, the 30 s API read
timeout, and the http2 syntax. Static checks; `nginx -t` and a live resolver check were run
against nginx:1.27-alpine when the change was made."""

from __future__ import annotations

import re
from pathlib import Path

import pytest

from app.core.upload_guard import is_upload_request

CONF = (
    Path(__file__).resolve().parents[2] / "infrastructure" / "nginx" / "default.conf"
).read_text(encoding="utf-8")


def _servers() -> list[str]:
    return re.split(r"\nserver \{", CONF)[1:]


def _location_blocks(server: str) -> dict[str, str]:
    blocks: dict[str, str] = {}
    for match in re.finditer(r"\n    location ([^{]+)\{(.*?)\n    \}", server, re.S):
        blocks[match.group(1).strip()] = match.group(2)
    return blocks


def test_backend_is_resolved_at_request_time() -> None:
    assert re.search(r"^resolver 127\.0\.0\.11 valid=10s ipv6=off;$", CONF, re.M)
    passes = re.findall(r"^\s+proxy_pass ([^;]+);", CONF, re.M)  # directives, not comments
    assert passes, "no proxy_pass found"
    # A literal upstream is resolved once at start; only variables are re-resolved (FIX-9).
    assert all(p.startswith("$backend_") for p in passes), passes


def test_http2_uses_the_current_directive() -> None:
    assert "listen 443 ssl http2" not in CONF
    for server in _servers():
        if "listen 443 ssl;" in server:
            assert "http2 on;" in server


def test_uploads_keep_the_long_timeout_and_other_api_calls_get_30_s() -> None:
    upload = "~ ^/api/v1/((posts|lost-pets|adoption-posts|cats)(/[^/]+)?/?|users/me/avatar)$"
    web_server, api_server = _servers()[1], _servers()[2]
    web, api = _location_blocks(web_server), _location_blocks(api_server)
    assert "proxy_read_timeout 180s;" in web[upload] and "proxy_read_timeout 180s;" in api[upload]
    assert "proxy_read_timeout 30s;" in web["/api/"]
    assert "proxy_read_timeout 30s;" in api["/"]


UPLOAD_REGEX = re.compile(
    r"^/api/v1/((posts|lost-pets|adoption-posts|cats)(/[^/]+)?/?|users/me/avatar)$"
)


@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/posts",
        "/api/v1/posts/",
        "/api/v1/posts/123",
        "/api/v1/lost-pets/abc",
        "/api/v1/adoption-posts",
        "/api/v1/cats/9",
        "/api/v1/users/me/avatar",
        "/api/v1/posts/123/comments",
        "/api/v1/cats/9/posts",
        "/api/v1/feed",
        "/api/v1/users/me",
    ],
)
def test_nginx_upload_paths_match_the_backend_upload_rule(path: str) -> None:
    scope = {
        "type": "http",
        "method": "POST",
        "path": path,
        "headers": [(b"content-type", b"multipart/form-data; boundary=x")],
    }
    assert bool(UPLOAD_REGEX.match(path)) == is_upload_request(scope), path


def test_json_access_log_still_on_every_server() -> None:
    servers = _servers()
    assert len(servers) == 3
    assert all("access_log /var/log/nginx/access.log ops_json;" in s for s in servers)
