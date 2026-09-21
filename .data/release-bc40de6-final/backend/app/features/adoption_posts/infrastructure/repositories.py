from __future__ import annotations

import base64
import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session, selectinload

from app.features.adoption_posts.domain.models import (
    AdoptionPostCreateDraft,
    AdoptionPostPage,
    AdoptionPostPhotoRecord,
    AdoptionPostRecord,
)
from app.features.posts.domain.models import PostAuthorSummary
from app.infrastructure.db.models import schema


class SqlAlchemyAdoptionPostRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, draft: AdoptionPostCreateDraft) -> AdoptionPostRecord:
        adoption_post = schema.AdoptionPost(
            id=draft.id,
            user_id=draft.user_id,
            pet_name=draft.pet_name,
            owner_phone_number=draft.owner_phone_number,
            owner_telegram_username=draft.owner_telegram_username,
            owner_phone_publication_consent=draft.owner_phone_publication_consent,
            additional_info=draft.additional_info,
            is_public=True,
        )
        adoption_post.photos = [
            schema.AdoptionPostPhoto(
                id=photo.id,
                photo_url=photo.photo_url,
                thumb_url=photo.thumb_url,
                position=photo.position,
            )
            for photo in draft.photos
        ]
        self.session.add(adoption_post)
        self.session.flush()
        created = self.get_by_id(adoption_post.id)
        if created is None:
            raise RuntimeError("Created adoption post could not be loaded.")
        return created

    def get_by_id(self, adoption_post_id: UUID) -> AdoptionPostRecord | None:
        item = self.session.scalar(
            select(schema.AdoptionPost)
            .options(
                selectinload(schema.AdoptionPost.photos),
                selectinload(schema.AdoptionPost.author),
            )
            .where(
                schema.AdoptionPost.id == adoption_post_id,
                schema.AdoptionPost.deleted_at.is_(None),
                schema.AdoptionPost.is_public.is_(True),
            )
        )
        return self._model_to_record(item) if item is not None else None

    def list_public(
        self,
        *,
        limit: int,
        cursor: str | None = None,
    ) -> AdoptionPostPage:
        statement = (
            select(schema.AdoptionPost)
            .options(
                selectinload(schema.AdoptionPost.photos),
                selectinload(schema.AdoptionPost.author),
            )
            .where(
                schema.AdoptionPost.deleted_at.is_(None),
                schema.AdoptionPost.is_public.is_(True),
            )
        )

        if cursor is not None:
            cursor_created_at, cursor_id = self._decode_cursor(cursor)
            statement = statement.where(
                or_(
                    schema.AdoptionPost.created_at < cursor_created_at,
                    and_(
                        schema.AdoptionPost.created_at == cursor_created_at,
                        schema.AdoptionPost.id < cursor_id,
                    ),
                )
            )

        rows = self.session.scalars(
            statement.order_by(
                schema.AdoptionPost.created_at.desc(),
                schema.AdoptionPost.id.desc(),
            ).limit(limit + 1)
        ).all()
        items = [self._model_to_record(row) for row in rows[:limit]]
        next_cursor = self._encode_cursor(rows[limit - 1]) if len(rows) > limit else None
        return AdoptionPostPage(items=items, next_cursor=next_cursor, limit=limit)

    def _model_to_record(self, item: schema.AdoptionPost) -> AdoptionPostRecord:
        photos = sorted(item.photos, key=lambda photo: photo.position)
        photo_records = [
            AdoptionPostPhotoRecord(
                id=photo.id,
                photo_url=photo.photo_url,
                thumb_url=photo.thumb_url,
                position=photo.position,
            )
            for photo in photos
        ]
        primary_photo = photo_records[0]
        author = item.author
        return AdoptionPostRecord(
            id=item.id,
            user_id=item.user_id,
            pet_name=item.pet_name,
            owner_phone_number=item.owner_phone_number,
            owner_telegram_username=item.owner_telegram_username,
            owner_phone_publication_consent=item.owner_phone_publication_consent,
            photo_url=primary_photo.photo_url,
            thumb_url=primary_photo.thumb_url,
            photo_urls=[photo.photo_url for photo in photo_records],
            photos=photo_records,
            additional_info=item.additional_info,
            is_public=item.is_public,
            comment_count=int(item.comment_count or 0),
            created_at=item.created_at,
            updated_at=item.updated_at,
            deleted_at=item.deleted_at,
            author=(
                PostAuthorSummary(
                    id=author.id,
                    name=author.name,
                    avatar_url=author.avatar_url,
                )
                if author is not None
                else None
            ),
        )

    def _decode_cursor(self, cursor: str) -> tuple[datetime, UUID]:
        try:
            raw = base64.urlsafe_b64decode(cursor.encode("utf-8")).decode("utf-8")
            payload = json.loads(raw)
            created_at = datetime.fromisoformat(str(payload["created_at"]).replace("Z", "+00:00"))
            item_id = UUID(str(payload["id"]))
            return created_at, item_id
        except Exception as exc:  # pragma: no cover
            raise ValueError("Invalid cursor.") from exc

    def _encode_cursor(self, item: schema.AdoptionPost) -> str:
        payload: dict[str, Any] = {
            "created_at": item.created_at.astimezone(UTC).isoformat().replace("+00:00", "Z"),
            "id": str(item.id),
        }
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("utf-8")
