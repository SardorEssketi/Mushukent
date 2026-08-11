from __future__ import annotations

import json
from urllib import error

import pytest
from fastapi import HTTPException

from app.core.config import Settings
from app.features.auth.infrastructure import email as email_module
from app.features.auth.infrastructure.email import EmailVerificationSender


class StubResponse:
    status = 200

    def __enter__(self) -> "StubResponse":
        return self

    def __exit__(self, *args: object) -> None:
        return None


def _production_settings(**overrides: object) -> Settings:
    values: dict[str, object] = {
        "APP_ENV": "production",
        "APP_DEBUG": False,
        "ENABLE_API_DOCS": False,
        "CORS_ALLOWED_ORIGINS": "https://mushukistan.uz",
        "PUBLIC_APP_BASE_URL": "https://mushukistan.uz",
        "POSTGRES_PASSWORD": "strong-db-password",
        "DATABASE_URL": "postgresql+psycopg://mushukistan:strong-db-password@db:5432/mushukistan",
        "JWT_SECRET_KEY": "a" * 64,
        "RESEND_API_KEY": "re_test_key",
        "RESEND_FROM_EMAIL": "noreply@mushukistan.uz",
    }
    values.update(overrides)
    return Settings(_env_file=None, **values)


def test_verification_email_uses_resend_http_api(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, object] = {}

    def fake_urlopen(resend_request, timeout: int):
        captured["url"] = resend_request.full_url
        captured["timeout"] = timeout
        captured["headers"] = dict(resend_request.header_items())
        captured["payload"] = json.loads(resend_request.data.decode("utf-8"))
        return StubResponse()

    monkeypatch.setattr(email_module.request, "urlopen", fake_urlopen)
    settings = _production_settings()

    EmailVerificationSender(settings).send_verification_email(
        email="user@example.com",
        token="verification-token",
    )

    assert captured["url"] == "https://api.resend.com/emails"
    assert captured["timeout"] == 10
    assert captured["headers"]["Authorization"] == "Bearer re_test_key"
    assert captured["headers"]["Content-type"] == "application/json"
    assert captured["payload"] == {
        "from": "noreply@mushukistan.uz",
        "to": ["user@example.com"],
        "subject": "Verify your Mushukistan account",
        "text": (
            "Confirm your Mushukistan account by opening this link:\n\n"
            "https://mushukistan.uz/verify-email?token=verification-token\n\n"
            "If you did not create this account, ignore this email."
        ),
    }


def test_verification_email_maps_resend_failures(monkeypatch: pytest.MonkeyPatch) -> None:
    def fake_urlopen(resend_request, timeout: int):
        raise error.URLError("network unavailable")

    monkeypatch.setattr(email_module.request, "urlopen", fake_urlopen)
    settings = _production_settings()

    with pytest.raises(HTTPException) as excinfo:
        EmailVerificationSender(settings).send_verification_email(
            email="user@example.com",
            token="verification-token",
        )

    assert excinfo.value.status_code == 502
    assert excinfo.value.detail["error"]["code"] == "EMAIL_DELIVERY_FAILED"


def test_production_settings_require_resend_api_key() -> None:
    with pytest.raises(ValueError, match="RESEND_API_KEY"):
        _production_settings(RESEND_API_KEY="")
