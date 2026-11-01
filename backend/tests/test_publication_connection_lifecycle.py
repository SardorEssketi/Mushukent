from concurrent.futures import ThreadPoolExecutor
from threading import Event, Lock
from time import monotonic, sleep

from sqlalchemy import event
from test_posts import _create_user_with_token, _jpeg_bytes, client, posts_runtime  # noqa: F401


def test_queued_uploads_release_authentication_connections(client, posts_runtime, monkeypatch):
    _, token = _create_user_with_token(
        posts_runtime.db_session_manager, posts_runtime.token_service, email="pool@example.test"
    )
    release, lock = Event(), Lock()
    original = type(posts_runtime.fake_storage).upload
    auth_queries = 0
    engine = posts_runtime.db_session_manager.engine

    def observe(_conn, _cursor, statement, _parameters, _context, _executemany):
        nonlocal auth_queries
        if "FROM users" in statement:
            with lock:
                auth_queries += 1

    def delayed(storage, **kwargs):
        assert release.wait(10)
        return original(storage, **kwargs)

    event.listen(engine, "after_cursor_execute", observe)
    monkeypatch.setattr(type(posts_runtime.fake_storage), "upload", delayed)

    def publish():
        return client.post(
            "/api/v1/posts",
            headers={"Authorization": f"Bearer {token}"},
            files={"photos": ("test.jpg", _jpeg_bytes(), "image/jpeg")},
        )

    try:
        with ThreadPoolExecutor(max_workers=15) as pool:
            tasks = [pool.submit(publish) for _ in range(15)]
            try:
                deadline = monotonic() + 8
                while auth_queries < 15 and monotonic() < deadline:
                    sleep(0.01)
                assert auth_queries == 15
                sleep(0.05)
                assert engine.pool.checkedout() == 0
            finally:
                release.set()
            assert all(task.result().status_code == 201 for task in tasks)
    finally:
        event.remove(engine, "after_cursor_execute", observe)
# ruff: noqa: F811
