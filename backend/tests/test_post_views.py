"""Post views: each person counted once per post when they open it (docs/ADRS.md, ADR-0024)."""

from __future__ import annotations

import sys
from pathlib import Path
from uuid import uuid4

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401
    API,
    block,
    client,
    make_adoption,
    make_lost_pet,
    make_post,
    make_user,
    runtime,
)

KINDS = ("posts", "lost-pets", "adoption-posts")


def _make(runtime, kind: str, owner):
    if kind == "posts":
        return make_post(runtime, owner)
    if kind == "lost-pets":
        return make_lost_pet(runtime, owner)
    return make_adoption(runtime, owner)


def _view(client, kind: str, post_id, *, viewer=None, guest_id: str | None = None):
    headers = dict(viewer.h) if viewer is not None else {}
    if guest_id is not None:
        headers["X-Viewer-Id"] = guest_id
    return client.post(f"{API}/{kind}/{post_id}/views", headers=headers)


def _view_rows(runtime):
    from sqlalchemy import select

    from app.infrastructure.db.models import schema

    with runtime.manager.session_scope() as session:
        return list(session.scalars(select(schema.PostView)))


@pytest.mark.parametrize("kind", KINDS)
def test_each_person_counts_once_and_shows_on_detail_and_feed(client, runtime, kind) -> None:
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    post_id = _make(runtime, kind, owner)
    guest = str(uuid4())

    first = _view(client, kind, post_id, viewer=viewer)
    assert first.status_code == 200, first.text
    assert first.json()["data"] == {"view_count": 1, "counted": True}
    assert _view(client, kind, post_id, viewer=viewer).json()["data"] == {
        "view_count": 1,
        "counted": False,
    }
    assert _view(client, kind, post_id, guest_id=guest).json()["data"]["view_count"] == 2
    assert _view(client, kind, post_id, guest_id=guest).json()["data"]["counted"] is False

    detail = client.get(f"{API}/{kind}/{post_id}")
    assert detail.json()["data"]["view_count"] == 2
    feed = client.get(f"{API}/feed", params={"limit": 50}).json()["data"]["items"]
    assert next(item for item in feed if item["id"] == str(post_id))["view_count"] == 2


@pytest.mark.parametrize("kind", KINDS)
def test_author_and_guest_without_id_are_not_counted(client, runtime, kind) -> None:
    owner = make_user(runtime, "Owner")
    post_id = _make(runtime, kind, owner)

    assert _view(client, kind, post_id, viewer=owner).json()["data"] == {
        "view_count": 0,
        "counted": False,
    }
    assert _view(client, kind, post_id).json()["data"]["counted"] is False
    assert _view(client, kind, post_id, guest_id="not-a-uuid").json()["data"]["counted"] is False
    assert _view_rows(runtime) == []


@pytest.mark.parametrize("kind", KINDS)
def test_hidden_posts_are_not_found(client, runtime, kind) -> None:
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    post_id = _make(runtime, kind, owner)
    assert block(client, owner, viewer).status_code in (200, 201, 204)

    assert _view(client, kind, post_id, viewer=viewer).status_code == 404
    assert _view(client, kind, uuid4(), guest_id=str(uuid4())).status_code == 404
    assert _view_rows(runtime) == []


def test_guest_id_is_stored_only_as_a_keyed_hash(client, runtime) -> None:
    owner = make_user(runtime, "Owner")
    post_id = make_post(runtime, owner)
    guest = str(uuid4())

    _view(client, "posts", post_id, guest_id=guest)

    (row,) = _view_rows(runtime)
    assert row.user_id is None
    assert row.guest_key and guest not in row.guest_key
    assert guest.replace("-", "") not in row.guest_key


def test_account_deletion_removes_view_records_but_keeps_totals(client, runtime) -> None:
    from app.infrastructure.db.models import schema

    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    post_id = make_post(runtime, owner)
    _view(client, "posts", post_id, viewer=viewer)

    assert client.delete(f"{API}/users/me", headers=viewer.h).status_code == 204

    assert _view_rows(runtime) == []
    with runtime.manager.session_scope() as session:
        assert session.get(schema.Post, post_id).view_count == 1
