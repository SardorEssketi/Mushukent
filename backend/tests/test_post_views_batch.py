"""Set-based `POST /views/seen` (load audit LT-05, FIX-3).

Same rules as before (authors not counted, guests by keyed install id, visibility and blocks, one
view per viewer per item, deterministic lock order), at a bounded number of SQL statements
instead of ~4 per item, and safe under concurrent overlapping batches.
"""

from __future__ import annotations

import sys
import threading
from pathlib import Path
from uuid import uuid4

from sqlalchemy import event, update

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401
    API,
    client,
    make_adoption,
    make_cat,
    make_lost_pet,
    make_post,
    make_user,
    runtime,
)

from app.infrastructure.db.models import schema  # noqa: E402


def _seen(client, items, *, viewer=None, guest_id: str | None = None):
    headers = dict(viewer.h) if viewer is not None else {}
    if guest_id is not None:
        headers["X-Viewer-Id"] = guest_id
    return client.post(f"{API}/views/seen", headers=headers, json={"items": items})


def _counts(runtime, post_ids) -> dict:
    with runtime.manager.session_scope() as session:
        rows = session.query(schema.Post.id, schema.Post.view_count).filter(
            schema.Post.id.in_(post_ids)
        )
        return {str(post_id): count for post_id, count in rows}


def test_visibility_rules_for_moderators_authors_private_and_hidden_cats(client, runtime) -> None:
    owner = make_user(runtime, "Owner")
    viewer = make_user(runtime, "Viewer")
    moderator = make_user(runtime, "Mod", moderator=True)
    private = make_post(runtime, owner)
    hidden_cat_cat = make_cat(runtime, owner)
    hidden_cat_post = make_post(runtime, owner, cat_id=hidden_cat_cat)
    with runtime.manager.session_scope() as session:
        session.execute(
            update(schema.Post).where(schema.Post.id == private).values(is_public=False)
        )
        session.execute(
            update(schema.Cat).where(schema.Cat.id == hidden_cat_cat).values(is_active=False)
        )
    items = [{"kind": "post", "id": str(private)}, {"kind": "post", "id": str(hidden_cat_post)}]

    assert _seen(client, items, viewer=viewer).json()["data"]["items"] == []
    by_owner = _seen(client, items, viewer=owner).json()["data"]["items"]
    assert [(item["counted"], item["view_count"]) for item in by_owner] == [(False, 0), (False, 0)]
    by_moderator = _seen(client, items, viewer=moderator).json()["data"]["items"]
    assert [(item["counted"], item["view_count"]) for item in by_moderator] == [
        (True, 1),
        (True, 1),
    ]


def test_private_or_resolved_rules_for_lost_pets_and_adoptions(client, runtime) -> None:
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    lost = make_lost_pet(runtime, owner)
    adoption = make_adoption(runtime, owner)
    with runtime.manager.session_scope() as session:
        session.execute(
            update(schema.LostPet).where(schema.LostPet.id == lost).values(is_public=False)
        )
    response = _seen(
        client,
        [{"kind": "lost_pet", "id": str(lost)}, {"kind": "adoption", "id": str(adoption)}],
        viewer=viewer,
    )
    assert response.json()["data"]["items"] == [
        {"kind": "adoption", "id": str(adoption), "view_count": 1, "counted": True}
    ]


def test_guest_install_id_counts_once(client, runtime) -> None:
    post_id = make_post(runtime, make_user(runtime, "Owner"))
    guest = str(uuid4())
    first = _seen(client, [{"kind": "post", "id": str(post_id)}], guest_id=guest)
    second = _seen(client, [{"kind": "post", "id": str(post_id)}], guest_id=guest)
    assert first.json()["data"]["items"][0] == {
        "kind": "post",
        "id": str(post_id),
        "view_count": 1,
        "counted": True,
    }
    assert second.json()["data"]["items"][0]["counted"] is False
    assert _counts(runtime, [post_id])[str(post_id)] == 1


def test_a_full_batch_uses_a_bounded_number_of_statements(client, runtime) -> None:
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    items = [{"kind": "post", "id": str(make_post(runtime, owner))} for _ in range(14)]
    items += [{"kind": "lost_pet", "id": str(make_lost_pet(runtime, owner))} for _ in range(3)]
    items += [{"kind": "adoption", "id": str(make_adoption(runtime, owner))} for _ in range(3)]
    statements: list[str] = []

    def count(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement)

    engine = runtime.manager.engine
    event.listen(engine, "before_cursor_execute", count)
    try:
        response = _seen(client, items, viewer=viewer)
    finally:
        event.remove(engine, "before_cursor_execute", count)
    assert response.status_code == 200
    assert all(item["counted"] for item in response.json()["data"]["items"])
    assert len(response.json()["data"]["items"]) == 20
    # One user lookup (auth), then per kind a visibility read, one insert, one lock + update.
    assert len(statements) <= 12, f"{len(statements)} statements for one batch"


def test_overlapping_concurrent_batches_on_a_hot_post_count_exactly(client, runtime) -> None:
    owner = make_user(runtime, "Owner")
    hot = make_post(runtime, owner)
    others = [make_post(runtime, owner) for _ in range(6)]
    viewers = [make_user(runtime, f"V{index}") for index in range(8)]
    errors: list[str] = []

    def run(viewer, offset: int) -> None:
        # Each viewer sends overlapping batches in a different order; every batch has the hot post.
        ids = [hot, *others[offset:], *others[:offset]]
        for start in range(0, len(ids), 3):
            batch = [{"kind": "post", "id": str(post_id)} for post_id in reversed(ids[start:])]
            response = _seen(client, batch, viewer=viewer)
            if response.status_code != 200:
                errors.append(f"{response.status_code} {response.text[:120]}")

    threads = [
        threading.Thread(target=run, args=(viewer, index % len(others)))
        for index, viewer in enumerate(viewers)
    ]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(60)
    assert errors == []
    counts = _counts(runtime, [hot, *others])
    assert counts[str(hot)] == len(viewers)
    assert all(counts[str(post_id)] == len(viewers) for post_id in others)
