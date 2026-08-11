from __future__ import annotations

import base64
import json
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from geoalchemy2 import Geography
from geoalchemy2.elements import WKTElement
from sqlalchemy import and_, cast, func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.features.cats.domain.models import GeoPoint
from app.features.lost_pets.domain.models import (
    LostPetCreateDraft,
    LostPetPage,
    LostPetPhotoRecord,
    LostPetRecord,
)
from app.features.posts.domain.models import PostAuthorSummary
from app.infrastructure.db.models import schema


class SqlAlchemyLostPetRepository:
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, draft: LostPetCreateDraft) -> LostPetRecord:
        lost_pet = schema.LostPet(
            id=draft.id,
            user_id=draft.user_id,
            pet_name=draft.pet_name,
            owner_phone_number=draft.owner_phone_number,
            owner_telegram_username=draft.owner_telegram_username,
            owner_phone_publication_consent=draft.owner_phone_publication_consent,
            last_seen_location=WKTElement(
                f"POINT({draft.last_seen_longitude} {draft.last_seen_latitude})",
                srid=4326,
            ),
            additional_info=draft.additional_info,
            is_resolved=False,
            is_public=True,
        )
        lost_pet.photos = [
            schema.LostPetPhoto(
                id=photo.id,
                photo_url=photo.photo_url,
                thumb_url=photo.thumb_url,
                position=photo.position,
            )
            for photo in draft.photos
        ]
        self.session.add(lost_pet)
        self.session.flush()
        created = self.get_by_id(lost_pet.id)
        if created is None:
            raise RuntimeError("Created lost pet could not be loaded.")
        return created

    def get_by_id(self, lost_pet_id: UUID) -> LostPetRecord | None:
        item = self.session.scalar(
            select(schema.LostPet)
            .options(selectinload(schema.LostPet.photos), selectinload(schema.LostPet.author))
            .where(
                schema.LostPet.id == lost_pet_id,
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
            )
        )
        return self._model_to_record(item) if item is not None else None

    def list_public(
        self,
        *,
        limit: int,
        cursor: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        valid_for_map: bool = False,
    ) -> LostPetPage:
        statement = (
            select(schema.LostPet)
            .options(selectinload(schema.LostPet.photos), selectinload(schema.LostPet.author))
            .where(
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
            )
        )
        if valid_for_map:
            statement = statement.where(
                schema.LostPet.is_resolved.is_(False),
                schema.LostPet.created_at >= datetime.now(UTC) - timedelta(days=30),
            )

        distance_expr = None
        if latitude is not None or longitude is not None or radius_meters is not None:
            if latitude is None or longitude is None or radius_meters is None:
                raise ValueError("Nearby lost pets require latitude, longitude and radius_meters.")
            reference_geom = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
            distance_expr = func.ST_Distance(
                cast(schema.LostPet.last_seen_location, Geography),
                cast(reference_geom, Geography),
            )
            statement = statement.where(
                func.ST_DWithin(
                    cast(schema.LostPet.last_seen_location, Geography),
                    cast(reference_geom, Geography),
                    radius_meters,
                )
            )

        if cursor is not None:
            cursor_created_at, cursor_id = self._decode_cursor(cursor)
            statement = statement.where(
                or_(
                    schema.LostPet.created_at < cursor_created_at,
                    and_(
                        schema.LostPet.created_at == cursor_created_at,
                        schema.LostPet.id < cursor_id,
                    ),
                )
            )

        if distance_expr is not None:
            statement = statement.order_by(
                distance_expr.asc(),
                schema.LostPet.created_at.desc(),
                schema.LostPet.id.desc(),
            )
        else:
            statement = statement.order_by(
                schema.LostPet.created_at.desc(), schema.LostPet.id.desc()
            )

        rows = self.session.scalars(statement.limit(limit + 1)).all()
        items = [self._model_to_record(row) for row in rows[:limit]]
        next_cursor = self._encode_cursor(rows[limit - 1]) if len(rows) > limit else None
        return LostPetPage(items=items, next_cursor=next_cursor, limit=limit)

    def _model_to_record(self, item: schema.LostPet) -> LostPetRecord:
        photos = sorted(item.photos, key=lambda photo: photo.position)
        photo_records = [
            LostPetPhotoRecord(
                id=photo.id,
                photo_url=photo.photo_url,
                thumb_url=photo.thumb_url,
                position=photo.position,
            )
            for photo in photos
        ]
        primary_photo = photo_records[0]
        author = item.author
        return LostPetRecord(
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
            last_seen_location=GeoPoint(
                latitude=float(item.last_seen_latitude),
                longitude=float(item.last_seen_longitude),
            ),
            additional_info=item.additional_info,
            is_resolved=item.is_resolved,
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

    def _encode_cursor(self, item: schema.LostPet) -> str:
        payload: dict[str, Any] = {
            "created_at": item.created_at.astimezone(UTC).isoformat().replace("+00:00", "Z"),
            "id": str(item.id),
        }
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("utf-8")
