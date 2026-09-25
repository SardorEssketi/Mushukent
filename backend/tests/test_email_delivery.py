from __future__ import annotations

import json
from html.parser import HTMLParser
from urllib import error
from urllib.parse import parse_qs, quote, urlsplit

import pytest
from fastapi import HTTPException

from app.core.config import Settings
from app.features.auth.infrastructure import email as email_module
from app.features.auth.infrastructure.email import (
    RESEND_USER_AGENT,
    AccountDeletionConfirmationSender,
    EmailVerificationSender,
)


class StubResponse:
    status = 200

    def __enter__(self) -> "StubResponse":
        return self

    def __exit__(self, *args: object) -> None:
        return None


class AnchorCollector(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.anchors: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text = ""

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag == "a":
            self._href = dict(attrs).get("href")
            self._text = ""

    def handle_data(self, data: str) -> None:
        if self._href is not None:
            self._text += data

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._href is not None:
            self.anchors.append((self._href, self._text.strip()))
            self._href = None
            self._text = ""


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
        "GOOGLE_OAUTH_CLIENT_ID": "web-client.apps.googleusercontent.com",
        "R2_ACCOUNT_ID": "test-account",
        "R2_ACCESS_KEY_ID": "test-access-key",
        "R2_SECRET_ACCESS_KEY": "test-secret-key",
        "R2_PUBLIC_BASE_URL": "https://media.mushukistan.uz",
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

    token = "header.payload/with+reserved="
    EmailVerificationSender(settings).send_verification_email(
        email="user@example.com",
        token=token,
    )

    assert captured["url"] == "https://api.resend.com/emails"
    assert captured["timeout"] == 10
    assert captured["headers"]["Authorization"] == "Bearer re_test_key"
    assert captured["headers"]["Content-type"] == "application/json"
    assert captured["headers"]["User-agent"] == RESEND_USER_AGENT
    payload = captured["payload"]
    assert isinstance(payload, dict)
    assert payload["from"] == "noreply@mushukistan.uz"
    assert payload["to"] == ["user@example.com"]
    assert payload["subject"] == "Verify your Mushukistan account"

    expected_url = "https://mushukistan.uz/verify-email?token=" + quote(token, safe="")
    text = payload["text"]
    html = payload["html"]
    assert isinstance(text, str)
    assert isinstance(html, str)
    assert expected_url in text
    assert "Mushukistan" in text
    assert "Verify your email" in text
    assert "This link expires in 24 hours." in text
    assert "If you did not create this account, ignore this email." in text

    anchors = AnchorCollector()
    anchors.feed(html)
    assert [label for _, label in anchors.anchors] == [
        "Verify email address",
        expected_url,
    ]
    assert all(href == expected_url for href, _ in anchors.anchors)
    assert all(parse_qs(urlsplit(href).query)["token"] == [token] for href, _ in anchors.anchors)
    assert "Verify your email" in html
    assert "Button not working? Copy and paste this link:" in html
    assert "This link expires in 24 hours." in html
    assert "If you didn't create this account, you can ignore this email." in html
    assert "<script" not in html.casefold()


def test_account_deletion_email_uses_resend_http_api(monkeypatch: pytest.MonkeyPatch) -> None:
    captured: dict[str, object] = {}

    def fake_urlopen(resend_request, timeout: int):
        captured["url"] = resend_request.full_url
        captured["timeout"] = timeout
        captured["headers"] = dict(resend_request.header_items())
        captured["payload"] = json.loads(resend_request.data.decode("utf-8"))
        return StubResponse()

    monkeypatch.setattr(email_module.request, "urlopen", fake_urlopen)
    settings = _production_settings()

    AccountDeletionConfirmationSender(settings).send_confirmation_email(
        email="user@example.com",
        token="deletion-token",
    )

    assert captured["url"] == "https://api.resend.com/emails"
    assert captured["timeout"] == 10
    assert captured["headers"]["Authorization"] == "Bearer re_test_key"
    assert captured["headers"]["Content-type"] == "application/json"
    assert captured["headers"]["User-agent"] == RESEND_USER_AGENT
    assert captured["payload"] == {
        "from": "noreply@mushukistan.uz",
        "to": ["user@example.com"],
        "subject": "Confirm deletion of your Mushukistan account",
        "text": (
            "Open this link to confirm deletion of your Mushukistan account:\n\n"
            "https://mushukistan.uz/delete-account?token=deletion-token\n\n"
            "After the page opens, press Confirm account deletion to complete deletion. "
            "This link is time-limited. If you did not request account deletion, "
            "ignore this email and your account will not be deleted."
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


def test_production_settings_require_google_oauth_client_id() -> None:
    with pytest.raises(ValueError, match="GOOGLE_OAUTH_CLIENT_ID"):
        _production_settings(GOOGLE_OAUTH_CLIENT_ID="")
