"""The historical production diff tool must reject unapproved write targets."""

from __future__ import annotations

import pytest

from scripts.apply_reviewed_places_v2_diff import DIFF_SHA, _target_allowed


def test_production_write_requires_approved_digest(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("PLACES_V2_DIFF_SHA", raising=False)
    url = "postgresql+psycopg://mushukistan:test@db/mushukistan"
    with pytest.raises(RuntimeError, match="approved diff SHA"):
        _target_allowed(url, "production", apply=True)
    monkeypatch.setenv("PLACES_V2_DIFF_SHA", DIFF_SHA)
    _target_allowed(url, "production", apply=True)


def test_unexpected_database_target_is_rejected() -> None:
    with pytest.raises(RuntimeError, match="unexpected production database"):
        _target_allowed(
            "postgresql+psycopg://mushukistan:test@localhost/mushukistan", "production", False
        )
    with pytest.raises(RuntimeError, match="non-isolated rehearsal"):
        _target_allowed("postgresql+psycopg://mushukistan:test@db/mushukistan", "isolated", False)
