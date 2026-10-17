from __future__ import annotations

import importlib.util
import io
from email.message import Message
from pathlib import Path
from urllib.error import HTTPError

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "r2_disposable_smoke.py"
spec = importlib.util.spec_from_file_location("r2_disposable_smoke", SCRIPT)
smoke = importlib.util.module_from_spec(spec)
spec.loader.exec_module(smoke)


class _Response:
    status = 200

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False


def test_public_read_sends_explicit_user_agent_not_urllib_default() -> None:
    seen = {}

    def opener(request, timeout):
        seen["ua"] = request.get_header("User-agent")
        return _Response()

    ok, message = smoke.public_read("https://media.example/k.png", opener=opener)
    assert ok and "PASS" in message
    assert seen["ua"] == smoke.USER_AGENT
    assert not seen["ua"].startswith("Python-urllib")


def test_public_read_reports_status_and_safe_headers_without_url_or_body() -> None:
    headers = Message()
    headers["Server"] = "cloudflare"
    headers["CF-RAY"] = "abc-WAW"
    headers["Set-Cookie"] = "secret=1"

    def opener(request, timeout):
        body = io.BytesIO(b"error code: 1010")
        raise HTTPError(request.full_url, 403, "Forbidden", headers, body)

    ok, message = smoke.public_read("https://media.example/private/key.png", opener=opener)
    assert not ok
    assert "HTTP 403" in message and "cloudflare" in message and "WAF" in message
    assert "media.example" not in message and "key.png" not in message
    assert "secret" not in message and "1010" not in message
