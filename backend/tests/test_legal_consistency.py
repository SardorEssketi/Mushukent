"""The legal texts must describe what the product actually does (docs/CONTACT_PRIVACY.md).

Guards against the wording drifting back to "public phone numbers" or "no analytics/push" and keeps
the displayed document versions identical across the markdown, the in-app screen and the web page.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PRIVACY_MD = (ROOT / "docs/legal/PRIVACY_POLICY.md").read_text(encoding="utf-8")
TERMS_MD = (ROOT / "docs/legal/TERMS_OF_SERVICE.md").read_text(encoding="utf-8")
SCREEN = (
    ROOT / "frontend/lib/features/legal/presentation/screens/legal_document_screen.dart"
).read_text(encoding="utf-8")
WEB_PRIVACY = (ROOT / "frontend/web/privacy/index.html").read_text(encoding="utf-8")
STRINGS = (ROOT / "frontend/lib/core/localization/app_strings.dart").read_text(encoding="utf-8")

STALE_PHRASES = (
    "displayed publicly",
    "publicly show",
    "may publicly show",
    "lost-pet phone numbers",
    "contact details when the user explicitly consented to publish",
    "does not include analytics SDKs, advertising SDKs, crash reporting SDKs, push notifications",
    "No analytics, ads, push",
    "нет аналитики, рекламы, push",
    "analitika, reklama, push",
)


def _version(text: str, pattern: str) -> str:
    match = re.search(pattern, text)
    assert match, pattern
    return match.group(1)


def test_no_stale_public_phone_or_no_analytics_claims() -> None:
    for name, text in (
        ("privacy", PRIVACY_MD),
        ("terms", TERMS_MD),
        ("screen", SCREEN),
        ("web", WEB_PRIVACY),
        ("strings", STRINGS),
    ):
        for phrase in STALE_PHRASES:
            assert phrase not in text, (name, phrase)


def test_contact_visibility_is_described_everywhere() -> None:
    for name, text in (("privacy", PRIVACY_MD), ("terms", TERMS_MD), ("screen", SCREEN)):
        assert "signed-in" in text, name
        assert "Contact Owner" in text, name
        assert "older app versions" in text, name
        assert "per day and per week" in text, name
    assert "older app versions" in WEB_PRIVACY
    # The three consent languages state the same facts.
    assert "signed-in users" in STRINGS
    assert "older app versions" in STRINGS
    assert "в старых версиях приложения" in STRINGS
    assert "eski versiyalarda" in STRINGS


def test_analytics_and_push_are_disclosed_without_claiming_analytics_are_off() -> None:
    for name, text in (("privacy", PRIVACY_MD), ("screen", SCREEN), ("web", WEB_PRIVACY)):
        assert "PostHog" in text, name
        assert "Firebase Cloud Messaging" in text, name
        assert "only when configured by the operator" in text, name


def test_displayed_versions_match_across_documents() -> None:
    privacy = _version(PRIVACY_MD, r"Version: (\d{4}-\d{2}-\d{2})")
    terms = _version(TERMS_MD, r"Version: (\d{4}-\d{2}-\d{2})")
    assert f"title: 'Privacy Policy',\n  version: '{privacy}'" in SCREEN.replace("\r\n", "\n")
    assert f"title: 'Terms of Service',\n  version: '{terms}'" in SCREEN.replace("\r\n", "\n")
    assert f"Version: {privacy}" in WEB_PRIVACY
