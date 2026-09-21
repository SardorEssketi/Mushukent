from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.features.posts.application.schemas import (
    PostCreateJSONRequest,
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
