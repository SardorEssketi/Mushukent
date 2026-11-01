from uuid import UUID, uuid4

from test_posts import _create_user_with_token, _jpeg_bytes, client, posts_runtime  # noqa: F401

from app.features.posts.infrastructure.repositories import SqlAlchemyPostRepository


def test_publication_error_has_correlation_without_private_exception_data(
    client, posts_runtime, monkeypatch, capsys
):
    _, token = _create_user_with_token(
        posts_runtime.db_session_manager,
        posts_runtime.token_service,
        email="diagnostic@example.test",
    )
    request_id = str(uuid4())
    private = "private-note-not-for-logs"

    def fail(*args, **kwargs):
        raise RuntimeError(private)

    monkeypatch.setattr(SqlAlchemyPostRepository, "recalculate_cat_stats", fail)
    response = client.post(
        "/api/v1/posts",
        data={"description": private},
        headers={"Authorization": f"Bearer {token}", "X-Request-ID": request_id},
        files={"photos": ("private-filename.jpg", _jpeg_bytes(), "image/jpeg")},
    )
    assert response.status_code == 500
    assert response.headers["X-Request-ID"] == request_id
    logs = capsys.readouterr().out
    assert request_id in logs
    assert private not in logs
    assert token not in logs
    assert "private-filename.jpg" not in logs


def test_invalid_request_id_is_replaced(client):
    response = client.post("/api/v1/posts", headers={"X-Request-ID": "arbitrary-client-text"})
    assert str(UUID(response.headers["X-Request-ID"])) == response.headers["X-Request-ID"]
# ruff: noqa: F811
