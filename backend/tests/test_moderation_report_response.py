"""AUTH-219: a successful moderation decision returns the committed state.

The PATCH /moderation/reports/{id} response must agree with an immediately following GET for
every decision (removal, resolve without action, dismiss, already-deleted target, suspension),
and stale or concurrent decisions must not cause a second deletion, counter change or notice.
Runs against the disposable integration database.
"""

from __future__ import annotations

import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from pathlib import Path
from uuid import UUID

import pytest
from sqlalchemy import func, select

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401  (pytest fixtures)
    API,
    Person,
    client,
    make_adoption,
    make_comment,
    make_lost_pet,
    make_post,
    make_user,
    runtime,
)

from app.infrastructure.db.models import schema  # noqa: E402

pytestmark = pytest.mark.integration


def _report(client, reporter: Person, target_type: str, target_id: UUID) -> str:
    response = client.post(
        f"{API}/reports",
        json={"target_type": target_type, "target_id": str(target_id), "reason": "spam"},
        headers=reporter.h,
    )
    assert response.status_code in (200, 201), response.text
    return response.json()["data"]["id"]


def _patch(client, moderator: Person, report_id: str, status: str, action: str | None = None):
    body: dict[str, str] = {"status": status}
    if action:
        body["action"] = action
    return client.patch(f"{API}/moderation/reports/{report_id}", json=body, headers=moderator.h)


def _get(client, moderator: Person, report_id: str) -> dict:
    response = client.get(f"{API}/moderation/reports/{report_id}", headers=moderator.h)
    assert response.status_code == 200, response.text
    return response.json()["data"]


def _count(runtime, model, *conditions) -> int:
    with runtime.manager.session_scope() as session:
        return int(session.scalar(select(func.count()).select_from(model).where(*conditions)))


def _notices(runtime, owner: Person) -> int:
    return _count(
        runtime,
        schema.Notification,
        schema.Notification.recipient_id == owner.id,
        schema.Notification.kind == "publication_removed",
    )


def _assert_response_matches_fresh_read(client, moderator: Person, response) -> dict:
    assert response.status_code == 200, response.text
    returned = response.json()["data"]
    assert returned == _get(client, moderator, returned["id"])
    return returned


@pytest.fixture()
def people(runtime):
    return {
        "owner": make_user(runtime, "Owner"),
        "reporter": make_user(runtime, "Reporter"),
        "mod": make_user(runtime, "Mod", moderator=True),
        "mod2": make_user(runtime, "Mod Two", moderator=True),
    }


def test_soft_delete_post_response_shows_the_removed_target(client, runtime, people):
    post_id = make_post(runtime, people["owner"])
    report_id = _report(client, people["reporter"], "post", post_id)

    data = _assert_response_matches_fresh_read(
        client,
        people["mod"],
        _patch(client, people["mod"], report_id, "resolved", "soft_delete_post"),
    )

    assert data["status"] == "resolved"
    assert data["handled_by"]["id"] == str(people["mod"].id)
    assert data["handled_at"]
    assert data["reporter"]["id"] == str(people["reporter"].id)
    assert data["target"]["is_active"] is False
    assert data["target"]["deleted_at"]
    assert _notices(runtime, people["owner"]) == 1
    assert (
        _count(
            runtime,
            schema.PostHistory,
            schema.PostHistory.post_id == post_id,
            schema.PostHistory.action == "deleted",
        )
        == 1
    )


@pytest.mark.parametrize("kind", ["lost_pet", "adoption_post"])
def test_soft_delete_special_publication_response_shows_removal(client, runtime, people, kind):
    factory = make_lost_pet if kind == "lost_pet" else make_adoption
    target_id = factory(runtime, people["owner"])
    report_id = _report(client, people["reporter"], kind, target_id)

    data = _assert_response_matches_fresh_read(
        client,
        people["mod"],
        _patch(client, people["mod"], report_id, "resolved", "soft_delete_post"),
    )

    assert data["target"]["is_active"] is False
    assert data["target"]["deleted_at"]
    assert _notices(runtime, people["owner"]) == 1


def test_soft_delete_comment_response_and_single_counter_change(client, runtime, people):
    post_id = make_post(runtime, people["reporter"])
    comment_id = make_comment(runtime, people["owner"], post_id=post_id, content="rude")
    with runtime.manager.session_scope() as session:
        session.get(schema.Post, post_id).comment_count = 1
    report_id = _report(client, people["reporter"], "comment", comment_id)

    data = _assert_response_matches_fresh_read(
        client,
        people["mod"],
        _patch(client, people["mod"], report_id, "resolved", "soft_delete_comment"),
    )

    assert data["target"]["is_active"] is False
    assert data["target"]["deleted_at"]
    with runtime.manager.session_scope() as session:
        assert session.get(schema.Post, post_id).comment_count == 0


@pytest.mark.parametrize("status", ["resolved", "dismissed"])
def test_decision_without_action_keeps_target_active(client, runtime, people, status):
    post_id = make_post(runtime, people["owner"])
    report_id = _report(client, people["reporter"], "post", post_id)

    data = _assert_response_matches_fresh_read(
        client, people["mod"], _patch(client, people["mod"], report_id, status)
    )

    assert data["status"] == status
    assert data["target"]["is_active"] is True
    assert "deleted_at" not in data["target"]
    assert _notices(runtime, people["owner"]) == 0


def test_already_deleted_target_is_reported_unchanged(client, runtime, people):
    post_id = make_post(runtime, people["reporter"])
    comment_id = make_comment(runtime, people["owner"], post_id=post_id, content="gone")
    report_id = _report(client, people["reporter"], "comment", comment_id)
    owner_deleted_at = datetime(2026, 11, 1, 12, 0, tzinfo=UTC)
    with runtime.manager.session_scope() as session:
        session.get(schema.Comment, comment_id).deleted_at = owner_deleted_at
        session.get(schema.Post, post_id).comment_count = 0
    before = _get(client, people["mod"], report_id)
    assert before["target"]["is_active"] is False

    data = _assert_response_matches_fresh_read(
        client,
        people["mod"],
        _patch(client, people["mod"], report_id, "resolved", "soft_delete_comment"),
    )

    assert data["target"] == before["target"]  # the owner's deletion is not repeated or moved
    with runtime.manager.session_scope() as session:
        assert session.get(schema.Post, post_id).comment_count == 0


def test_suspend_user_response_shows_inactive_user(client, runtime, people):
    report_id = _report(client, people["reporter"], "user", people["owner"].id)

    data = _assert_response_matches_fresh_read(
        client, people["mod"], _patch(client, people["mod"], report_id, "resolved", "suspend_user")
    )

    assert data["target"]["is_active"] is False


def test_stale_repeat_decision_is_rejected_without_side_effects(client, runtime, people):
    post_id = make_post(runtime, people["owner"])
    report_id = _report(client, people["reporter"], "post", post_id)
    first = _patch(client, people["mod"], report_id, "resolved", "soft_delete_post")
    committed = _assert_response_matches_fresh_read(client, people["mod"], first)

    for moderator, status, action in (
        (people["mod"], "resolved", "soft_delete_post"),
        (people["mod2"], "dismissed", None),
    ):
        repeat = _patch(client, moderator, report_id, status, action)
        assert repeat.status_code == 409
        assert repeat.json()["error"]["code"] == "REPORT_ALREADY_HANDLED"

    assert _get(client, people["mod"], report_id) == committed
    assert _notices(runtime, people["owner"]) == 1


def test_concurrent_decisions_commit_exactly_one(client, runtime, people):
    post_id = make_post(runtime, people["owner"])
    report_id = _report(client, people["reporter"], "post", post_id)
    attempts = [
        (people["mod"], "resolved", "soft_delete_post"),
        (people["mod2"], "dismissed", None),
    ]

    with ThreadPoolExecutor(max_workers=2) as pool:
        responses = list(pool.map(lambda a: _patch(client, a[0], report_id, a[1], a[2]), attempts))

    codes = sorted(response.status_code for response in responses)
    assert codes == [200, 409]
    winner = next(response for response in responses if response.status_code == 200)
    loser = next(response for response in responses if response.status_code == 409)
    assert loser.json()["error"]["code"] == "REPORT_ALREADY_HANDLED"
    data = _assert_response_matches_fresh_read(client, people["mod"], winner)

    removed = data["status"] == "resolved"
    assert data["target"]["is_active"] is (not removed)
    assert _notices(runtime, people["owner"]) == (1 if removed else 0)
    assert _count(
        runtime,
        schema.PostHistory,
        schema.PostHistory.post_id == post_id,
        schema.PostHistory.action == "deleted",
    ) == (1 if removed else 0)


def test_non_moderators_cannot_read_or_handle_reports(client, runtime, people):
    post_id = make_post(runtime, people["owner"])
    report_id = _report(client, people["reporter"], "post", post_id)

    for person in (people["owner"], people["reporter"]):
        assert client.get(f"{API}/moderation/reports", headers=person.h).status_code == 403
        assert (
            client.get(f"{API}/moderation/reports/{report_id}", headers=person.h).status_code == 403
        )
        assert _patch(client, person, report_id, "dismissed").status_code == 403
    assert client.get(f"{API}/moderation/reports").status_code == 401
    assert _get(client, people["mod"], report_id)["status"] == "open"
