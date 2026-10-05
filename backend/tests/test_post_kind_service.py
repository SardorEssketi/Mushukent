from __future__ import annotations

from contextlib import nullcontext
from dataclasses import replace
from datetime import UTC, datetime
from unittest.mock import Mock
from uuid import uuid4

import pytest
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient

from app.api.v1.routes.posts import router as posts_router
from app.core.dependencies import get_current_active_user, get_posts_service
from app.features.auth.domain.models import AuthUser
from app.features.cats.domain.models import CatStatus, GeoPoint
from app.features.posts.application.schemas import PostUpdateJSONRequest
from app.features.posts.application.service import PostsService
from app.features.posts.domain.models import PostCatSummary, PostDetailRecord
from app.infrastructure.db.enums import PostKind


def _post(user: AuthUser, *, kind: PostKind, description: str | None) -> PostDetailRecord:
    cat = PostCatSummary(
        id=uuid4(),
        name=None,
        cover_photo_url=None,
        status=CatStatus.UNKNOWN,
        is_active=True,
        merged_into=None,
        deleted_at=None,
    )
    now = datetime.now(UTC)
    return PostDetailRecord(
        id=uuid4(),
        cat_id=cat.id,
        user_id=user.id,
        photo_url="https://storage.example/cat.jpg",
        thumb_url=None,
        photo_urls=["https://storage.example/cat.jpg"],
        description=description,
        kind=kind,
        location=GeoPoint(latitude=41.31, longitude=69.28),
        status=CatStatus.UNKNOWN,
        is_public=True,
        like_count=0,
        comment_count=0,
        created_at=now,
        updated_at=now,
        deleted_at=None,
        author=None,
        cat=cat,
    )


def _service(current: PostDetailRecord) -> tuple[PostsService, Mock]:
    repository = Mock()
    repository.get_by_id.return_value = current
    session_manager = Mock()
    session_manager.session_scope.return_value = nullcontext(None)
    service = PostsService(
        db_session_manager=session_manager,
        post_repository_factory=lambda _session: repository,
        cat_repository_factory=lambda _session: None,
        user_repository_factory=lambda _session: None,
    )
    return service, repository


@pytest.mark.parametrize(
    ("kind", "description", "changes"),
    [
        (PostKind.NEEDS_HELP, "Existing details", {"description": None}),
        (PostKind.NEEDS_HELP, "Existing details", {"description": ""}),
        (PostKind.NEEDS_HELP, "Existing details", {"description": " \t "}),
        (PostKind.NEEDS_HELP, " \t ", {}),
        (PostKind.OBSERVATION, None, {"kind": "needs_help"}),
        (PostKind.OBSERVATION, " \t ", {"kind": "needs_help"}),
    ],
)
def test_needs_help_update_rejects_blank_result(kind, description, changes) -> None:
    user = AuthUser(id=uuid4(), email="author@example.com", password_hash=None)
    current = _post(user, kind=kind, description=description)
    service, repository = _service(current)

    with pytest.raises(HTTPException) as error:
        service.update_post(current.id, user, PostUpdateJSONRequest.model_validate(changes))

    assert error.value.status_code == 422
    assert error.value.detail["error"]["details"] == {"description": ["required_for_needs_help"]}
    repository.update.assert_not_called()
    repository.add_history.assert_not_called()


def test_update_api_rejects_blank_needs_help_details() -> None:
    user = AuthUser(id=uuid4(), email="author@example.com", password_hash=None)
    current = _post(user, kind=PostKind.NEEDS_HELP, description="Existing details")
    service, repository = _service(current)
    app = FastAPI()
    app.include_router(posts_router, prefix="/api/v1")
    app.dependency_overrides[get_current_active_user] = lambda: user
    app.dependency_overrides[get_posts_service] = lambda: service

    with TestClient(app) as client:
        response = client.patch(f"/api/v1/posts/{current.id}", json={"description": " \t "})

    assert response.status_code == 422
    assert response.json()["detail"]["error"]["details"] == {
        "description": ["required_for_needs_help"]
    }
    repository.update.assert_not_called()


@pytest.mark.parametrize(
    ("kind", "description", "changes", "result_kind", "result_description"),
    [
        (
            PostKind.NEEDS_HELP,
            "Old details",
            {"description": "  New details  "},
            PostKind.NEEDS_HELP,
            "New details",
        ),
        (
            PostKind.OBSERVATION,
            "Existing details",
            {"kind": "needs_help"},
            PostKind.NEEDS_HELP,
            "Existing details",
        ),
        (
            PostKind.OBSERVATION,
            "Existing note",
            {"description": " \t "},
            PostKind.OBSERVATION,
            None,
        ),
    ],
)
def test_update_preserves_valid_help_and_optional_observation_details(
    kind, description, changes, result_kind, result_description
) -> None:
    user = AuthUser(id=uuid4(), email="author@example.com", password_hash=None)
    current = _post(user, kind=kind, description=description)
    updated = replace(current, kind=result_kind, description=result_description)
    service, repository = _service(current)
    repository.get_by_id.side_effect = [current, updated]
    repository.update.return_value = updated

    response = service.update_post(current.id, user, PostUpdateJSONRequest.model_validate(changes))

    assert response.kind == result_kind
    assert response.description == result_description
    assert repository.update.call_args.args[1].description == result_description
