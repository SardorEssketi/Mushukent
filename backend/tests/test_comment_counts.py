"""Regression tests: a publication's ``comment_count`` equals the comments the viewer can see.

Bug: a card showed "1 comment" while the comment list was empty. Causes: account deletion
soft-deleted comments without lowering the stored counters, and the stored counter (global)
ignored the viewer-specific block filter that the comment lists apply.

Rule under test (see app/infrastructure/repositories/comment_visibility.py and
docs/BLOCKING.md "Comment counts"): the count returned with a post, Needs Help post, lost-pet
post or adoption post is the number of comments the same viewer gets from the full, paginated
comment list. Every test runs against the disposable integration database (see conftest.py).
"""

from __future__ import annotations

import sys
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID

from sqlalchemy import event, func, select

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401  (pytest fixtures)
    API,
    Person,
    block,
    client,
    make_adoption,
    make_cat,
    make_lost_pet,
    make_post,
    make_user,
    runtime,
    unblock,
)

from app.infrastructure.db.models import schema  # noqa: E402

COMMENT_PATH = {
    "post": "/posts/{id}/comments",
    "lost_pet": "/lost-pets/{id}/comments",
    "adoption": "/adoption-posts/{id}/comments",
}
DETAIL_PATH = {
    "post": "/posts/{id}",
    "lost_pet": "/lost-pets/{id}",
    "adoption": "/adoption-posts/{id}",
}
MODEL = {"post": schema.Post, "lost_pet": schema.LostPet, "adoption": schema.AdoptionPost}


# --------------------------------------------------------------------------- helpers


def add_comment(client, author: Person, kind: str, target: UUID, content: str = "hi", parent=None):
    """Create a comment through the API so the stored counter is maintained as in production."""
    body = {"content": content}
    if parent is not None:
        body["parent_comment_id"] = str(parent)
    response = client.post(
        f"{API}{COMMENT_PATH[kind].format(id=target)}", json=body, headers=author.h
    )
    assert response.status_code in (200, 201), response.text
    return UUID(response.json()["data"]["id"])


def delete_comment(client, actor: Person, comment_id: UUID) -> None:
    response = client.delete(f"{API}/comments/{comment_id}", headers=actor.h)
    assert response.status_code == 204, response.text


def detail_count(client, kind: str, target: UUID, viewer: Person | None) -> int:
    response = client.get(
        f"{API}{DETAIL_PATH[kind].format(id=target)}", headers=viewer.h if viewer else {}
    )
    assert response.status_code == 200, response.text
    return response.json()["data"]["comment_count"]


def listed_comment_ids(client, kind: str, target: UUID, viewer: Person | None) -> list[str]:
    """Walk the whole paginated comment list (small pages on purpose)."""
    ids: list[str] = []
    cursor = None
    for _ in range(50):
        params = {"limit": 2}
        if cursor:
            params["cursor"] = cursor
        response = client.get(
            f"{API}{COMMENT_PATH[kind].format(id=target)}",
            params=params,
            headers=viewer.h if viewer else {},
        )
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        ids.extend(item["id"] for item in data["items"])
        cursor = data.get("next_cursor")
        if not cursor:
            return ids
    raise AssertionError("comment list did not terminate")


def feed_counts(client, viewer: Person | None, **params) -> dict[str, int]:
    """Every item of the mixed feed (all pages) -> its comment_count."""
    counts: dict[str, int] = {}
    cursor = None
    for _ in range(50):
        query = {"limit": 5, **params}
        if cursor:
            query["cursor"] = cursor
        response = client.get(f"{API}/feed", params=query, headers=viewer.h if viewer else {})
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        counts.update({item["id"]: item["comment_count"] for item in data["items"]})
        cursor = data.get("next_cursor")
        if not cursor:
            return counts
    raise AssertionError("feed did not terminate")


def assert_consistent(client, kind: str, target: UUID, viewer: Person | None, expected: int):
    """Detail count == full comment list length == expected, for this viewer."""
    listed = listed_comment_ids(client, kind, target, viewer)
    assert len(listed) == expected, (kind, viewer and viewer.name, listed)
    assert detail_count(client, kind, target, viewer) == expected


def stored_count(runtime, kind: str, target: UUID) -> int:
    with runtime.manager.session_scope() as session:
        return session.get(MODEL[kind], target).comment_count


def active_comment_rows(runtime, kind: str, target: UUID) -> int:
    column = {
        "post": schema.Comment.post_id,
        "lost_pet": schema.Comment.lost_pet_id,
        "adoption": schema.Comment.adoption_post_id,
    }[kind]
    with runtime.manager.session_scope() as session:
        return session.scalar(
            select(func.count(schema.Comment.id)).where(
                column == target, schema.Comment.deleted_at.is_(None)
            )
        )


def make_target(runtime, owner: Person, kind: str) -> UUID:
    if kind == "post":
        return make_post(runtime, owner)
    if kind == "needs_help":
        return make_post(runtime, owner, kind="needs_help")
    if kind == "lost_pet":
        return make_lost_pet(runtime, owner)
    return make_adoption(runtime, owner)


def api_kind(kind: str) -> str:
    return "post" if kind == "needs_help" else kind


@contextmanager
def count_queries(runtime):
    statements: list[str] = []

    def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
        statements.append(statement)

    engine = runtime.manager.engine
    event.listen(engine, "before_cursor_execute", before_cursor_execute)
    try:
        yield statements
    finally:
        event.remove(engine, "before_cursor_execute", before_cursor_execute)


ALL_KINDS = ("post", "needs_help", "lost_pet", "adoption")


# --------------------------------------------------------------------------- basic lifecycle


def test_single_visible_comment_then_soft_delete_for_every_publication_type(client, runtime):
    owner, writer = make_user(runtime, "Owner"), make_user(runtime, "Writer")
    for kind in ALL_KINDS:
        target, path_kind = make_target(runtime, owner, kind), api_kind(kind)
        comment = add_comment(client, writer, path_kind, target)
        for viewer in (None, owner, writer):
            assert_consistent(client, path_kind, target, viewer, 1)

        delete_comment(client, writer, comment)
        for viewer in (None, owner, writer):
            assert_consistent(client, path_kind, target, viewer, 0)
        assert stored_count(runtime, path_kind, target) == 0


def test_create_then_delete_returns_to_original_count_without_drift(client, runtime):
    owner, writer = make_user(runtime, "Owner"), make_user(runtime, "Writer")
    for kind in ALL_KINDS:
        target, path_kind = make_target(runtime, owner, kind), api_kind(kind)
        add_comment(client, owner, path_kind, target, "keep")
        before = detail_count(client, path_kind, target, None)
        reply = add_comment(client, writer, path_kind, target, "temp")
        assert detail_count(client, path_kind, target, None) == before + 1
        delete_comment(client, writer, reply)
        # Deleting twice is a no-op and never decrements again.
        delete_comment(client, writer, reply)
        assert detail_count(client, path_kind, target, None) == before == 1
        assert stored_count(runtime, path_kind, target) == active_comment_rows(
            runtime, path_kind, target
        )


def test_moderator_removal_by_delete_and_by_report_hides_comment_from_count(client, runtime):
    owner, writer = make_user(runtime, "Owner"), make_user(runtime, "Writer")
    reporter = make_user(runtime, "Reporter")
    moderator = make_user(runtime, "Mod", moderator=True)
    for kind in ("post", "lost_pet", "adoption"):
        target = make_target(runtime, owner, kind)
        by_delete = add_comment(client, writer, kind, target, "a")
        by_report = add_comment(client, writer, kind, target, "b")
        assert_consistent(client, kind, target, None, 2)

        delete_comment(client, moderator, by_delete)
        report = client.post(
            f"{API}/reports",
            json={"target_type": "comment", "target_id": str(by_report), "reason": "spam"},
            headers=reporter.h,
        )
        assert report.status_code in (200, 201), report.text
        handled = client.patch(
            f"{API}/moderation/reports/{report.json()['data']['id']}",
            json={"status": "resolved", "action": "soft_delete_comment"},
            headers=moderator.h,
        )
        assert handled.status_code == 200, handled.text

        for viewer in (None, owner, writer, moderator):
            assert_consistent(client, kind, target, viewer, 0)
        assert stored_count(runtime, kind, target) == 0


def test_replies_are_part_of_the_counted_collection(client, runtime):
    owner, writer = make_user(runtime, "Owner"), make_user(runtime, "Writer")
    post = make_post(runtime, owner)
    parent = add_comment(client, owner, "post", post, "parent")
    add_comment(client, writer, "post", post, "reply", parent=parent)
    assert_consistent(client, "post", post, None, 2)


# --------------------------------------------------------------------------- account deletion


def test_account_deletion_removes_its_comments_from_counts_on_all_publication_types(
    client, runtime
):
    owner, leaver, stayer = (make_user(runtime, n) for n in ("Owner", "Leaver", "Stayer"))
    targets = {kind: make_target(runtime, owner, kind) for kind in ALL_KINDS}
    for kind, target in targets.items():
        add_comment(client, leaver, api_kind(kind), target, "leaver-1")
        add_comment(client, leaver, api_kind(kind), target, "leaver-2")
        add_comment(client, stayer, api_kind(kind), target, "stayer")

    assert client.delete(f"{API}/users/me", headers=leaver.h).status_code == 204

    for kind, target in targets.items():
        path_kind = api_kind(kind)
        for viewer in (None, owner, stayer):
            assert_consistent(client, path_kind, target, viewer, 1)
        # The stored counter is exact as well (no stale "+2").
        assert stored_count(runtime, path_kind, target) == 1
    feed = feed_counts(client, None)
    assert {feed[str(target)] for target in targets.values()} == {1}


def test_account_deletion_does_not_double_decrement_already_deleted_comments(client, runtime):
    owner, leaver, stayer = (make_user(runtime, n) for n in ("Owner", "Leaver", "Stayer"))
    for kind in ("post", "lost_pet", "adoption"):
        target = make_target(runtime, owner, kind)
        removed = add_comment(client, leaver, kind, target, "removed earlier")
        add_comment(client, leaver, kind, target, "active")
        add_comment(client, stayer, kind, target, "stays")
        delete_comment(client, leaver, removed)
        assert stored_count(runtime, kind, target) == 2

    assert client.delete(f"{API}/users/me", headers=leaver.h).status_code == 204

    with runtime.manager.session_scope() as session:
        rows = session.scalars(
            select(schema.Comment).where(schema.Comment.content.in_(["removed earlier", "active"]))
        ).all()
        assert rows == []  # every comment of the account is anonymized
        anonymized = session.scalars(
            select(schema.Comment).where(schema.Comment.content == "[deleted]")
        ).all()
        assert len(anonymized) == 6
        assert all(row.user_id is None and row.deleted_at is not None for row in anonymized)
        for model in (schema.Post, schema.LostPet, schema.AdoptionPost):
            assert {row.comment_count for row in session.scalars(select(model))} == {1}


def test_account_deletion_with_only_deleted_comments_changes_no_counter(client, runtime):
    owner, leaver = make_user(runtime, "Owner"), make_user(runtime, "Leaver")
    post = make_post(runtime, owner)
    add_comment(client, owner, "post", post, "owner")
    gone = add_comment(client, leaver, "post", post, "gone")
    delete_comment(client, leaver, gone)
    assert client.delete(f"{API}/users/me", headers=leaver.h).status_code == 204
    assert stored_count(runtime, "post", post) == 1
    assert_consistent(client, "post", post, None, 1)


# --------------------------------------------------------------------------- blocking


def test_viewer_blocking_the_only_comment_author_sees_zero_and_unblock_restores(client, runtime):
    owner, viewer, author = (make_user(runtime, n) for n in ("Owner", "Viewer", "Author"))
    targets = {kind: make_target(runtime, owner, kind) for kind in ALL_KINDS}
    for kind, target in targets.items():
        add_comment(client, author, api_kind(kind), target)

    assert block(client, viewer, author).status_code == 204
    for kind, target in targets.items():
        assert_consistent(client, api_kind(kind), target, viewer, 0)
        # Nobody else is affected and the stored counter is untouched.
        assert_consistent(client, api_kind(kind), target, owner, 1)
        assert_consistent(client, api_kind(kind), target, None, 1)
        assert stored_count(runtime, api_kind(kind), target) == 1
    viewer_feed = feed_counts(client, viewer)
    assert {viewer_feed[str(target)] for target in targets.values()} == {0}

    assert unblock(client, viewer, author).status_code == 204
    for kind, target in targets.items():
        assert_consistent(client, api_kind(kind), target, viewer, 1)
    viewer_feed = feed_counts(client, viewer)
    assert {viewer_feed[str(target)] for target in targets.values()} == {1}


def test_block_hides_comments_in_both_directions(client, runtime):
    owner, viewer, author = (make_user(runtime, n) for n in ("Owner", "Viewer", "Author"))
    post = make_post(runtime, owner)
    add_comment(client, author, "post", post)
    add_comment(client, viewer, "post", post)

    # The comment author blocks the viewer: the policy is symmetric (docs/BLOCKING.md).
    assert block(client, author, viewer).status_code == 204
    assert_consistent(client, "post", post, viewer, 1)  # only the viewer's own comment
    assert_consistent(client, "post", post, author, 1)  # only the author's own comment
    assert_consistent(client, "post", post, owner, 2)
    assert_consistent(client, "post", post, None, 2)


def test_two_viewers_with_different_blocks_get_their_own_counts(client, runtime):
    owner, alice, bob = (make_user(runtime, n) for n in ("Owner", "Alice", "Bob"))
    carol, dave = make_user(runtime, "Carol"), make_user(runtime, "Dave")
    lost_pet = make_lost_pet(runtime, owner)
    for author in (carol, carol, dave):
        add_comment(client, author, "lost_pet", lost_pet)

    assert block(client, alice, carol).status_code == 204
    assert block(client, dave, bob).status_code == 204
    assert_consistent(client, "lost_pet", lost_pet, alice, 1)
    assert_consistent(client, "lost_pet", lost_pet, bob, 2)
    assert_consistent(client, "lost_pet", lost_pet, owner, 3)
    assert_consistent(client, "lost_pet", lost_pet, None, 3)


def test_mixed_hidden_and_visible_comments_count_only_visible(client, runtime):
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    blocked, deleted_author, normal = (make_user(runtime, n) for n in ("Blocked", "Gone", "Ok"))
    adoption = make_adoption(runtime, owner)
    add_comment(client, blocked, "adoption", adoption)
    add_comment(client, normal, "adoption", adoption)
    removed = add_comment(client, normal, "adoption", adoption)
    add_comment(client, deleted_author, "adoption", adoption)
    add_comment(client, viewer, "adoption", adoption)

    delete_comment(client, normal, removed)
    assert client.delete(f"{API}/users/me", headers=deleted_author.h).status_code == 204
    assert block(client, viewer, blocked).status_code == 204

    assert_consistent(client, "adoption", adoption, viewer, 2)
    assert_consistent(client, "adoption", adoption, owner, 3)
    assert_consistent(client, "adoption", adoption, None, 3)


def test_list_endpoints_agree_with_detail_and_comment_list(client, runtime):
    owner, viewer, author = (make_user(runtime, n) for n in ("Owner", "Viewer", "Author"))
    cat = make_cat(runtime, owner)
    post = make_post(runtime, owner, cat_id=cat)
    needs_help = make_post(runtime, owner, cat_id=cat, kind="needs_help")
    lost_pet = make_lost_pet(runtime, owner)
    adoption = make_adoption(runtime, owner)
    for kind, target in (
        ("post", post),
        ("post", needs_help),
        ("lost_pet", lost_pet),
        ("adoption", adoption),
    ):
        add_comment(client, author, kind, target)
        add_comment(client, owner, kind, target)
    assert block(client, viewer, author).status_code == 204

    def items(path, who, **params):
        response = client.get(f"{API}{path}", params=params, headers=who.h)
        assert response.status_code == 200, response.text
        return {item["id"]: item["comment_count"] for item in response.json()["data"]["items"]}

    for who, expected in ((viewer, 1), (owner, 2)):
        listings = [
            items(f"/users/{owner.id}/posts", who),
            items(f"/cats/{cat}/posts", who),
            items("/feed", who, filter_by="popular", limit=50),
            items("/feed", who, filter_by="recent", limit=50),
        ]
        for listing in listings:
            for target in (post, needs_help):
                assert listing[str(target)] == expected
        assert items("/lost-pets", who)[str(lost_pet)] == expected
        assert items("/adoption-posts", who)[str(adoption)] == expected
        assert items("/feed", who, filter_by="adoption")[str(adoption)] == expected
        assert items("/lost-pets/mine", owner)[str(lost_pet)] == 2
        assert items("/adoption-posts/mine", owner)[str(adoption)] == 2


def test_owner_responses_after_edit_and_resolution_use_owner_visibility(client, runtime):
    owner, blocked = make_user(runtime, "Owner"), make_user(runtime, "Blocked")
    lost_pet = make_lost_pet(runtime, owner)
    add_comment(client, blocked, "lost_pet", lost_pet)
    add_comment(client, owner, "lost_pet", lost_pet)
    assert block(client, owner, blocked).status_code == 204

    response = client.patch(
        f"{API}/lost-pets/{lost_pet}/resolution", json={"is_resolved": True}, headers=owner.h
    )
    assert response.status_code == 200, response.text
    assert response.json()["data"]["comment_count"] == 1


# --------------------------------------------------------------------------- performance


def test_feed_comment_counts_use_a_constant_number_of_queries(client, runtime):
    owner, viewer, author = (make_user(runtime, n) for n in ("Owner", "Viewer", "Author"))
    assert block(client, viewer, author).status_code == 204

    def seed(count: int) -> None:
        for _ in range(count):
            for kind in ("post", "lost_pet", "adoption"):
                target = make_target(runtime, owner, kind)
                add_comment(client, author, kind, target)
                add_comment(client, owner, kind, target)

    def feed_query_count() -> tuple[int, int]:
        with count_queries(runtime) as statements:
            response = client.get(
                f"{API}/feed", params={"limit": 50, "filter_by": "recent"}, headers=viewer.h
            )
        assert response.status_code == 200, response.text
        items = response.json()["data"]["items"]
        assert {item["comment_count"] for item in items} == {1}
        return len(items), len(statements)

    seed(1)
    small_items, small_queries = feed_query_count()
    seed(4)
    large_items, large_queries = feed_query_count()
    assert (small_items, large_items) == (3, 15)
    # More items, same number of statements: no per-item comment-count query.
    assert large_queries == small_queries


# --------------------------------------------------------------------------- concurrency


def test_concurrent_account_deletion_and_comment_deletion_keep_counter_exact(client, runtime):
    owner = make_user(runtime, "Owner")
    moderator = make_user(runtime, "Mod", moderator=True)
    for round_index in range(4):
        leaver = make_user(runtime, f"Leaver{round_index}")
        targets = [make_target(runtime, owner, kind) for kind in ("post", "lost_pet", "adoption")]
        kinds = ("post", "lost_pet", "adoption")
        # Raced: moderator deletion vs account deletion of the same comment.
        comments = [
            add_comment(client, leaver, kind, t) for kind, t in zip(kinds, targets, strict=True)
        ]
        for kind, target in zip(kinds, targets, strict=True):
            # Removed only by the account deletion.
            add_comment(client, leaver, kind, target, "account only")
            add_comment(client, owner, kind, target, "owner")

        def delete_account(person: Person = leaver) -> int:
            return client.delete(f"{API}/users/me", headers=person.h).status_code

        def moderate(comment_id: UUID) -> int:
            return client.delete(f"{API}/comments/{comment_id}", headers=moderator.h).status_code

        with ThreadPoolExecutor(max_workers=4) as pool:
            futures = [pool.submit(delete_account)] + [
                pool.submit(moderate, comment_id) for comment_id in comments
            ]
            results = [future.result() for future in futures]
        assert results[0] == 204
        assert all(code in (204, 404) for code in results[1:]), results

        for kind, target in zip(kinds, targets, strict=True):
            assert stored_count(runtime, kind, target) == active_comment_rows(runtime, kind, target)
            assert_consistent(client, kind, target, None, 1)


def test_concurrent_comment_creation_keeps_counter_exact(client, runtime):
    owner = make_user(runtime, "Owner")
    writers = [make_user(runtime, f"W{i}") for i in range(6)]
    targets = {kind: make_target(runtime, owner, kind) for kind in ("post", "lost_pet", "adoption")}
    with ThreadPoolExecutor(max_workers=6) as pool:
        list(
            pool.map(
                lambda pair: add_comment(client, pair[0], pair[1], targets[pair[1]]),
                [(writer, kind) for writer in writers for kind in targets],
            )
        )
    for kind, target in targets.items():
        assert stored_count(runtime, kind, target) == 6
        assert_consistent(client, kind, target, None, 6)


def test_stale_stored_counter_does_not_leak_into_responses(client, runtime):
    """Historic drift (e.g. from the old account-deletion bug) is not shown to users."""
    owner = make_user(runtime, "Owner")
    post = make_post(runtime, owner, created_at=datetime.now(UTC) - timedelta(minutes=1))
    with runtime.manager.session_scope() as session:
        session.get(schema.Post, post).comment_count = 1  # counter says 1, no comment exists
    assert_consistent(client, "post", post, None, 0)
    assert feed_counts(client, owner)[str(post)] == 0


def test_drifted_stored_counters_in_both_directions_affect_no_read_or_write(client, runtime):
    """Stored counter too high (no comments) or zero (comments exist) on every publication type.

    Responses, feed membership and order, and the write paths that lock the publication row
    through the stored-counter-reading queries (comment and like creation) all behave as if the
    counter were correct.
    """
    owner, writer = make_user(runtime, "Owner"), make_user(runtime, "Writer")
    targets = {
        kind: (make_target(runtime, owner, kind), api_kind(kind))
        for kind in ("post", "needs_help", "lost_pet", "adoption")
    }
    feed_before = list(feed_counts(client, writer))
    commented = {kind: target for kind, (target, _) in targets.items() if kind != "post"}
    for kind, target in commented.items():
        add_comment(client, writer, api_kind(kind), target)
    with runtime.manager.session_scope() as session:
        for kind, (target, path_kind) in targets.items():
            # "post" claims 7 comments but has none; the others claim 0 but have one.
            session.get(MODEL[path_kind], target).comment_count = 7 if kind == "post" else 0

    for kind, (target, path_kind) in targets.items():
        expected = 0 if kind == "post" else 1
        for viewer in (None, owner, writer):
            assert_consistent(client, path_kind, target, viewer, expected)
    counts = feed_counts(client, writer)
    assert list(counts) == feed_before  # same items, same order, same pagination
    for kind, (target, _) in targets.items():
        assert counts[str(target)] == (0 if kind == "post" else 1)

    # Writes that read the stored row (lock_visible_post) still work and stay consistent.
    post = targets["post"][0]
    liked = client.post(f"{API}/posts/{post}/likes", headers=writer.h)
    assert liked.status_code in (200, 201), liked.text
    add_comment(client, writer, "post", post)
    assert_consistent(client, "post", post, writer, 1)


def test_concurrent_deletion_of_accounts_with_overlapping_publications(client, runtime):
    """Two accounts that commented on each other's publications are deleted at the same time.

    Without the up-front, ordered publication locks in ``delete_me`` this deadlocked in every
    round locally; now both deletions succeed and every stored counter stays exact.
    """
    witness = make_user(runtime, "Witness")
    for round_index in range(4):
        first, second = make_user(runtime, f"A{round_index}"), make_user(runtime, f"B{round_index}")
        targets: list[tuple[str, UUID, Person]] = []
        for owner, other in ((first, second), (second, first)):
            for _ in range(12):
                targets.append(("post", make_post(runtime, owner), other))
            targets.append(("lost_pet", make_lost_pet(runtime, owner), other))
            targets.append(("adoption", make_adoption(runtime, owner), other))
        for kind, target, other in targets:
            add_comment(client, other, kind, target)
            add_comment(client, witness, kind, target)
            if kind == "post":
                liked = client.post(f"{API}/posts/{target}/likes", headers=other.h)
                assert liked.status_code in (200, 201), liked.text

        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(
                pool.map(
                    lambda person: client.delete(f"{API}/users/me", headers=person.h).status_code,
                    (first, second),
                )
            )
        assert results == [204, 204]
        for kind, target, _ in targets:
            assert stored_count(runtime, kind, target) == active_comment_rows(runtime, kind, target)
            assert active_comment_rows(runtime, kind, target) == 1  # the witness's comment
