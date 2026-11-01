from unittest.mock import Mock, patch

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session
from test_posts import _create_user_with_token, _jpeg_bytes, client, posts_runtime  # noqa: F401

from app.infrastructure.db.models import schema
from app.infrastructure.db.session import CommitOutcomeUnknownError, DatabaseSessionManager


def test_connection_cleanup_cannot_turn_a_committed_operation_into_failure():
    manager = DatabaseSessionManager("sqlite://")
    session = Mock()
    session.close.side_effect = RuntimeError("connection close failure")
    manager.session_factory = lambda: session
    with manager.session_scope():
        pass
    session.commit.assert_called_once()
    session.rollback.assert_not_called()
    manager.dispose()


def test_rollback_failure_preserves_unknown_commit_classification():
    manager = DatabaseSessionManager("sqlite://")
    session = Mock()
    session.commit.side_effect = RuntimeError("lost commit acknowledgement")
    session.rollback.side_effect = RuntimeError("connection is gone")
    manager.session_factory = lambda: session
    with pytest.raises(CommitOutcomeUnknownError):
        with manager.session_scope():
            pass
    manager.dispose()


@pytest.mark.parametrize("kind", ["observation", "needs_help", "lost_pet", "adoption"])
def test_lost_commit_acknowledgement_preserves_committed_media(client, posts_runtime, kind):
    user, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="commit-outcome@example.test",
    )
    with posts_runtime.db_session_manager.session_scope() as session:
        session.get(schema.User, user.id).phone_number = "+998901234567"
    if kind in {"observation", "needs_help"}:
        endpoint, model = "posts", schema.Post
        fields = {
            "kind": kind,
            "description": "Disposable test",
            "location": '{"latitude":41.3,"longitude":69.25}',
        }
    elif kind == "lost_pet":
        endpoint, model = "lost-pets", schema.LostPet
        fields = {
            "pet_name": "Test",
            "last_seen_location": '{"latitude":41.3,"longitude":69.25}',
            "owner_phone_publication_consent": "true",
        }
    else:
        endpoint, model = "adoption-posts", schema.AdoptionPost
        fields = {"pet_name": "Test", "owner_contact_consent": "true"}
    original_commit = Session.commit

    def commit_then_lose_ack(session):
        original_commit(session)
        raise RuntimeError("Injected lost acknowledgement")

    with patch.object(Session, "commit", commit_then_lose_ack):
        response = client.post(
            f"/api/v1/{endpoint}",
            headers={"Authorization": f"Bearer {token}", "X-Contact-Mode": "reveal"},
            data=fields,
            files={"photos": ("test.jpg", _jpeg_bytes(), "image/jpeg")},
        )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "PUBLICATION_OUTCOME_UNKNOWN"
    with posts_runtime.db_session_manager.engine.connect() as connection:
        assert connection.scalar(select(func.count()).select_from(model)) == 1
    assert len(posts_runtime.fake_storage.objects) == 2
    assert not posts_runtime.fake_storage.deleted_keys
# ruff: noqa: F811
