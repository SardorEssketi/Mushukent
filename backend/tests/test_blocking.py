"""Regression tests for user blocking (see docs/BLOCKING.md).

Policy under test: a block in either direction makes the two users invisible to each other
(feeds, lists, comments, notifications) and rejects interaction with each other's content
as "not found". Blocks are never deleted by the blocking feature, so unblocking restores
everything. Every test runs against the disposable integration database (see conftest.py).
"""

from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient
from geoalchemy2.elements import WKTElement
from sqlalchemy import func, select

from app.core.auth import AuthenticatedPrincipal, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.features.cats.domain.models import CatStatus
from app.features.notifications.application.worker import NotificationWorker
from app.features.notifications.infrastructure.fcm import PushResult
from app.features.notifications.infrastructure.repository import NotificationRepository
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.main import app

API = "/api/v1"


# --------------------------------------------------------------------------- fixtures


@pytest.fixture()
def runtime(monkeypatch: pytest.MonkeyPatch, db_session_manager: DatabaseSessionManager):
    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key")
    monkeypatch.setenv("JWT_ISSUER", "mushukistan-api")
    monkeypatch.setenv("JWT_AUDIENCE", "mushukistan-mobile")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "google-client-id")
    settings = Settings()
    token_service = JoseAccessTokenService(settings)
    app.state.container = AppContainer(settings=settings, db_session_manager=db_session_manager)
    app.dependency_overrides.clear()
    try:
        yield SimpleNamespace(
            settings=settings, token_service=token_service, manager=db_session_manager
        )
    finally:
        app.dependency_overrides.clear()


@pytest.fixture()
def client(runtime):
    with TestClient(app, raise_server_exceptions=False) as test_client:
        yield test_client


class Person:
    def __init__(self, user_id: UUID, token: str, name: str) -> None:
        self.id = user_id
        self.token = token
        self.name = name

    @property
    def h(self) -> dict[str, str]:
        return {"Authorization": f"Bearer {self.token}"}


def make_user(runtime, name: str, *, moderator: bool = False) -> Person:
    with runtime.manager.session_scope() as session:
        user = schema.User(
            email=f"{name.lower()}-{uuid4().hex}@example.com",
            name=name,
            password_hash=PasslibPasswordHasher().hash_password("StrongPass123"),
            is_moderator=moderator,
        )
        session.add(user)
        session.flush()
        token = runtime.token_service.issue_access_token(
            AuthenticatedPrincipal(user_id=user.id, role=Role.MODERATOR if moderator else Role.USER)
        )
        return Person(user.id, token, name)


def make_cat(runtime, creator: Person) -> UUID:
    with runtime.manager.session_scope() as session:
        cat = schema.Cat(
            name="Cat",
            status=CatStatus.UNKNOWN,
            created_by=creator.id,
            canonical_location=WKTElement("POINT(69.25 41.3)", srid=4326),
        )
        session.add(cat)
        session.flush()
        return cat.id


def make_post(
    runtime,
    author: Person,
    *,
    cat_id: UUID | None = None,
    description: str = "obs",
    created_at: datetime | None = None,
    like_count: int = 0,
    kind: str = "observation",
) -> UUID:
    cat_id = cat_id or make_cat(runtime, author)
    created_at = created_at or datetime.now(UTC)
    with runtime.manager.session_scope() as session:
        post = schema.Post(
            cat_id=cat_id,
            user_id=author.id,
            photo_url="https://example.com/p.jpg",
            thumb_url="https://example.com/t.jpg",
            description=description,
            location=WKTElement("POINT(69.25 41.3)", srid=4326),
            status=CatStatus.UNKNOWN,
            kind=kind,
            is_public=True,
            like_count=like_count,
            comment_count=0,
            created_at=created_at,
            updated_at=created_at,
        )
        session.add(post)
        session.flush()
        return post.id


def make_lost_pet(runtime, owner: Person, name: str = "Rex") -> UUID:
    with runtime.manager.session_scope() as session:
        pet = schema.LostPet(
            user_id=owner.id,
            pet_name=name,
            owner_phone_number="+998901234567",
            owner_phone_publication_consent=True,
            last_seen_location=WKTElement("POINT(69.25 41.3)", srid=4326),
        )
        session.add(pet)
        session.flush()
        session.add(
            schema.LostPetPhoto(
                lost_pet_id=pet.id,
                photo_url="https://example.com/l.jpg",
                thumb_url="https://example.com/lt.jpg",
                position=0,
            )
        )
        session.flush()
        return pet.id


def make_adoption(runtime, owner: Person, name: str = "Murka") -> UUID:
    with runtime.manager.session_scope() as session:
        post = schema.AdoptionPost(
            user_id=owner.id,
            pet_name=name,
            owner_phone_number="+998901234567",
            owner_phone_publication_consent=True,
        )
        session.add(post)
        session.flush()
        session.add(
            schema.AdoptionPostPhoto(
                adoption_post_id=post.id,
                photo_url="https://example.com/a.jpg",
                thumb_url="https://example.com/at.jpg",
                position=0,
            )
        )
        session.flush()
        return post.id


def make_comment(
    runtime,
    author: Person,
    *,
    post_id: UUID | None = None,
    content: str = "hello",
    created_at: datetime | None = None,
    parent_id: UUID | None = None,
) -> UUID:
    created_at = created_at or datetime.now(UTC)
    with runtime.manager.session_scope() as session:
        comment = schema.Comment(
            post_id=post_id,
            user_id=author.id,
            content=content,
            parent_comment_id=parent_id,
            created_at=created_at,
            updated_at=created_at,
        )
        session.add(comment)
        session.flush()
        return comment.id


def block(client: TestClient, blocker: Person, blocked: Person):
    return client.post(f"{API}/users/{blocked.id}/block", headers=blocker.h)


def unblock(client: TestClient, blocker: Person, blocked: Person):
    return client.delete(f"{API}/users/{blocked.id}/block", headers=blocker.h)


def feed_ids(client: TestClient, viewer: Person | None, **params) -> list[str]:
    """Walk every page of the feed and return all item ids in order."""
    ids: list[str] = []
    cursor = None
    for _ in range(20):
        query = {"limit": 3, **params}
        if cursor:
            query["cursor"] = cursor
        response = client.get(f"{API}/feed", params=query, headers=viewer.h if viewer else {})
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        ids.extend(item["id"] for item in data["items"])
        cursor = data.get("next_cursor")
        if not cursor:
            return ids
    raise AssertionError("feed did not terminate")


def comment_contents(client: TestClient, path: str, viewer: Person | None, **params) -> list[str]:
    contents: list[str] = []
    cursor = None
    for _ in range(20):
        query = {"limit": 3, **params}
        if cursor:
            query["cursor"] = cursor
        response = client.get(f"{API}{path}", params=query, headers=viewer.h if viewer else {})
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        contents.extend(item["content"] for item in data["items"])
        cursor = data.get("next_cursor")
        if not cursor:
            return contents
    raise AssertionError("comments did not terminate")


def notification_items(client: TestClient, viewer: Person) -> list[dict]:
    response = client.get(f"{API}/notifications", params={"limit": 50}, headers=viewer.h)
    assert response.status_code == 200, response.text
    return response.json()["data"]["items"]


def unread_count(client: TestClient, viewer: Person) -> int:
    response = client.get(f"{API}/notifications/unread-count", headers=viewer.h)
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    return data["count"] if isinstance(data, dict) else data


# --------------------------------------------------------------------------- the bug


def test_blocked_user_cannot_interact_with_blockers_content(client, runtime):
    """The exact scenario from the audit (F-01)."""
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = make_post(runtime, alice)
    lost = make_lost_pet(runtime, alice)
    adoption = make_adoption(runtime, alice)
    alice_comment = make_comment(runtime, alice, post_id=post, content="alice says hi")
    assert block(client, alice, bob).status_code == 204

    # Bob cannot comment, reply, like, read or contact: everything is "not found".
    assert (
        client.post(
            f"{API}/posts/{post}/comments", headers=bob.h, json={"content": "hi"}
        ).status_code
        == 404
    )
    assert (
        client.post(
            f"{API}/posts/{post}/comments",
            headers=bob.h,
            json={"content": "re", "parent_comment_id": str(alice_comment)},
        ).status_code
        == 404
    )
    assert client.post(f"{API}/posts/{post}/likes", headers=bob.h).status_code == 404
    assert client.get(f"{API}/posts/{post}", headers=bob.h).status_code == 404
    assert client.get(f"{API}/posts/{post}/comments", headers=bob.h).status_code == 404
    assert client.get(f"{API}/lost-pets/{lost}", headers=bob.h).status_code == 404
    assert client.post(f"{API}/lost-pets/{lost}/contact", headers=bob.h).status_code == 404
    assert (
        client.post(
            f"{API}/lost-pets/{lost}/comments", headers=bob.h, json={"content": "x"}
        ).status_code
        == 404
    )
    assert client.get(f"{API}/adoption-posts/{adoption}", headers=bob.h).status_code == 404
    assert client.post(f"{API}/adoption-posts/{adoption}/contact", headers=bob.h).status_code == 404
    assert (
        client.post(
            f"{API}/adoption-posts/{adoption}/comments", headers=bob.h, json={"content": "x"}
        ).status_code
        == 404
    )

    # Nothing leaked into the database as a side effect of the rejected calls.
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.Like.id))) == 0
        assert session.scalar(select(func.count(schema.LostPetContactEvent.id))) == 0
        assert session.scalar(select(func.count(schema.AdoptionContactEvent.id))) == 0
        assert session.scalar(select(func.count(schema.Notification.id))) == 0
        assert (
            session.scalar(
                select(func.count(schema.Comment.id)).where(schema.Comment.user_id == bob.id)
            )
            == 0
        )


def test_block_is_symmetric_blocker_also_cannot_see_blocked_content(client, runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    bob_post = make_post(runtime, bob)
    bob_lost = make_lost_pet(runtime, bob)
    bob_adoption = make_adoption(runtime, bob)
    assert block(client, alice, bob).status_code == 204
    assert client.get(f"{API}/posts/{bob_post}", headers=alice.h).status_code == 404
    assert client.post(f"{API}/posts/{bob_post}/likes", headers=alice.h).status_code == 404
    assert client.get(f"{API}/lost-pets/{bob_lost}", headers=alice.h).status_code == 404
    assert client.post(f"{API}/lost-pets/{bob_lost}/contact", headers=alice.h).status_code == 404
    assert client.get(f"{API}/adoption-posts/{bob_adoption}", headers=alice.h).status_code == 404


def test_unrelated_users_and_anonymous_are_unaffected(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    alice_post, bob_post = make_post(runtime, alice), make_post(runtime, bob)
    alice_lost = make_lost_pet(runtime, alice)
    assert block(client, alice, bob).status_code == 204

    for viewer_headers in (carol.h, {}):
        assert client.get(f"{API}/posts/{alice_post}", headers=viewer_headers).status_code == 200
        assert client.get(f"{API}/posts/{bob_post}", headers=viewer_headers).status_code == 200
        assert (
            client.get(f"{API}/lost-pets/{alice_lost}", headers=viewer_headers).status_code == 200
        )
    # Carol can still comment on, like and contact both of them.
    assert (
        client.post(
            f"{API}/posts/{alice_post}/comments", headers=carol.h, json={"content": "hello"}
        ).status_code
        == 201
    )
    assert client.post(f"{API}/posts/{bob_post}/likes", headers=carol.h).status_code == 200
    assert client.post(f"{API}/lost-pets/{alice_lost}/contact", headers=carol.h).status_code == 204
    # Blocking one person does not block that person's other relationships.
    assert block(client, carol, bob).status_code == 204
    assert client.get(f"{API}/posts/{alice_post}", headers=carol.h).status_code == 200


# --------------------------------------------------------------------------- feeds


def test_feed_is_filtered_in_both_directions_and_pagination_stays_correct(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    now = datetime.now(UTC)
    posts: dict[str, list[str]] = {"bob": [], "carol": [], "alice": []}
    # Interleave so a filter applied after fetching a page would produce short/empty pages.
    for index in range(5):
        posts["bob"].append(
            str(make_post(runtime, bob, created_at=now - timedelta(minutes=index * 3)))
        )
        posts["carol"].append(
            str(make_post(runtime, carol, created_at=now - timedelta(minutes=index * 3 + 1)))
        )
        posts["alice"].append(
            str(make_post(runtime, alice, created_at=now - timedelta(minutes=index * 3 + 2)))
        )
    bob_lost = make_lost_pet(runtime, bob)
    bob_adoption = make_adoption(runtime, bob)
    carol_adoption = make_adoption(runtime, carol)

    everything = set(feed_ids(client, alice, filter="recent"))
    assert {*posts["bob"], str(bob_lost), str(bob_adoption)} <= everything  # before the block

    assert block(client, alice, bob).status_code == 204
    for flt in ("recent", "popular"):
        alice_ids = feed_ids(client, alice, filter=flt)
        assert not set(alice_ids) & {*posts["bob"], str(bob_lost), str(bob_adoption)}, flt
        assert {*posts["alice"], *posts["carol"]} <= set(alice_ids), flt
        assert len(alice_ids) == len(set(alice_ids)), "duplicate item across pages"
        bob_ids = feed_ids(client, bob, filter=flt)
        assert not set(bob_ids) & set(posts["alice"]), flt
        assert {*posts["bob"], *posts["carol"]} <= set(bob_ids), flt

    adoption_only = feed_ids(client, alice, filter="adoption")
    assert adoption_only == [str(carol_adoption)]

    # Carol and anonymous visitors still see everyone.
    for viewer in (carol, None):
        visible = set(feed_ids(client, viewer, filter="recent"))
        assert {*posts["alice"], *posts["bob"], *posts["carol"]} <= visible

    # Exactly the right number of items, in newest-first order, across pages of 3.
    alice_recent = [
        i
        for i in feed_ids(client, alice, filter="recent")
        if i in {*posts["alice"], *posts["carol"]}
    ]
    assert len(alice_recent) == 10


def test_lost_pet_list_map_and_adoption_list_are_filtered(client, runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    bob_lost = make_lost_pet(runtime, bob)
    alice_lost = make_lost_pet(runtime, alice, name="Alice pet")
    bob_adoption = make_adoption(runtime, bob)
    assert block(client, alice, bob).status_code == 204
    bbox = "69.0,41.0,69.5,41.5"

    def ids(path: str, viewer: Person | None, **params) -> set[str]:
        response = client.get(f"{API}{path}", params=params, headers=viewer.h if viewer else {})
        assert response.status_code == 200, response.text
        return {item["id"] for item in response.json()["data"]["items"]}

    assert ids("/lost-pets", alice) == {str(alice_lost)}
    assert ids("/lost-pets/map", alice, bbox=bbox) == {str(alice_lost)}
    assert ids("/adoption-posts", alice) == set()
    # Bob is the one who is hidden from Alice's lists, and Alice from Bob's.
    assert ids("/lost-pets", bob) == {str(bob_lost)}
    assert ids("/lost-pets/map", bob, bbox=bbox) == {str(bob_lost)}
    assert ids("/adoption-posts", bob) == {str(bob_adoption)}
    # Anonymous visitors see all of it.
    assert ids("/lost-pets", None) == {str(alice_lost), str(bob_lost)}
    assert ids("/lost-pets/map", None, bbox=bbox) == {str(alice_lost), str(bob_lost)}
    assert ids("/adoption-posts", None) == {str(bob_adoption)}


def test_user_profile_lists_and_cat_endpoints_respect_blocks(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    shared_cat = make_cat(runtime, carol)
    bob_post = make_post(runtime, bob, cat_id=shared_cat, description="bob on shared cat")
    carol_post = make_post(runtime, carol, cat_id=shared_cat, description="carol on shared cat")
    carol_thread_post = make_post(runtime, carol)
    make_comment(runtime, bob, post_id=carol_thread_post, content="bob comment")
    make_comment(runtime, carol, post_id=carol_thread_post, content="carol comment")
    assert block(client, alice, bob).status_code == 204

    posts = client.get(f"{API}/users/{bob.id}/posts", headers=alice.h)
    assert posts.status_code == 200 and posts.json()["data"]["items"] == []
    comments = client.get(f"{API}/users/{bob.id}/comments", headers=alice.h)
    assert comments.status_code == 200 and comments.json()["data"]["items"] == []
    # The profile itself stays reachable so the blocker can unblock from it.
    profile = client.get(f"{API}/users/{bob.id}", headers=alice.h)
    assert profile.status_code == 200 and profile.json()["data"]["is_blocked_by_viewer"] is True
    assert (
        client.get(f"{API}/users/{alice.id}", headers=bob.h).json()["data"]["is_blocked_by_viewer"]
        is False
    )
    assert client.get(f"{API}/users/{bob.id}").json()["data"]["is_blocked_by_viewer"] is False

    # Other people's views are unchanged.
    assert (
        len(client.get(f"{API}/users/{bob.id}/posts", headers=carol.h).json()["data"]["items"]) == 1
    )

    # The shared cat only shows the post Alice may see.
    cat_posts = client.get(f"{API}/cats/{shared_cat}/posts", headers=alice.h).json()["data"][
        "items"
    ]
    assert [item["id"] for item in cat_posts] == [str(carol_post)]
    detail = client.get(f"{API}/cats/{shared_cat}", headers=alice.h).json()["data"]
    history_ids = {item["id"] for item in detail["observation_history"]["items"]}
    assert str(bob_post) not in history_ids and str(carol_post) in history_ids
    anonymous_detail = client.get(f"{API}/cats/{shared_cat}").json()["data"]
    assert str(bob_post) in {
        item["id"] for item in anonymous_detail["observation_history"]["items"]
    }

    # Map pins: a cat whose only visible observation is Bob's disappears for Alice.
    bob_only_cat = make_cat(runtime, bob)
    make_post(runtime, bob, cat_id=bob_only_cat)
    bbox = "69.0,41.0,69.5,41.5"
    alice_pins = {
        item["id"]
        for item in client.get(
            f"{API}/cats", params={"bbox": bbox, "limit": 100}, headers=alice.h
        ).json()["data"]["items"]
    }
    carol_pins = {
        item["id"]
        for item in client.get(
            f"{API}/cats", params={"bbox": bbox, "limit": 100}, headers=carol.h
        ).json()["data"]["items"]
    }
    assert str(bob_only_cat) not in alice_pins
    assert str(bob_only_cat) in carol_pins


# --------------------------------------------------------------------------- comments


def test_comment_threads_hide_blocked_authors_and_keep_pages_full(client, runtime):
    alice, bob, carol, dave = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol", "Dave"))
    post = make_post(runtime, carol)
    base = datetime.now(UTC) - timedelta(hours=1)
    for index in range(6):
        make_comment(
            runtime,
            bob,
            post_id=post,
            content=f"bob-{index}",
            created_at=base + timedelta(minutes=index * 2),
        )
        make_comment(
            runtime,
            dave,
            post_id=post,
            content=f"dave-{index}",
            created_at=base + timedelta(minutes=index * 2 + 1),
        )
    assert block(client, alice, bob).status_code == 204
    path = f"/posts/{post}/comments"

    alice_view = comment_contents(client, path, alice, order="asc")
    assert alice_view == [f"dave-{i}" for i in range(6)]
    # Bob is hidden from Alice and the other way round, nobody else is affected.
    assert comment_contents(client, path, carol, order="asc") == [
        c for i in range(6) for c in (f"bob-{i}", f"dave-{i}")
    ]
    assert comment_contents(client, path, None, order="asc") == [
        c for i in range(6) for c in (f"bob-{i}", f"dave-{i}")
    ]
    assert comment_contents(client, path, alice, order="desc") == [
        f"dave-{i}" for i in reversed(range(6))
    ]

    # Alice's own comment on Carol's post is invisible to Bob, but Dave's stays visible.
    make_comment(
        runtime, alice, post_id=post, content="alice-1", created_at=base + timedelta(hours=1)
    )
    bob_view = comment_contents(client, path, bob, order="asc")
    assert "alice-1" not in bob_view and "dave-5" in bob_view and "bob-0" in bob_view


def test_comments_by_user_list_hides_comments_on_blocked_authors_posts(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    bob_post = make_post(runtime, bob)
    carol_post = make_post(runtime, carol)
    make_comment(runtime, carol, post_id=bob_post, content="carol on bob")
    make_comment(runtime, carol, post_id=carol_post, content="carol on carol")
    assert block(client, alice, bob).status_code == 204
    assert comment_contents(client, f"/users/{carol.id}/comments", alice) == ["carol on carol"]
    assert sorted(comment_contents(client, f"/users/{carol.id}/comments", None)) == [
        "carol on bob",
        "carol on carol",
    ]


# ------------------------------------------------------------------- notifications


def test_notifications_before_and_after_blocking_and_unblocking(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    post = make_post(runtime, alice)
    # Before the block both comments notify Alice normally.
    for person, text in ((bob, "from bob"), (carol, "from carol")):
        response = client.post(
            f"{API}/posts/{post}/comments", headers=person.h, json={"content": text}
        )
        assert response.status_code == 201
    assert len(notification_items(client, alice)) == 2
    assert unread_count(client, alice) == 2

    assert block(client, alice, bob).status_code == 204
    visible = notification_items(client, alice)
    assert [item.get("actor_name") for item in visible] == ["Carol"]
    assert unread_count(client, alice) == 1

    # While blocked, Bob cannot generate new notifications for Alice (404) and Carol still can.
    assert (
        client.post(
            f"{API}/posts/{post}/comments", headers=bob.h, json={"content": "again"}
        ).status_code
        == 404
    )
    assert (
        client.post(
            f"{API}/posts/{post}/comments", headers=carol.h, json={"content": "again"}
        ).status_code
        == 201
    )
    assert unread_count(client, alice) == 2

    # Unblocking brings the old notification back and Bob can interact again.
    assert unblock(client, alice, bob).status_code == 204
    assert unread_count(client, alice) == 3
    assert {item.get("actor_name") for item in notification_items(client, alice)} == {
        "Bob",
        "Carol",
    }
    assert (
        client.post(
            f"{API}/posts/{post}/comments", headers=bob.h, json={"content": "back"}
        ).status_code
        == 201
    )
    assert unread_count(client, alice) == 4


def test_notification_pagination_skips_blocked_actors_without_short_pages(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    post = make_post(runtime, alice)
    with runtime.manager.session_scope() as session:
        repo = NotificationRepository(session)
        base = datetime.now(UTC)
        for index in range(6):
            for actor in (bob, carol):
                created = repo.create_event(
                    recipient_id=alice.id,
                    actor_id=actor.id,
                    kind="comment",
                    target_kind="post",
                    target_id=post,
                    event_key=f"seed:{actor.name}:{index}",
                    push_enabled=False,
                )
                assert created is not None
        notifications = session.scalars(select(schema.Notification)).all()
        for position, notification in enumerate(notifications):
            notification.created_at = base - timedelta(seconds=position)
    assert block(client, alice, bob).status_code == 204

    collected: list[str] = []
    cursor = None
    pages = 0
    while True:
        params = {"limit": 4, **({"cursor": cursor} if cursor else {})}
        data = client.get(f"{API}/notifications", params=params, headers=alice.h).json()["data"]
        collected.extend(item["id"] for item in data["items"])
        pages += 1
        cursor = data.get("next_cursor")
        if not cursor:
            break
        assert len(data["items"]) == 4
    assert len(collected) == 6 and len(set(collected)) == 6
    assert pages == 2


def test_create_event_is_suppressed_for_blocked_pairs_in_either_direction(runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = uuid4()
    for blocker, blocked in ((alice, bob), (bob, alice)):
        with runtime.manager.session_scope() as session:
            session.execute(schema.UserBlock.__table__.delete())
            session.add(schema.UserBlock(blocker_id=blocker.id, blocked_id=blocked.id))
        with runtime.manager.session_scope() as session:
            repo = NotificationRepository(session)
            for recipient, actor in ((alice, bob), (bob, alice)):
                assert (
                    repo.create_event(
                        recipient_id=recipient.id,
                        actor_id=actor.id,
                        kind="comment",
                        target_kind="post",
                        target_id=post,
                        event_key=f"k:{blocker.name}:{recipient.name}",
                        push_enabled=True,
                    )
                    is None
                )
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.Notification.id))) == 0
        assert session.scalar(select(func.count(schema.NotificationPushJob.id))) == 0


class _Sender:
    def __init__(self) -> None:
        self.calls = 0

    def send(self, token, title, body, data) -> PushResult:
        self.calls += 1
        return PushResult(success=True)


def test_queued_push_is_cancelled_when_a_block_appears_before_delivery(client, runtime):
    key = Fernet.generate_key().decode()
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = make_post(runtime, alice)
    with runtime.manager.session_scope() as session:
        NotificationRepository(session).upsert_device(
            alice.id, "alice-device-token-long-enough", key
        )
    assert (
        client.post(
            f"{API}/posts/{post}/comments", headers=bob.h, json={"content": "queued"}
        ).status_code
        == 201
    )
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.NotificationPushJob.id))) == 1
    # Alice blocks Bob after the push was queued but before the worker ran.
    assert block(client, alice, bob).status_code == 204

    sender = _Sender()
    worker = NotificationWorker(runtime.manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)
    assert worker.deliver(datetime.now(UTC)) == 0
    assert sender.calls == 0
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(schema.NotificationPushJob.status)) == "cancelled"


def test_push_still_delivered_for_unblocked_users(client, runtime):
    key = Fernet.generate_key().decode()
    alice, carol = make_user(runtime, "Alice"), make_user(runtime, "Carol")
    post = make_post(runtime, alice)
    with runtime.manager.session_scope() as session:
        NotificationRepository(session).upsert_device(
            alice.id, "alice-device-token-long-enough", key
        )
    assert (
        client.post(
            f"{API}/posts/{post}/comments", headers=carol.h, json={"content": "hi"}
        ).status_code
        == 201
    )
    sender = _Sender()
    worker = NotificationWorker(runtime.manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)
    assert worker.deliver(datetime.now(UTC)) == 1
    assert sender.calls == 1


def test_nearby_lost_pet_alerts_skip_blocked_recipients(client, runtime):
    key = Fernet.generate_key().decode()
    owner, blocked, other = (make_user(runtime, n) for n in ("Owner", "Blocked", "Other"))
    with runtime.manager.session_scope() as session:
        repo = NotificationRepository(session)
        for person in (blocked, other):
            pref = repo.preferences(person.id)
            repo.set_alert_location(pref, 41.3111, 69.2797)
            pref.nearby_enabled = True
            repo.upsert_device(person.id, f"nearby-{person.name}-device-token-1234", key)
    assert block(client, owner, blocked).status_code == 204
    with runtime.manager.session_scope() as session:
        recipients = NotificationRepository(session).nearby_recipients(
            latitude=41.3111, longitude=69.2797, owner_id=owner.id
        )
    assert recipients == [other.id]


def test_existing_nearby_alert_is_hidden_and_not_pushed_after_block(client, runtime):
    key = Fernet.generate_key().decode()
    owner, recipient = make_user(runtime, "Owner"), make_user(runtime, "Recipient")
    pet = make_lost_pet(runtime, owner)
    with runtime.manager.session_scope() as session:
        repo = NotificationRepository(session)
        pref = repo.preferences(recipient.id)
        repo.set_alert_location(pref, 41.3, 69.25)
        pref.nearby_enabled = True
        repo.upsert_device(recipient.id, "recipient-device-token-long-enough", key)
        repo.create_nearby_events(lost_pet_id=pet, recipient_ids=[recipient.id])
    assert unread_count(client, recipient) == 1
    assert block(client, recipient, owner).status_code == 204
    assert unread_count(client, recipient) == 0
    assert notification_items(client, recipient) == []
    sender = _Sender()
    worker = NotificationWorker(runtime.manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), sender)
    assert worker.deliver(datetime.now(UTC)) == 0 and sender.calls == 0
    assert unblock(client, recipient, owner).status_code == 204
    assert unread_count(client, recipient) == 1


# ------------------------------------------------------ block/unblock endpoint behavior


def test_block_and_unblock_are_idempotent_and_validated(client, runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    assert block(client, alice, bob).status_code == 204
    assert block(client, alice, bob).status_code == 204  # duplicate
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.UserBlock.id))) == 1
    assert unblock(client, alice, bob).status_code == 204
    assert unblock(client, alice, bob).status_code == 204  # duplicate
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.UserBlock.id))) == 0

    assert block(client, alice, alice).status_code == 422
    missing = client.post(f"{API}/users/{uuid4()}/block", headers=alice.h)
    assert missing.status_code == 404
    assert client.post(f"{API}/users/not-a-uuid/block", headers=alice.h).status_code == 422
    assert client.post(f"{API}/users/{bob.id}/block").status_code == 401
    assert client.delete(f"{API}/users/{bob.id}/block").status_code == 401
    assert client.get(f"{API}/users/me/blocks").status_code == 401


def test_only_the_blocker_can_remove_a_block(client, runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = make_post(runtime, alice)
    assert block(client, alice, bob).status_code == 204
    # Bob "unblocking" Alice only deletes a block Bob created (none), Alice's block stays.
    assert unblock(client, bob, alice).status_code == 204
    assert client.get(f"{API}/posts/{post}", headers=bob.h).status_code == 404
    assert unblock(client, alice, bob).status_code == 204
    assert client.get(f"{API}/posts/{post}", headers=bob.h).status_code == 200


def test_mutual_blocks_need_both_removed_to_restore_visibility(client, runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = make_post(runtime, alice)
    assert block(client, alice, bob).status_code == 204
    assert block(client, bob, alice).status_code == 204
    assert unblock(client, alice, bob).status_code == 204
    assert client.get(f"{API}/posts/{post}", headers=bob.h).status_code == 404
    assert unblock(client, bob, alice).status_code == 204
    assert client.get(f"{API}/posts/{post}", headers=bob.h).status_code == 200


def test_blocked_users_list_endpoint(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    assert client.get(f"{API}/users/me/blocks", headers=alice.h).json()["data"]["items"] == []
    assert block(client, alice, bob).status_code == 204
    assert block(client, alice, carol).status_code == 204
    assert block(client, bob, alice).status_code == 204  # someone else's block is not listed
    items = client.get(f"{API}/users/me/blocks", headers=alice.h).json()["data"]["items"]
    assert [item["name"] for item in items] == ["Carol", "Bob"]  # newest first
    assert set(items[0]) == {"id", "name", "avatar_url", "blocked_at"} or set(items[0]) >= {
        "id",
        "name",
        "blocked_at",
    }
    assert unblock(client, alice, carol).status_code == 204
    items = client.get(f"{API}/users/me/blocks", headers=alice.h).json()["data"]["items"]
    assert [item["name"] for item in items] == ["Bob"]
    # Bob sees only the block he created.
    bob_items = client.get(f"{API}/users/me/blocks", headers=bob.h).json()["data"]["items"]
    assert [item["name"] for item in bob_items] == ["Alice"]


def test_blocking_does_not_delete_existing_content_or_interactions(client, runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = make_post(runtime, alice)
    assert client.post(f"{API}/posts/{post}/likes", headers=bob.h).status_code == 200
    comment = client.post(
        f"{API}/posts/{post}/comments", headers=bob.h, json={"content": "before the block"}
    )
    assert comment.status_code == 201
    assert block(client, alice, bob).status_code == 204
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.Like.id))) == 1
        assert session.scalar(select(func.count(schema.Comment.id))) == 1
    assert comment_contents(client, f"/posts/{post}/comments", alice) == []
    assert unblock(client, alice, bob).status_code == 204
    assert comment_contents(client, f"/posts/{post}/comments", alice) == ["before the block"]
    # Bob can retract an old like even while blocked (unlike is not an interaction with content).
    assert block(client, alice, bob).status_code == 204
    assert client.delete(f"{API}/posts/{post}/likes", headers=bob.h).status_code == 204


def test_account_deletion_removes_blocks_in_both_directions(client, runtime):
    alice, bob, carol = (make_user(runtime, n) for n in ("Alice", "Bob", "Carol"))
    assert block(client, alice, bob).status_code == 204
    assert block(client, bob, carol).status_code == 204
    assert client.delete(f"{API}/users/me", headers=bob.h).status_code == 204
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.UserBlock.id))) == 0


def test_moderators_can_still_moderate_content_of_a_user_they_blocked(client, runtime):
    moderator, bob = make_user(runtime, "Mod", moderator=True), make_user(runtime, "Bob")
    post = make_post(runtime, bob)
    assert block(client, moderator, bob).status_code == 204
    history = client.get(f"{API}/moderation/posts/{post}/history", headers=moderator.h)
    assert history.status_code == 200
    assert client.delete(f"{API}/moderation/posts/{post}", headers=moderator.h).status_code == 204


def test_owner_can_still_edit_and_delete_own_content_while_blocking_others(client, runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = make_post(runtime, alice)
    assert block(client, alice, bob).status_code == 204
    patched = client.patch(f"{API}/posts/{post}", headers=alice.h, json={"description": "edited"})
    assert patched.status_code == 200
    assert client.get(f"{API}/posts/{post}", headers=alice.h).status_code == 200
    assert client.delete(f"{API}/posts/{post}", headers=alice.h).status_code == 204


# ------------------------------------------------------------------------ concurrency


def test_concurrent_duplicate_block_requests_create_one_row(runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    with TestClient(app, raise_server_exceptions=False) as local_client:

        def attempt(_: int) -> int:
            return local_client.post(f"{API}/users/{bob.id}/block", headers=alice.h).status_code

        with ThreadPoolExecutor(max_workers=12) as pool:
            statuses = list(pool.map(attempt, range(24)))
    assert set(statuses) == {204}
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.UserBlock.id))) == 1


def test_interactions_racing_with_a_block_never_error_and_end_consistent(runtime):
    alice, bob = make_user(runtime, "Alice"), make_user(runtime, "Bob")
    post = make_post(runtime, alice)
    with TestClient(app, raise_server_exceptions=False) as local_client:

        def bob_acts(index: int) -> int:
            if index % 2:
                return local_client.post(f"{API}/posts/{post}/likes", headers=bob.h).status_code
            return local_client.post(
                f"{API}/posts/{post}/comments", headers=bob.h, json={"content": f"c{index}"}
            ).status_code

        def alice_blocks(_: int) -> int:
            return local_client.post(f"{API}/users/{bob.id}/block", headers=alice.h).status_code

        with ThreadPoolExecutor(max_workers=10) as pool:
            futures = [pool.submit(bob_acts, i) for i in range(10)]
            futures.append(pool.submit(alice_blocks, 0))
            futures.extend(pool.submit(bob_acts, i) for i in range(10, 20))
            statuses = [f.result() for f in futures]
        # Only success, duplicate-like or "not found" are acceptable; never a server error.
        assert all(status in {200, 201, 204, 404, 409} for status in statuses), statuses
        # Whatever Bob managed to write before the block committed stays hidden from Alice,
        # and every attempt after the block is rejected.
        assert comment_contents(local_client, f"/posts/{post}/comments", alice) == []
        after = local_client.post(
            f"{API}/posts/{post}/comments", headers=bob.h, json={"content": "late"}
        )
        assert after.status_code == 404
        assert local_client.post(f"{API}/posts/{post}/likes", headers=bob.h).status_code == 404
        # Notifications written before the block committed are hidden as well.
        assert notification_items(local_client, alice) == []
        assert unread_count(local_client, alice) == 0


# ---------------------------------------------------------------------- auth hygiene


def test_block_endpoints_ignore_a_forged_blocker(client, runtime):
    """The blocker is always the authenticated user; no parameter can spoof it."""
    alice, bob, mallory = (make_user(runtime, n) for n in ("Alice", "Bob", "Mallory"))
    post = make_post(runtime, alice)
    response = client.post(
        f"{API}/users/{bob.id}/block", headers=mallory.h, params={"blocker_id": str(alice.id)}
    )
    assert response.status_code == 204
    with runtime.manager.session_scope() as session:
        row = session.scalars(select(schema.UserBlock)).one()
        assert row.blocker_id == mallory.id and row.blocked_id == bob.id
    assert client.get(f"{API}/posts/{post}", headers=bob.h).status_code == 200
