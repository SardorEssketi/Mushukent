"""PostHog data minimisation: no email, name, phone, Telegram or free text leaves the server.

See docs/SECURITY.md ("Analytics") and docs/legal/PRIVACY_POLICY.md.
"""

from __future__ import annotations

import ast
from pathlib import Path
from types import SimpleNamespace
from uuid import uuid4

import pytest

import app.core.analytics as analytics_module
from app.api.v1.routes.auth import _identify_authenticated_user
from app.core.analytics import Analytics
from app.core.config import Settings
from app.features.auth.domain.models import AuthUser

APP_DIR = Path(__file__).resolve().parents[1] / "app"
EMAIL = "private.person@example.com"
NAME = "Private Person"
PHONE = "+998901234567"
TELEGRAM = "private_handle"
# Property names that may be attached to events. Anything else needs a privacy review.
ALLOWED_EVENT_PROPERTIES = {"photo_count", "comment_target", "login_method"}


class RecordingClient:
    def __init__(self) -> None:
        self.calls: list[tuple[str, tuple, dict]] = []

    def capture(self, *args, **kwargs):
        self.calls.append(("capture", args, kwargs))

    def set(self, *args, **kwargs):
        self.calls.append(("set", args, kwargs))


def _request(client):
    return SimpleNamespace(app=SimpleNamespace(state=SimpleNamespace(posthog_client=client)))


def _user() -> AuthUser:
    return AuthUser(
        id=uuid4(),
        email=EMAIL,
        password_hash="hash",
        name=NAME,
        phone_number=PHONE,
        telegram_username=TELEGRAM,
        preferred_language="ru",
        bio="private bio text",
    )


def test_identifying_a_user_sends_no_personal_data() -> None:
    client = RecordingClient()
    user = _user()
    _identify_authenticated_user(
        _request(client), user, event="user_logged_in", properties={"login_method": "password"}
    )
    sent = repr(client.calls)
    for secret in (EMAIL, NAME, PHONE, TELEGRAM, "private bio text", "hash"):
        assert secret not in sent, secret
    (set_call,) = [call for call in client.calls if call[0] == "set"]
    assert set_call[2]["distinct_id"] == str(user.id)
    assert set(set_call[2]["properties"]) == {"preferred_language", "is_moderator"}


def test_identification_without_analytics_is_a_no_op() -> None:
    _identify_authenticated_user(_request(None), _user(), event="user_logged_in")


def test_exception_autocapture_and_geoip_are_off(monkeypatch: pytest.MonkeyPatch) -> None:
    seen: dict[str, object] = {}

    class Capturing:
        def __init__(self, **kwargs) -> None:
            seen.update(kwargs)

        def shutdown(self) -> None:
            pass

        def flush(self) -> None:
            pass

    monkeypatch.setattr("posthog.Posthog", Capturing)
    monkeypatch.setattr(analytics_module, "configure_posthog_log_export", lambda *a: _Quiet())
    monkeypatch.setattr(analytics_module, "shutdown_posthog_log_export", lambda: None)
    analytics = Analytics()
    analytics.start(
        Settings(POSTHOG_PROJECT_TOKEN="phc_x", POSTHOG_HOST="https://eu.i.posthog.com")
    )
    analytics.stop()
    assert seen["enable_exception_autocapture"] is False
    assert seen["disable_geoip"] is True


class _Quiet:
    def info(self, *args, **kwargs) -> None:
        pass


def test_every_capture_call_in_the_codebase_uses_only_allowed_properties() -> None:
    """A new event property must be added to ALLOWED_EVENT_PROPERTIES on purpose."""
    checked = 0
    for path in APP_DIR.rglob("*.py"):
        for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute)):
                continue
            if node.func.attr not in {"capture", "set"}:
                continue
            owner = ast.unparse(node.func.value)
            if "posthog" not in owner:
                continue
            checked += 1
            for keyword in node.keywords:
                if keyword.arg != "properties":
                    continue
                if isinstance(keyword.value, ast.Dict):
                    keys = {
                        key.value for key in keyword.value.keys if isinstance(key, ast.Constant)
                    }
                    assert keys <= ALLOWED_EVENT_PROPERTIES | {
                        "preferred_language",
                        "is_moderator",
                    }, (path.name, keys)
                else:
                    # Dynamic properties are only allowed where they are the audited helper's own.
                    assert path.name == "auth.py", (path.name, ast.unparse(keyword.value))
    assert checked > 10


def test_posthog_log_export_only_carries_the_health_check() -> None:
    users = [
        path.name
        for path in APP_DIR.rglob("*.py")
        if "get_posthog_logger" in path.read_text(encoding="utf-8")
        and path.name not in {"posthog_logging.py"}
    ]
    assert users == ["health.py"]
