"""Contact reveal: explicit endpoint, per-user quota, legacy compatibility and leak scans.

See docs/CONTACT_PRIVACY.md. The reveal log must never store or log a contact value.
"""

from __future__ import annotations

import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from structlog.testing import capture_logs

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401
    API,
    client,
    make_adoption,
    make_lost_pet,
    make_user,
    runtime,
)

PHONE = "+998901234567"
TELEGRAM = "owner_handle"
REVEAL = {"X-Contact-Mode": "reveal"}


@pytest.fixture()
def limits(monkeypatch):
    """Tight, known limits for the shared settings object the reveal service reads."""
    from app.core.config import get_settings

    settings = get_settings()
    monkeypatch.setattr(settings, "contact_reveal_max_per_day", 2)
    monkeypatch.setattr(settings, "contact_reveal_max_per_week", 3)
    monkeypatch.setattr(settings, "contact_reveal_min_account_age_hours", 0)
    monkeypatch.setattr(settings, "contact_legacy_detail_enabled", True)
    return settings


def _with_telegram(runtime, lost_id=None, adoption_id=None):
    from app.infrastructure.db.models import schema

    with runtime.manager.session_scope() as session:
        if lost_id:
            session.get(schema.LostPet, lost_id).owner_telegram_username = TELEGRAM
        if adoption_id:
            session.get(schema.AdoptionPost, adoption_id).owner_telegram_username = TELEGRAM


def _reveal_rows(runtime):
    from sqlalchemy import select

    from app.infrastructure.db.models import schema

    with runtime.manager.session_scope() as session:
        return list(session.scalars(select(schema.ContactReveal)))


def _shift_reveals(runtime, delta: timedelta):
    from sqlalchemy import update

    from app.infrastructure.db.models import schema

    with runtime.manager.session_scope() as session:
        session.execute(
            update(schema.ContactReveal).values(created_at=schema.ContactReveal.created_at - delta)
        )


def test_reveal_requires_sign_in_and_returns_contact_uncached(client, runtime, limits) -> None:
    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    adoption = make_adoption(runtime, owner)
    _with_telegram(runtime, lost, adoption)
    viewer = make_user(runtime, "Viewer")
    for kind, post in (("lost-pets", lost), ("adoption-posts", adoption)):
        url = f"{API}/{kind}/{post}/contact-reveal"
        assert client.post(url).status_code == 401
        response = client.post(url, headers=viewer.h)
        assert response.status_code == 200, response.text
        assert response.json()["data"] == {"phone_number": PHONE, "telegram_username": TELEGRAM}
        assert "no-store" in response.headers["cache-control"]
        assert "Authorization" in response.headers["vary"]


def test_owner_blocked_and_resolved_cannot_reveal(client, runtime, limits) -> None:
    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    viewer = make_user(runtime, "Viewer")
    url = f"{API}/lost-pets/{lost}/contact-reveal"
    assert client.post(url, headers=owner.h).status_code == 403
    assert client.post(f"{API}/users/{owner.id}/block", headers=viewer.h).status_code in (
        200,
        201,
        204,
    )
    assert client.post(url, headers=viewer.h).status_code == 404
    assert client.delete(f"{API}/users/{owner.id}/block", headers=viewer.h).status_code in (
        200,
        204,
    )
    resolved = client.patch(
        f"{API}/lost-pets/{lost}/resolution", headers=owner.h, json={"is_resolved": True}
    )
    assert resolved.status_code == 200, resolved.text
    assert client.post(url, headers=viewer.h).status_code == 404
    assert _reveal_rows(runtime) == []


def test_daily_limit_counts_unique_posts_and_repeat_reveal_is_free(client, runtime, limits) -> None:
    owner = make_user(runtime, "Owner")
    posts = [make_lost_pet(runtime, owner, f"Pet{i}") for i in range(3)]
    viewer = make_user(runtime, "Viewer")
    urls = [f"{API}/lost-pets/{post}/contact-reveal" for post in posts]
    assert client.post(urls[0], headers=viewer.h).status_code == 200
    assert client.post(urls[1], headers=viewer.h).status_code == 200
    blocked = client.post(urls[2], headers=viewer.h)
    assert blocked.status_code == 429
    assert int(blocked.headers["retry-after"]) > 0
    assert client.post(urls[0], headers=viewer.h).status_code == 200
    assert len(_reveal_rows(runtime)) == 2
    other = make_user(runtime, "Other")
    assert client.post(urls[2], headers=other.h).status_code == 200


def test_quota_is_a_rolling_window_and_has_a_weekly_cap(client, runtime, limits) -> None:
    owner = make_user(runtime, "Owner")
    posts = [make_lost_pet(runtime, owner, f"Pet{i}") for i in range(4)]
    viewer = make_user(runtime, "Viewer")
    urls = [f"{API}/lost-pets/{post}/contact-reveal" for post in posts]
    assert client.post(urls[0], headers=viewer.h).status_code == 200
    assert client.post(urls[1], headers=viewer.h).status_code == 200
    assert client.post(urls[2], headers=viewer.h).status_code == 429
    _shift_reveals(runtime, timedelta(hours=25))
    assert client.post(urls[2], headers=viewer.h).status_code == 200
    # Three reveals inside seven days: the weekly cap (3) blocks a fourth despite daily room.
    _shift_reveals(runtime, timedelta(hours=25))
    blocked = client.post(urls[3], headers=viewer.h)
    assert blocked.status_code == 429
    assert blocked.json()["error"]["code"] == "CONTACT_REVEAL_LIMIT"


def test_parallel_requests_cannot_exceed_the_quota(client, runtime, limits, monkeypatch) -> None:
    monkeypatch.setattr(limits, "contact_reveal_max_per_day", 3)
    monkeypatch.setattr(limits, "contact_reveal_max_per_week", 30)
    owner = make_user(runtime, "Owner")
    posts = [make_lost_pet(runtime, owner, f"Pet{i}") for i in range(8)]
    viewer = make_user(runtime, "Viewer")

    def reveal(post):
        return client.post(f"{API}/lost-pets/{post}/contact-reveal", headers=viewer.h).status_code

    with ThreadPoolExecutor(max_workers=8) as pool:
        codes = list(pool.map(reveal, posts))
    assert sorted(codes).count(200) == 3
    assert set(codes) <= {200, 429}
    assert len(_reveal_rows(runtime)) == 3


def test_minimum_account_age_blocks_brand_new_accounts(
    client, runtime, limits, monkeypatch
) -> None:
    monkeypatch.setattr(limits, "contact_reveal_min_account_age_hours", 24)
    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    viewer = make_user(runtime, "Viewer")
    response = client.post(f"{API}/lost-pets/{lost}/contact-reveal", headers=viewer.h)
    assert response.status_code == 429
    assert int(response.headers["retry-after"]) > 0


def test_reveal_mode_detail_never_carries_contact_but_owner_keeps_theirs(
    client, runtime, limits
) -> None:
    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    adoption = make_adoption(runtime, owner)
    viewer = make_user(runtime, "Viewer")
    for kind, post in (("lost-pets", lost), ("adoption-posts", adoption)):
        detail = client.get(f"{API}/{kind}/{post}", headers={**viewer.h, **REVEAL})
        assert PHONE not in detail.text
        assert detail.json()["data"]["contact_available"] is True
        own = client.get(f"{API}/{kind}/{post}", headers={**owner.h, **REVEAL})
        assert own.json()["data"]["owner_phone_number"] == PHONE
    assert _reveal_rows(runtime) == []


def test_legacy_detail_uses_the_same_quota_and_is_recorded(client, runtime, limits) -> None:
    owner = make_user(runtime, "Owner")
    posts = [make_lost_pet(runtime, owner, f"Pet{i}") for i in range(3)]
    viewer = make_user(runtime, "Viewer")
    first = client.get(f"{API}/lost-pets/{posts[0]}", headers=viewer.h)
    assert first.json()["data"]["owner_phone_number"] == PHONE
    assert "no-store" in first.headers["cache-control"]
    assert (
        client.get(f"{API}/lost-pets/{posts[1]}", headers=viewer.h).json()["data"][
            "owner_phone_number"
        ]
        == PHONE
    )
    third = client.get(f"{API}/lost-pets/{posts[2]}", headers=viewer.h)
    assert third.status_code == 200
    assert PHONE not in third.text
    assert third.json()["data"]["contact_available"] is True
    assert {row.mode for row in _reveal_rows(runtime)} == {"legacy_detail"}
    # Legacy detail reads and explicit reveals draw on one quota.
    assert (
        client.post(f"{API}/lost-pets/{posts[2]}/contact-reveal", headers=viewer.h).status_code
        == 429
    )
    # Re-reading a post already revealed stays free.
    assert PHONE in client.get(f"{API}/lost-pets/{posts[0]}", headers=viewer.h).text


def test_legacy_mode_can_be_switched_off_and_anonymous_never_qualifies(
    client, runtime, limits, monkeypatch
) -> None:
    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    viewer = make_user(runtime, "Viewer")
    assert PHONE not in client.get(f"{API}/lost-pets/{lost}").text
    monkeypatch.setattr(limits, "contact_legacy_detail_enabled", False)
    assert PHONE not in client.get(f"{API}/lost-pets/{lost}", headers=viewer.h).text
    assert _reveal_rows(runtime) == []
    # The explicit endpoint is unaffected by the legacy switch.
    assert (
        client.post(f"{API}/lost-pets/{lost}/contact-reveal", headers=viewer.h).status_code == 200
    )


def test_lists_feed_and_search_never_leak_even_for_heavy_revealers(client, runtime, limits) -> None:
    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    adoption = make_adoption(runtime, owner)
    _with_telegram(runtime, lost, adoption)
    viewer = make_user(runtime, "Viewer")
    assert (
        client.post(f"{API}/lost-pets/{lost}/contact-reveal", headers=viewer.h).status_code == 200
    )
    for headers in ({}, viewer.h, {**viewer.h, **REVEAL}):
        for path in (
            "/lost-pets",
            "/adoption-posts",
            "/feed?filter=recent",
            "/feed?filter=adoption",
            "/lost-pets/map?bbox=69.0,41.0,69.5,41.5",
            "/notifications",
        ):
            response = client.get(f"{API}{path}", headers=headers)
            assert PHONE not in response.text and TELEGRAM not in response.text, (path, headers)
    assert PHONE not in client.get(f"{API}/lost-pets/mine", headers=viewer.h).text


def test_every_parameterless_get_route_is_clean_for_anonymous_and_reveal_clients(
    client, runtime, limits
) -> None:
    from app.main import app

    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    adoption = make_adoption(runtime, owner)
    _with_telegram(runtime, lost, adoption)
    viewer = make_user(runtime, "Viewer")
    prefix = "/api/v1"
    paths = sorted(
        path.removeprefix(prefix)
        for path, operations in app.openapi()["paths"].items()
        if "get" in operations and "{" not in path
    )
    assert len(paths) > 10
    for path in paths:
        for headers in ({}, {**viewer.h, **REVEAL}):
            response = client.get(f"{API}{path}", headers=headers)
            assert PHONE not in response.text and TELEGRAM not in response.text, (path, headers)


def test_reveals_are_logged_and_stored_without_contact_values(client, runtime, limits) -> None:
    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    _with_telegram(runtime, lost)
    viewer = make_user(runtime, "Viewer")
    with capture_logs() as logs:
        assert (
            client.post(f"{API}/lost-pets/{lost}/contact-reveal", headers=viewer.h).status_code
            == 200
        )
        assert (
            client.get(f"{API}/lost-pets/{lost}", headers=make_user(runtime, "V2").h).status_code
            == 200
        )
    events = [entry for entry in logs if entry.get("event") == "contact_revealed"]
    assert len(events) == 2
    assert PHONE not in repr(logs) and TELEGRAM not in repr(logs)
    rows = _reveal_rows(runtime)
    assert len(rows) == 2
    assert PHONE not in repr([vars(row) for row in rows])
    assert all(row.created_at > datetime.now(UTC) - timedelta(minutes=5) for row in rows)
