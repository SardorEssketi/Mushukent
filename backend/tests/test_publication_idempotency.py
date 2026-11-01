from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Event
from unittest.mock import patch
from uuid import uuid4

import pytest
from sqlalchemy import func, select
from sqlalchemy.orm import Session
from test_posts import _create_user_with_token, _jpeg_bytes, client, posts_runtime  # noqa: F401

from app.core.storage import StorageOperationError
from app.infrastructure.db.models import schema
from app.infrastructure.publication_operations import PublicationOperations


def publication_case(runtime, kind):
    user, token = _create_user_with_token(
        runtime.db_session_manager, runtime.token_service, email=f"{uuid4()}@example.test"
    )
    with runtime.db_session_manager.session_scope() as session:
        session.get(schema.User, user.id).phone_number = "+998901234567"
    if kind in {"observation", "needs_help"}:
        endpoint, model = "posts", schema.Post
        fields = {
            "kind": kind,
            "description": "Test",
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
    headers = {
        "Authorization": f"Bearer {token}",
        "X-Contact-Mode": "reveal",
        "Idempotency-Key": str(uuid4()),
    }
    return user, endpoint, model, fields, headers


def send(client, case, **changes):
    _, endpoint, _, fields, headers = case
    return client.post(
        f"/api/v1/{endpoint}",
        headers=headers,
        data={**fields, **changes},
        files={"photos": ("generated.jpg", _jpeg_bytes(), "image/jpeg")},
    )


@pytest.mark.parametrize("kind", ["observation", "needs_help", "lost_pet", "adoption"])
def test_replay_returns_same_publication_without_more_media(client, posts_runtime, kind):
    case = publication_case(posts_runtime, kind)
    first, second = send(client, case), send(client, case)
    assert first.status_code == second.status_code == 201
    assert first.json()["data"]["id"] == second.json()["data"]["id"]
    assert len(posts_runtime.fake_storage.objects) == 2
    with posts_runtime.db_session_manager.engine.connect() as connection:
        assert connection.scalar(select(func.count()).select_from(case[2])) == 1
    status = client.get(
        f"/api/v1/publication-operations/{case[4]['Idempotency-Key']}", headers=case[4]
    )
    assert status.json()["data"]["state"] == "completed"
    assert "media_keys" not in status.json()["data"]


def test_changed_payload_conflicts_and_other_accounts_cannot_read_status(client, posts_runtime):
    case = publication_case(posts_runtime, "observation")
    assert send(client, case).status_code == 201
    response = send(client, case, description="Different content")
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "PUBLICATION_KEY_CONFLICT"
    other = publication_case(posts_runtime, "observation")
    status = client.get(
        f"/api/v1/publication-operations/{case[4]['Idempotency-Key']}", headers=other[4]
    )
    assert status.status_code == 404
    other[4]["Idempotency-Key"] = case[4]["Idempotency-Key"]
    assert send(client, other).status_code == 201


def test_overlapping_requests_do_not_start_second_upload(client, posts_runtime, monkeypatch):
    case = publication_case(posts_runtime, "observation")
    entered, release = Event(), Event()
    original = type(posts_runtime.fake_storage).upload

    def delayed(storage, **kwargs):
        entered.set()
        assert release.wait(5)
        return original(storage, **kwargs)

    monkeypatch.setattr(type(posts_runtime.fake_storage), "upload", delayed)
    with ThreadPoolExecutor() as pool:
        first = pool.submit(send, client, case)
        assert entered.wait(5)
        try:
            second = send(client, case)
            assert second.status_code == 409
            assert second.json()["error"]["code"] == "PUBLICATION_IN_PROGRESS"
        finally:
            release.set()
        assert first.result().status_code == 201
    assert len(posts_runtime.fake_storage.objects) == 2


def test_lost_final_commit_acknowledgement_is_reconciled(client, posts_runtime):
    case = publication_case(posts_runtime, "observation")
    original = Session.commit

    def commit(session):
        completed = any(
            isinstance(obj, schema.PublicationOperation) and obj.state == "completed"
            for obj in session.dirty
        )
        original(session)
        if completed:
            raise RuntimeError("lost acknowledgement")

    with patch.object(Session, "commit", commit):
        result = send(client, case)
    assert result.status_code == 201
    assert send(client, case).json()["data"]["id"] == result.json()["data"]["id"]
    assert len(posts_runtime.fake_storage.objects) == 2


def test_expired_attempt_is_fenced_before_finalization(posts_runtime):
    user, *_ = publication_case(posts_runtime, "observation")
    operations = PublicationOperations(posts_runtime.db_session_manager)
    key = uuid4()
    first = operations.reserve(user.id, key, "post", "digest")
    with posts_runtime.db_session_manager.session_scope() as session:
        session.get(schema.PublicationOperation, (user.id, key)).lease_expires_at = datetime.now(
            UTC
        ) - timedelta(seconds=1)
    second = operations.reserve(user.id, key, "post", "digest")
    assert first.target_id == second.target_id
    assert first.owner_token != second.owner_token
    with pytest.raises(Exception) as error:
        with posts_runtime.db_session_manager.session_scope() as session:
            first.complete(session)
    assert error.value.status_code == 409


def test_ambiguous_put_is_journaled_and_retry_is_safe(client, posts_runtime, monkeypatch):
    case = publication_case(posts_runtime, "observation")
    original = type(posts_runtime.fake_storage).upload
    failed = False

    def lost_ack(storage, **kwargs):
        nonlocal failed
        result = original(storage, **kwargs)
        if not failed:
            failed = True
            raise StorageOperationError("PUT acknowledgement lost")
        return result

    monkeypatch.setattr(type(posts_runtime.fake_storage), "upload", lost_ack)
    assert send(client, case).status_code == 502
    assert not posts_runtime.fake_storage.objects
    assert send(client, case).status_code == 201
    with posts_runtime.db_session_manager.session_scope() as session:
        operation = session.get(
            schema.PublicationOperation, (case[0].id, case[4]["Idempotency-Key"])
        )
        assert operation.state == "completed"
        assert len(operation.media_keys) == 3


@pytest.mark.parametrize("kind", ["observation", "needs_help", "lost_pet", "adoption"])
def test_socket_timeout_then_replay_creates_one_publication(
    client, posts_runtime, monkeypatch, kind
):
    import socket
    from threading import Thread
    from time import monotonic, sleep

    import httpx
    import uvicorn

    from app.main import app

    case = publication_case(posts_runtime, kind)
    original = type(posts_runtime.fake_storage).upload

    def delayed(storage, **kwargs):
        sleep(0.12)
        return original(storage, **kwargs)

    monkeypatch.setattr(type(posts_runtime.fake_storage), "upload", delayed)
    listener = socket.socket()
    listener.bind(("127.0.0.1", 0))
    server = uvicorn.Server(
        uvicorn.Config(app, lifespan="off", log_level="critical", access_log=False)
    )
    thread = Thread(target=lambda: server.run(sockets=[listener]), daemon=True)
    thread.start()
    try:
        deadline = monotonic() + 5
        while not server.started and monotonic() < deadline:
            sleep(0.01)
        assert server.started
        with httpx.Client(
            base_url=f"http://127.0.0.1:{listener.getsockname()[1]}", timeout=3
        ) as network:
            url = f"/api/v1/{case[1]}"
            with pytest.raises(httpx.ReadTimeout):
                network.post(
                    url,
                    headers=case[4],
                    data=case[3],
                    files={"photos": ("test.jpg", _jpeg_bytes(), "image/jpeg")},
                    timeout=0.05,
                )
            deadline = monotonic() + 5
            while monotonic() < deadline:
                status = network.get(
                    f"/api/v1/publication-operations/{case[4]['Idempotency-Key']}", headers=case[4]
                )
                if status.status_code == 200 and status.json()["data"]["state"] == "completed":
                    break
                sleep(0.03)
            replay = network.post(
                url,
                headers=case[4],
                data=case[3],
                files={"photos": ("test.jpg", _jpeg_bytes(), "image/jpeg")},
            )
            assert replay.status_code == 201
            assert replay.json()["data"]["id"] == status.json()["data"]["target_id"]
            assert len(posts_runtime.fake_storage.objects) == 2
    finally:
        server.should_exit = True
        thread.join(timeout=5)
        listener.close()
        assert not thread.is_alive()
# ruff: noqa: F811
