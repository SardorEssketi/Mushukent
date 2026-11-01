"""Moderators can remove every publication type (Issue #5).

Covers direct deletion and report actions for lost-pet and adoption posts (previously owner-only),
unchanged behaviour for regular and Needs Help posts, attribution (``deleted_by_id``,
``post_history``, ``reports.handled_by``), the owner's single "publication removed" notification
and its push, and that related records survive. Runs against the disposable integration database.
"""

from __future__ import annotations

import sys
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

from cryptography.fernet import Fernet
from sqlalchemy import func, select

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401  (pytest fixtures)
    API,
    Person,
    _Sender,
    block,
    client,
    make_adoption,
    make_lost_pet,
    make_post,
    make_user,
    runtime,
)

from app.core.config import Settings  # noqa: E402
from app.features.notifications.application.worker import NotificationWorker  # noqa: E402
from app.features.notifications.infrastructure.repository import (  # noqa: E402
    NotificationRepository,
)
from app.infrastructure.db.models import schema  # noqa: E402

SPECIAL = {
    "lost_pet": ("/lost-pets", schema.LostPet, make_lost_pet, "LOST_PET_NOT_FOUND"),
    "adoption_post": (
        "/adoption-posts",
        schema.AdoptionPost,
        make_adoption,
        "ADOPTION_POST_NOT_FOUND",
    ),
}


def removal_notices(runtime, owner: Person) -> list[schema.Notification]:
    with runtime.manager.session_scope() as session:
        rows = session.scalars(
            select(schema.Notification).where(
                schema.Notification.recipient_id == owner.id,
                schema.Notification.kind == "publication_removed",
            )
        ).all()
        session.expunge_all()
        return list(rows)


def row(runtime, model, target_id: UUID):
    with runtime.manager.session_scope() as session:
        item = session.get(model, target_id)
        session.expunge_all()
        return item


def listed_ids(client, path: str, viewer: Person | None = None) -> set[str]:
    response = client.get(f"{API}{path}", params={"limit": 50}, headers=viewer.h if viewer else {})
    assert response.status_code == 200, response.text
    return {item["id"] for item in response.json()["data"]["items"]}


def report(client, reporter: Person, target_type: str, target_id: UUID) -> str:
    response = client.post(
        f"{API}/reports",
        json={"target_type": target_type, "target_id": str(target_id), "reason": "spam"},
        headers=reporter.h,
    )
    assert response.status_code in (200, 201), response.text
    return response.json()["data"]["id"]


def handle(client, moderator: Person, report_id: str, action: str | None = "soft_delete_post"):
    body = {"status": "resolved"}
    if action:
        body["action"] = action
    return client.patch(f"{API}/moderation/reports/{report_id}", json=body, headers=moderator.h)


# --------------------------------------------------------------------------- direct deletion


def test_moderator_removes_lost_pet_and_adoption_posts(client, runtime):
    moderator = make_user(runtime, "Mod", moderator=True)
    owner, viewer = make_user(runtime, "Owner"), make_user(runtime, "Viewer")
    for target_kind, (path, model, factory, _) in SPECIAL.items():
        target = factory(runtime, owner)
        assert str(target) in listed_ids(client, path)

        response = client.delete(f"{API}{path}/{target}", headers=moderator.h)
        assert response.status_code == 204, response.text

        item = row(runtime, model, target)
        assert item.deleted_at is not None
        assert item.deleted_by_id == moderator.id  # attribution survives the soft delete
        assert item.user_id == owner.id  # ownership is not rewritten
        for who in (None, viewer, owner):
            assert str(target) not in listed_ids(client, path, who)
            assert (
                client.get(f"{API}{path}/{target}", headers=who.h if who else {}).status_code == 404
            )
        assert str(target) not in {i for i in listed_ids(client, "/feed", viewer)}

        notices = [n for n in removal_notices(runtime, owner) if n.target_id == target]
        assert len(notices) == 1
        assert notices[0].target_kind == target_kind
        assert notices[0].actor_id is None  # the moderator is never revealed


def test_owner_deletion_is_attributed_to_the_owner_and_not_notified(client, runtime):
    owner = make_user(runtime, "Owner")
    for path, model, factory, _ in SPECIAL.values():
        target = factory(runtime, owner)
        assert client.delete(f"{API}{path}/{target}", headers=owner.h).status_code == 204
        item = row(runtime, model, target)
        assert item.deleted_at is not None and item.deleted_by_id == owner.id
    assert removal_notices(runtime, owner) == []


def test_ordinary_users_cannot_delete_other_users_publications(client, runtime):
    owner, stranger = make_user(runtime, "Owner"), make_user(runtime, "Stranger")
    moderator = make_user(runtime, "Mod", moderator=True)
    for path, model, factory, not_found in SPECIAL.values():
        target = factory(runtime, owner)
        response = client.delete(f"{API}{path}/{target}", headers=stranger.h)
        assert response.status_code == 403, response.text
        # Existing per-type codes are kept.
        forbidden = "FORBIDDEN" if model is schema.LostPet else "ADOPTION_POST_FORBIDDEN"
        assert response.json()["error"]["code"] == forbidden
        assert row(runtime, model, target).deleted_at is None

        missing = UUID("00000000-0000-4000-8000-000000000000")
        for who in (stranger, moderator):
            response = client.delete(f"{API}{path}/{missing}", headers=who.h)
            assert response.status_code == 404
            assert response.json()["error"]["code"] == not_found
        assert client.delete(f"{API}{path}/{target}").status_code == 401
    assert removal_notices(runtime, owner) == []


def test_repeated_deletion_is_safe_and_notifies_once(client, runtime):
    owner, stranger = make_user(runtime, "Owner"), make_user(runtime, "Stranger")
    first, second = (make_user(runtime, n, moderator=True) for n in ("ModA", "ModB"))
    for path, model, factory, _ in SPECIAL.values():
        target = factory(runtime, owner)
        assert client.delete(f"{API}{path}/{target}", headers=first.h).status_code == 204
        deleted_at = row(runtime, model, target).deleted_at
        for who in (first, second, owner):
            assert client.delete(f"{API}{path}/{target}", headers=who.h).status_code == 204
        # A stranger keeps the existing answer for someone else's post.
        assert client.delete(f"{API}{path}/{target}", headers=stranger.h).status_code == 403
        item = row(runtime, model, target)
        assert item.deleted_at == deleted_at and item.deleted_by_id == first.id
    assert len(removal_notices(runtime, owner)) == 2  # one per publication


def test_regular_and_needs_help_posts_keep_moderation_and_notify_owner(client, runtime):
    moderator = make_user(runtime, "Mod", moderator=True)
    owner = make_user(runtime, "Owner")
    regular = make_post(runtime, owner)
    needs_help = make_post(runtime, owner, kind="needs_help")
    own = make_post(runtime, owner)

    assert client.delete(f"{API}/posts/{regular}", headers=moderator.h).status_code == 204
    assert (
        client.delete(f"{API}/moderation/posts/{needs_help}", headers=moderator.h).status_code
        == 204
    )
    assert (
        client.delete(f"{API}/moderation/posts/{needs_help}", headers=moderator.h).status_code
        == 204
    )
    assert client.delete(f"{API}/posts/{own}", headers=owner.h).status_code == 204

    with runtime.manager.session_scope() as session:
        history = session.execute(
            select(schema.PostHistory.post_id, schema.PostHistory.actor_id).where(
                schema.PostHistory.action == "deleted"
            )
        ).all()
    assert set(history) == {(regular, moderator.id), (needs_help, moderator.id), (own, owner.id)}
    notices = removal_notices(runtime, owner)
    assert {(n.target_kind, n.target_id) for n in notices} == {
        ("post", regular),
        ("post", needs_help),
    }


# --------------------------------------------------------------------------- notifications


def test_removal_notice_is_listed_without_moderator_and_survives_blocks(client, runtime):
    moderator = make_user(runtime, "Mod", moderator=True)
    owner = make_user(runtime, "Owner")
    lost_pet = make_lost_pet(runtime, owner)
    assert block(client, owner, moderator).status_code == 204  # owner blocked the moderator
    assert client.delete(f"{API}/lost-pets/{lost_pet}", headers=moderator.h).status_code == 204

    response = client.get(f"{API}/notifications", headers=owner.h)
    assert response.status_code == 200, response.text
    items = response.json()["data"]["items"]
    assert len(items) == 1
    assert items[0]["kind"] == "publication_removed"
    assert items[0]["target_kind"] == "lost_pet"
    assert items[0]["target_id"] == str(lost_pet)
    assert items[0]["actor_name"] is None
    unread = client.get(f"{API}/notifications/unread-count", headers=owner.h).json()["data"]
    assert (unread["count"] if isinstance(unread, dict) else unread) == 1


def test_removal_push_is_delivered_once_in_the_owner_language(client, runtime):
    key = Fernet.generate_key().decode()
    moderator = make_user(runtime, "Mod", moderator=True)
    owner = make_user(runtime, "Owner")
    with runtime.manager.session_scope() as session:
        NotificationRepository(session).upsert_device(
            owner.id, "owner-device-token-long-enough", key
        )
        session.get(schema.User, owner.id).preferred_language = "ru"
    adoption = make_adoption(runtime, owner)
    assert client.delete(f"{API}/adoption-posts/{adoption}", headers=moderator.h).status_code == 204
    assert client.delete(f"{API}/adoption-posts/{adoption}", headers=moderator.h).status_code == 204

    sent = []

    class Sender(_Sender):
        def send(self, token, title, body, data):
            sent.append((title, data))
            return super().send(token, title, body, data)

    worker = NotificationWorker(runtime.manager, Settings(PUSH_TOKEN_ENCRYPTION_KEY=key), Sender())
    assert worker.deliver(datetime.now(UTC)) == 1
    assert worker.deliver(datetime.now(UTC)) == 0
    assert sent[0][0] == "Публикация удалена"
    assert sent[0][1]["kind"] == "publication_removed"
    assert sent[0][1]["target_kind"] == "adoption_post"


def test_publication_of_a_deleted_account_is_removed_without_notification(client, runtime):
    moderator = make_user(runtime, "Mod", moderator=True)
    owner = make_user(runtime, "Owner")
    lost_pet = make_lost_pet(runtime, owner)
    with runtime.manager.session_scope() as session:
        session.get(schema.LostPet, lost_pet).user_id = None  # owner account gone
    assert client.delete(f"{API}/lost-pets/{lost_pet}", headers=moderator.h).status_code == 204
    with runtime.manager.session_scope() as session:
        assert session.scalar(select(func.count(schema.Notification.id))) == 0


# --------------------------------------------------------------------------- reports


def test_report_action_removes_lost_pet_and_adoption_once_for_many_reports(client, runtime):
    moderator = make_user(runtime, "Mod", moderator=True)
    owner = make_user(runtime, "Owner")
    reporters = [make_user(runtime, f"R{i}") for i in range(2)]
    for target_type, (path, model, factory, not_found) in SPECIAL.items():
        target = factory(runtime, owner)
        first, second = (report(client, who, target_type, target) for who in reporters)

        handled = handle(client, moderator, first)
        assert handled.status_code == 200, handled.text
        assert handled.json()["data"]["status"] == "resolved"
        item = row(runtime, model, target)
        assert item.deleted_at is not None and item.deleted_by_id == moderator.id
        deleted_at = item.deleted_at

        # The second report on the same target resolves without a second side effect.
        handled = handle(client, moderator, second)
        assert handled.status_code == 200, handled.text
        assert row(runtime, model, target).deleted_at == deleted_at
        assert handle(client, moderator, first).status_code == 409  # already handled

        # Reports stay auditable: who handled them and the (deleted) target preview.
        for report_id in (first, second):
            detail = client.get(f"{API}/moderation/reports/{report_id}", headers=moderator.h)
            assert detail.status_code == 200, detail.text
            data = detail.json()["data"]
            assert data["handled_by"]["id"] == str(moderator.id)
            assert data["handled_at"] is not None
            assert data["target"]["id"] == str(target)
            assert data["target"]["deleted_at"] is not None
        # A deleted target cannot be reported again or come back.
        response = client.post(
            f"{API}/reports",
            json={"target_type": target_type, "target_id": str(target), "reason": "again"},
            headers=reporters[0].h,
        )
        assert response.status_code == 404 and response.json()["error"]["code"] == not_found
        assert str(target) not in listed_ids(client, path)
    assert len(removal_notices(runtime, owner)) == 2


def test_report_actions_that_do_not_match_the_target_are_rejected(client, runtime):
    moderator = make_user(runtime, "Mod", moderator=True)
    owner, reporter = make_user(runtime, "Owner"), make_user(runtime, "Reporter")
    for target_type, (_, model, factory, _) in SPECIAL.items():
        target = factory(runtime, owner)
        report_id = report(client, reporter, target_type, target)
        response = handle(client, moderator, report_id, "soft_delete_comment")
        assert response.status_code == 400
        assert row(runtime, model, target).deleted_at is None
        # The report is still open and can be dismissed normally.
        dismissed = client.patch(
            f"{API}/moderation/reports/{report_id}",
            json={"status": "dismissed"},
            headers=moderator.h,
        )
        assert dismissed.status_code == 200, dismissed.text
        assert row(runtime, model, target).deleted_at is None
    assert removal_notices(runtime, owner) == []


def test_ordinary_users_cannot_use_moderation_routes(client, runtime):
    owner, stranger = make_user(runtime, "Owner"), make_user(runtime, "Stranger")
    lost_pet = make_lost_pet(runtime, owner)
    report_id = report(client, stranger, "lost_pet", lost_pet)
    assert handle(client, stranger, report_id).status_code == 403
    assert row(runtime, schema.LostPet, lost_pet).deleted_at is None


# --------------------------------------------------------------------------- related records


def test_removal_keeps_related_records_and_account_deletion_clears_attribution(client, runtime):
    moderator = make_user(runtime, "Mod", moderator=True)
    owner, commenter = make_user(runtime, "Owner"), make_user(runtime, "Commenter")
    lost_pet = make_lost_pet(runtime, owner)
    comment = client.post(
        f"{API}/lost-pets/{lost_pet}/comments", json={"content": "seen"}, headers=commenter.h
    )
    assert comment.status_code == 201, comment.text
    assert client.delete(f"{API}/lost-pets/{lost_pet}", headers=moderator.h).status_code == 204

    with runtime.manager.session_scope() as session:
        # Soft delete only: photos and comments stay, nothing cascades.
        assert (
            session.scalar(
                select(func.count(schema.LostPetPhoto.id)).where(
                    schema.LostPetPhoto.lost_pet_id == lost_pet
                )
            )
            == 1
        )
        assert (
            session.scalar(
                select(func.count(schema.Comment.id)).where(schema.Comment.lost_pet_id == lost_pet)
            )
            == 1
        )
        assert session.get(schema.User, owner.id).is_active

    # Deleting the moderator's account anonymizes the attribution, like comments.deleted_by_id.
    assert client.delete(f"{API}/users/me", headers=moderator.h).status_code == 204
    item = row(runtime, schema.LostPet, lost_pet)
    assert item.deleted_at is not None and item.deleted_by_id is None
    assert len(removal_notices(runtime, owner)) == 1
