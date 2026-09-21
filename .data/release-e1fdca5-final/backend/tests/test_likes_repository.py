from __future__ import annotations

from datetime import UTC, datetime
from uuid import uuid4

from app.features.likes.infrastructure.repositories import SqlAlchemyLikeRepository


def test_like_repository_maps_locationless_post() -> None:
    post_id = uuid4()
    cat_id = uuid4()
    user_id = uuid4()
    created_at = datetime.now(UTC)
    row = {
        "post_id": post_id,
        "post_cat_id": cat_id,
        "post_user_id": user_id,
        "photo_url": "https://example.com/post.jpg",
        "thumb_url": None,
        "description": "Locationless observation",
        "post_status": "unknown",
        "is_public": True,
        "like_count": 0,
        "comment_count": 0,
        "created_at": created_at,
        "updated_at": created_at,
        "deleted_at": None,
        "latitude": None,
        "longitude": None,
        "cat_id": cat_id,
        "cat_name": "Mittens",
        "cat_cover_photo_url": None,
        "cat_status": "unknown",
        "cat_is_active": True,
        "cat_merged_into": None,
        "cat_deleted_at": None,
        "author_id": user_id,
        "author_name": "Owner",
        "author_avatar_url": None,
    }

    record = SqlAlchemyLikeRepository(session=None)._row_to_post_detail(row)  # type: ignore[arg-type]

    assert record.id == post_id
    assert record.location is None
