"""`recent` mixed feed with per-branch limits (load audit FIX-5) must page exactly like the
old global-sort query: same items, same order, same cursor semantics, including ties on
created_at across posts, lost pets and adoption posts."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

from sqlalchemy import text
from test_feed_map import (  # noqa: F401 - fixtures are used by name
    _create_adoption_post,
    _create_cat,
    _create_lost_pet,
    _create_post,
    _create_user_with_token,
    client,
    feed_runtime,
)

# The old query: complete branches, one global sort (FEED_ITEM_TYPE_RANK: post 3, lost 2, adopt 1).
REFERENCE = text(
    """
    SELECT id::text FROM (
        SELECT p.id, p.created_at, 3 AS rank FROM posts p JOIN cats c ON c.id = p.cat_id
        WHERE p.deleted_at IS NULL
          AND ((p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL)
               OR p.user_id = CAST(:viewer AS uuid))
        UNION ALL
        SELECT id, created_at, 2 FROM lost_pets
        WHERE deleted_at IS NULL AND is_public AND NOT is_resolved
        UNION ALL
        SELECT id, created_at, 1 FROM adoption_posts
        WHERE deleted_at IS NULL AND is_public AND NOT is_resolved
    ) feed ORDER BY created_at DESC, rank DESC, id DESC
"""
)


def _seed(feed_runtime):
    manager = feed_runtime.db_session_manager
    author, token = _create_user_with_token(
        manager, feed_runtime.token_service, email="recent-parity@example.com"
    )
    cat = _create_cat(manager, creator_id=author.id)
    hidden_cat = _create_cat(manager, creator_id=author.id, is_active=False)
    base = datetime(2026, 11, 1, 12, 0, tzinfo=UTC)
    for index in range(60):
        moment = base - timedelta(minutes=index // 4)  # 4 items share each timestamp
        _create_post(manager, cat_id=cat.id, user_id=author.id, created_at=moment)
        if index % 3 == 0:
            _create_lost_pet(manager, user_id=author.id, created_at=moment)
        if index % 5 == 0:
            _create_adoption_post(manager, user_id=author.id, created_at=moment)
    # Hidden or excluded rows must stay excluded.
    _create_post(manager, cat_id=hidden_cat.id, user_id=author.id, created_at=base)
    _create_post(
        manager, cat_id=cat.id, user_id=author.id, created_at=base, deleted_at=datetime.now(UTC)
    )
    _create_post(manager, cat_id=cat.id, user_id=author.id, created_at=base, is_public=False)
    _create_lost_pet(manager, user_id=author.id, created_at=base, is_resolved=True)
    return author, token


def _api_ids(client, *, limit: int, headers=None) -> list[str]:
    ids, cursor = [], None
    for _ in range(500):
        params = {"filter": "recent", "limit": limit}
        if cursor:
            params["cursor"] = cursor
        response = client.get("/api/v1/feed", params=params, headers=headers or {})
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        ids.extend(item["id"] for item in data["items"])
        cursor = data["next_cursor"]
        if not cursor:
            return ids
    raise AssertionError("pagination did not terminate")


def _reference_ids(feed_runtime, viewer=None) -> list[str]:
    with feed_runtime.db_session_manager.session_scope() as session:
        return list(
            session.execute(REFERENCE, {"viewer": str(viewer) if viewer else None}).scalars()
        )


def test_recent_pages_match_the_global_sort_for_guests(client, feed_runtime) -> None:
    _seed(feed_runtime)
    expected = _reference_ids(feed_runtime)
    for limit in (1, 4, 7, 20, 50):
        assert _api_ids(client, limit=limit) == expected, f"mismatch at limit {limit}"


def test_recent_pages_match_the_global_sort_for_the_author(client, feed_runtime) -> None:
    author, token = _seed(feed_runtime)
    expected = _reference_ids(feed_runtime, viewer=author.id)
    headers = {"Authorization": f"Bearer {token}"}
    for limit in (3, 20):
        assert _api_ids(client, limit=limit, headers=headers) == expected
