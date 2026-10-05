from __future__ import annotations

from unittest.mock import Mock
from uuid import uuid4

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError

from app.api.v1.routes.posts import router as posts_router
from app.core.dependencies import get_current_active_user, get_posts_service
from app.features.auth.domain.models import AuthUser
from app.features.posts.application.schemas import (
    PostCreateJSONRequest,
    PostCreateMultipartRequest,
    PostUpdateJSONRequest,
)
from app.features.posts.domain.models import post_history_snapshot_from_values
from app.infrastructure.db.enums import PostKind


def test_observation_kind_defaults_to_observation() -> None:
    payload = PostCreateJSONRequest.model_validate(
        {"photo_url": "https://storage.example/cat.jpg", "description": "Seen nearby"}
    )

    assert payload.kind == PostKind.OBSERVATION


def test_needs_help_kind_requires_location() -> None:
    with pytest.raises(ValidationError, match="Location is required"):
        PostCreateJSONRequest.model_validate(
            {
                "photo_url": "https://storage.example/cat.jpg",
                "kind": "needs_help",
            }
        )


@pytest.mark.parametrize(
    "request_model",
    [PostCreateJSONRequest, PostCreateMultipartRequest],
    ids=["json", "multipart"],
)
@pytest.mark.parametrize(
    "description_fields",
    [{}, {"description": ""}, {"description": " \t "}],
    ids=["missing", "empty", "whitespace"],
)
def test_needs_help_kind_requires_help_details(request_model, description_fields) -> None:
    base = {
        "photo_url": "https://storage.example/cat.jpg",
        "kind": "needs_help",
        "location": {"latitude": 41.31, "longitude": 69.28},
    }
    with pytest.raises(ValidationError, match="Help details are required"):
        request_model.model_validate({**base, **description_fields})


@pytest.mark.parametrize(
    "request_model",
    [PostCreateJSONRequest, PostCreateMultipartRequest],
    ids=["json", "multipart"],
)
def test_needs_help_kind_accepts_nonblank_help_details(request_model) -> None:
    payload = request_model.model_validate(
        {
            "photo_url": "https://storage.example/cat.jpg",
            "kind": "needs_help",
            "location": {"latitude": 41.31, "longitude": 69.28},
            "description": "  Injured paw  ",
        }
    )
    assert payload.description == "Injured paw"


@pytest.mark.parametrize(
    "description_fields",
    [{}, {"description": ""}, {"description": " \t "}],
    ids=["missing", "empty", "whitespace"],
)
def test_normal_post_allows_optional_location_and_note(description_fields) -> None:
    payload = PostCreateJSONRequest.model_validate(
        {"photo_url": "https://storage.example/cat.jpg", **description_fields}
    )
    assert payload.kind == PostKind.OBSERVATION
    assert payload.location is None
    assert payload.description == (None if not description_fields else "")


@pytest.mark.parametrize(
    "description_fields",
    [{}, {"description": ""}, {"description": " \t "}],
    ids=["missing", "empty", "whitespace"],
)
def test_create_api_rejects_needs_help_without_details(description_fields) -> None:
    app = FastAPI()
    app.include_router(posts_router, prefix="/api/v1")
    user = AuthUser(id=uuid4(), email="author@example.com", password_hash=None)
    service = Mock()
    app.dependency_overrides[get_current_active_user] = lambda: user
    app.dependency_overrides[get_posts_service] = lambda: service

    with TestClient(app) as client:
        response = client.post(
            "/api/v1/posts",
            json={
                "photo_url": "https://storage.example/cat.jpg",
                "kind": "needs_help",
                "location": {"latitude": 41.31, "longitude": 69.28},
                **description_fields,
            },
        )

    assert response.status_code == 422
    assert response.json()["detail"]["error"]["code"] == "VALIDATION_ERROR"
    service.create_post.assert_not_called()


def test_kind_is_constrained_and_tag_contract_is_rejected() -> None:
    with pytest.raises(ValidationError):
        PostCreateJSONRequest.model_validate(
            {
                "photo_url": "https://storage.example/cat.jpg",
                "kind": "urgent",
            }
        )
    with pytest.raises(ValidationError):
        PostCreateJSONRequest.model_validate(
            {
                "photo_url": "https://storage.example/cat.jpg",
                "tags": ["needs_help"],
            }
        )


def test_update_can_change_kind_and_history_snapshot_records_it() -> None:
    update = PostUpdateJSONRequest.model_validate({"kind": "needs_help"})
    snapshot = post_history_snapshot_from_values(
        description="Needs assistance",
        kind=update.kind.value,
        status=None,
        location_latitude=41.31,
        location_longitude=69.28,
        is_public=True,
        photo_urls=["https://storage.example/cat.jpg"],
    )

    assert update.kind == PostKind.NEEDS_HELP
    assert snapshot["kind"] == "needs_help"
