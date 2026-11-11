"""Saved posts: a user can save other users' cat posts and see them in a private list."""

from __future__ import annotations

import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401
    API,
    block,
    client,
    make_post,
    make_user,
    runtime,
)


def _save(client, person, post_id):
    return client.post(f"{API}/posts/{post_id}/saved", headers=person.h)


def _unsave(client, person, post_id):
    return client.delete(f"{API}/posts/{post_id}/saved", headers=person.h)


def _saved_ids(client, person, **params) -> list[str]:
    response = client.get(f"{API}/users/me/saved-posts", headers=person.h, params=params)
    assert response.status_code == 200, response.text
    return [item["id"] for item in response.json()["data"]["items"]]


def test_save_lists_newest_saved_first_and_marks_post(client, runtime) -> None:
    author, reader = make_user(runtime, "Author"), make_user(runtime, "Reader")
    older = make_post(runtime, author, created_at=datetime.now(UTC) - timedelta(days=2))
    newer = make_post(runtime, author)

    # Saved order, not post age, decides the list order.
    assert _save(client, reader, newer).status_code == 204
    assert _save(client, reader, older).status_code == 204
    assert _saved_ids(client, reader) == [str(older), str(newer)]

    detail = client.get(f"{API}/posts/{older}", headers=reader.h).json()["data"]
    assert detail["is_saved_by_me"] is True
    feed = client.get(f"{API}/feed", headers=reader.h, params={"limit": 50}).json()["data"]
    assert next(item for item in feed["items"] if item["id"] == str(older))["is_saved_by_me"]
    # Other viewers and guests never see someone else's saves.
    other = make_user(runtime, "Other")
    assert (
        client.get(f"{API}/posts/{older}", headers=other.h).json()["data"]["is_saved_by_me"]
        is False
    )
    assert client.get(f"{API}/posts/{older}").json()["data"]["is_saved_by_me"] is False


def test_save_is_idempotent_and_unsave_removes(client, runtime) -> None:
    author, reader = make_user(runtime, "Author"), make_user(runtime, "Reader")
    post_id = make_post(runtime, author)

    assert _save(client, reader, post_id).status_code == 204
    assert _save(client, reader, post_id).status_code == 204
    assert _saved_ids(client, reader) == [str(post_id)]

    assert _unsave(client, reader, post_id).status_code == 204
    assert _unsave(client, reader, post_id).status_code == 204
    assert _saved_ids(client, reader) == []
    detail = client.get(f"{API}/posts/{post_id}", headers=reader.h).json()["data"]
    assert detail["is_saved_by_me"] is False


def test_only_other_users_cat_posts_can_be_saved(client, runtime) -> None:
    author, reader = make_user(runtime, "Author"), make_user(runtime, "Reader")
    own = make_post(runtime, reader)
    needs_help = make_post(runtime, author, kind="needs_help")

    own_response = _save(client, reader, own)
    assert own_response.status_code == 422
    assert own_response.json()["error"]["code"] == "CANNOT_SAVE_OWN_POST"
    help_response = _save(client, reader, needs_help)
    assert help_response.status_code == 422
    assert help_response.json()["error"]["code"] == "POST_NOT_SAVEABLE"
    assert _save(client, reader, "00000000-0000-4000-8000-000000000000").status_code == 404
    assert _saved_ids(client, reader) == []


def test_saved_posts_require_sign_in(client, runtime) -> None:
    author = make_user(runtime, "Author")
    post_id = make_post(runtime, author)
    assert client.post(f"{API}/posts/{post_id}/saved").status_code == 401
    assert client.get(f"{API}/users/me/saved-posts").status_code == 401


def test_list_is_private_to_its_owner(client, runtime) -> None:
    author = make_user(runtime, "Author")
    reader, other = make_user(runtime, "Reader"), make_user(runtime, "Other")
    post_id = make_post(runtime, author)
    _save(client, reader, post_id)
    assert _saved_ids(client, other) == []


def test_deleted_and_blocked_posts_drop_out(client, runtime) -> None:
    author, reader = make_user(runtime, "Author"), make_user(runtime, "Reader")
    blocked_author = make_user(runtime, "Blocked")
    kept = make_post(runtime, author)
    deleted = make_post(runtime, author)
    hidden_by_block = make_post(runtime, blocked_author)
    for post_id in (kept, deleted, hidden_by_block):
        assert _save(client, reader, post_id).status_code == 204

    assert client.delete(f"{API}/posts/{deleted}", headers=author.h).status_code == 204
    assert block(client, reader, blocked_author).status_code in (200, 201, 204)
    assert _saved_ids(client, reader) == [str(kept)]
    # A blocked author's post cannot be saved anew either.
    _unsave(client, reader, hidden_by_block)
    assert _save(client, reader, hidden_by_block).status_code == 404


def test_saved_list_pages_with_cursor(client, runtime) -> None:
    author, reader = make_user(runtime, "Author"), make_user(runtime, "Reader")
    post_ids = [make_post(runtime, author) for _ in range(5)]
    for post_id in post_ids:
        _save(client, reader, post_id)

    first = client.get(f"{API}/users/me/saved-posts", headers=reader.h, params={"limit": 2}).json()[
        "data"
    ]
    seen = [item["id"] for item in first["items"]]
    cursor = first.get("next_cursor")
    while cursor:
        page = client.get(
            f"{API}/users/me/saved-posts",
            headers=reader.h,
            params={"limit": 2, "cursor": cursor},
        ).json()["data"]
        seen += [item["id"] for item in page["items"]]
        cursor = page.get("next_cursor")
    assert seen == [str(post_id) for post_id in reversed(post_ids)]


def test_account_deletion_removes_the_users_saved_posts(client, runtime) -> None:
    from sqlalchemy import func, select

    from app.infrastructure.db.models import schema

    author, reader = make_user(runtime, "Author"), make_user(runtime, "Reader")
    post_id = make_post(runtime, author)
    assert _save(client, reader, post_id).status_code == 204
    assert client.delete(f"{API}/users/me", headers=reader.h).status_code in (200, 204)
    with runtime.manager.session_scope() as session:
        remaining = session.scalar(
            select(func.count())
            .select_from(schema.SavedPost)
            .where(schema.SavedPost.user_id == reader.id)
        )
    assert remaining == 0


def test_moderators_cannot_save_posts_the_list_would_hide(client, runtime) -> None:
    from sqlalchemy import update

    from app.infrastructure.db.models import schema

    author = make_user(runtime, "Author")
    moderator = make_user(runtime, "Mod", moderator=True)
    post_id = make_post(runtime, author)
    with runtime.manager.session_scope() as session:
        session.execute(
            update(schema.Post).where(schema.Post.id == post_id).values(is_public=False)
        )
    # A moderator can open the private post, but saving it is refused.
    assert client.get(f"{API}/posts/{post_id}", headers=moderator.h).status_code == 200
    assert _save(client, moderator, post_id).status_code == 404
    assert _saved_ids(client, moderator) == []


def test_own_post_reason_wins_over_kind(client, runtime) -> None:
    reader = make_user(runtime, "Reader")
    own_help = make_post(runtime, reader, kind="needs_help")
    response = _save(client, reader, own_help)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "CANNOT_SAVE_OWN_POST"
