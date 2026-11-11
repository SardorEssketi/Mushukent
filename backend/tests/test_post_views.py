"""Post views: one per person per post, on opening it or seeing its feed card (ADR-0024)."""

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


def _seen(client, items, *, viewer=None, guest_id: str | None = None):
    headers = dict(viewer.h) if viewer is not None else {}
    if guest_id is not None:
        headers["X-Viewer-Id"] = guest_id
    return client.post(f"{API}/views/seen", headers=headers, json={"items": items})


def test_feed_cards_seen_count_once_together_with_opening(client, runtime) -> None:
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    post_id = make_post(runtime, owner)
    lost_id = make_lost_pet(runtime, owner)
    adoption_id = make_adoption(runtime, owner)
    items = [
        {"kind": "post", "id": str(post_id)},
        {"kind": "lost_pet", "id": str(lost_id)},
        {"kind": "adoption", "id": str(adoption_id)},
        {"kind": "post", "id": str(post_id)},
    ]

    first = _seen(client, items, viewer=viewer)
    assert first.status_code == 200, first.text
    assert first.json()["data"]["items"] == [
        {"kind": "post", "id": str(post_id), "view_count": 1, "counted": True},
        {"kind": "lost_pet", "id": str(lost_id), "view_count": 1, "counted": True},
        {"kind": "adoption", "id": str(adoption_id), "view_count": 1, "counted": True},
    ]
    # Seeing the card and then opening the post is still one view.
    assert _view(client, "posts", post_id, viewer=viewer).json()["data"] == {
        "view_count": 1,
        "counted": False,
    }
    again = _seen(client, items[:1], guest_id=str(uuid4())).json()["data"]["items"]
    assert again == [{"kind": "post", "id": str(post_id), "view_count": 2, "counted": True}]


def test_seen_batch_skips_hidden_and_missing_posts_and_authors(client, runtime) -> None:
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    other = make_user(runtime, "Other")
    blocked_post = make_post(runtime, owner)
    visible_post = make_post(runtime, other)
    own_post = make_post(runtime, viewer)
    assert block(client, owner, viewer).status_code in (200, 201, 204)

    response = _seen(
        client,
        [
            {"kind": "post", "id": str(blocked_post)},
            {"kind": "lost_pet", "id": str(uuid4())},
            {"kind": "post", "id": str(own_post)},
            {"kind": "post", "id": str(visible_post)},
        ],
        viewer=viewer,
    )
    assert response.status_code == 200, response.text
    assert response.json()["data"]["items"] == [
        {"kind": "post", "id": str(own_post), "view_count": 0, "counted": False},
        {"kind": "post", "id": str(visible_post), "view_count": 1, "counted": True},
    ]
    assert len(_view_rows(runtime)) == 1


def test_seen_batch_rejects_bad_requests(client, runtime) -> None:
    post_id = make_post(runtime, make_user(runtime, "Owner"))
    guest = str(uuid4())
    assert _seen(client, [], guest_id=guest).status_code == 422
    assert _seen(client, [{"kind": "story", "id": str(post_id)}], guest_id=guest).status_code == 422
    too_many = [{"kind": "post", "id": str(uuid4())} for _ in range(21)]
    assert _seen(client, too_many, guest_id=guest).status_code == 422
    # A guest without an id is accepted but never counted.
    no_id = _seen(client, [{"kind": "post", "id": str(post_id)}])
    assert no_id.json()["data"]["items"][0]["counted"] is False
    assert _view_rows(runtime) == []
