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
    LostPetFollowUpRecord,
    LostPetMapMarker,
    LostPetMapPage,
    LostPetPage,
    LostPetPhotoRecord,
    LostPetRecord,
    LostPetUpdateDraft,
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

    def get_by_id(
        self,
        lost_pet_id: UUID,
        *,
        for_update: bool = False,
        include_deleted: bool = False,
    ) -> LostPetRecord | None:
        statement = (
            select(schema.LostPet)
            .options(selectinload(schema.LostPet.photos), selectinload(schema.LostPet.author))
            .where(
                schema.LostPet.id == lost_pet_id,
                schema.LostPet.is_public.is_(True),
            )
        )
        if not include_deleted:
            statement = statement.where(schema.LostPet.deleted_at.is_(None))
        statement = statement.execution_options(populate_existing=True)
        if for_update:
            statement = statement.with_for_update()
        item = self.session.scalar(statement)
        return self._model_to_record(item) if item is not None else None

    def update(self, lost_pet_id: UUID, draft: LostPetUpdateDraft) -> LostPetRecord:
        item = self.session.get(schema.LostPet, lost_pet_id)
        if item is None:
            raise RuntimeError("Locked lost pet could not be loaded for update.")
        item.pet_name = draft.pet_name
        item.owner_phone_number = draft.owner_phone_number
        item.owner_telegram_username = draft.owner_telegram_username
        item.last_seen_location = WKTElement(
            f"POINT({draft.last_seen_longitude} {draft.last_seen_latitude})", srid=4326
        )
        item.additional_info = draft.additional_info
        item.updated_at = draft.updated_at
        if draft.photos is not None:
            item.photos = [
                schema.LostPetPhoto(
                    id=photo.id,
                    photo_url=photo.photo_url,
                    thumb_url=photo.thumb_url,
                    position=photo.position,
                )
                for photo in draft.photos
            ]
        self.session.flush()
        return self._model_to_record(item)

    def soft_delete(self, lost_pet_id: UUID, deleted_at: datetime) -> None:
        item = self.session.get(schema.LostPet, lost_pet_id)
        if item is None:
            raise RuntimeError("Locked lost pet could not be loaded for deletion.")
        item.deleted_at = deleted_at
        item.updated_at = deleted_at
        pending = self.session.scalar(
            select(schema.LostPetFollowUp)
            .where(
                schema.LostPetFollowUp.lost_pet_id == lost_pet_id,
                schema.LostPetFollowUp.completed_at.is_(None),
            )
            .with_for_update()
        )
        if pending is not None:
            self.session.delete(pending)
        self.session.flush()

    def set_resolution(
        self, lost_pet_id: UUID, *, is_resolved: bool, changed_at: datetime
    ) -> LostPetRecord:
        item = self.session.get(schema.LostPet, lost_pet_id)
        if item is None:
            raise RuntimeError("Locked lost pet could not be loaded for resolution.")
        if item.is_resolved != is_resolved:
            item.is_resolved = is_resolved
            item.updated_at = changed_at
        if is_resolved:
            pending = self.session.scalar(
                select(schema.LostPetFollowUp)
                .where(
                    schema.LostPetFollowUp.lost_pet_id == lost_pet_id,
                    schema.LostPetFollowUp.completed_at.is_(None),
                )
                .with_for_update()
            )
            if pending is not None:
                self.session.delete(pending)
        self.session.flush()
        result = self.get_by_id(lost_pet_id)
        if result is None:
            raise RuntimeError("Resolved lost pet could not be loaded.")
        return result

    def get_by_ids(
        self, lost_pet_ids: list[UUID], *, active_only: bool = False
    ) -> list[LostPetRecord]:
        if not lost_pet_ids:
            return []
        statement = (
            select(schema.LostPet)
            .options(selectinload(schema.LostPet.photos), selectinload(schema.LostPet.author))
            .where(
                schema.LostPet.id.in_(lost_pet_ids),
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
            )
        )
        if active_only:
            statement = statement.where(schema.LostPet.is_resolved.is_(False))
        items = self.session.scalars(statement).all()
        return [self._model_to_record(item) for item in items]

    def record_contact(self, lost_pet_id: UUID, contacting_user_id: UUID) -> bool:
        pet = self.session.scalar(
            select(schema.LostPet).where(schema.LostPet.id == lost_pet_id).with_for_update()
        )
        if (
            pet is None
            or pet.deleted_at is not None
            or not pet.is_public
            or pet.is_resolved
            or pet.user_id is None
        ):
            return False
        if pet.user_id == contacting_user_id:
            raise PermissionError("Owners cannot contact themselves through this flow.")
        now = datetime.now(UTC)
        self.session.add(
            schema.LostPetContactEvent(
                lost_pet_id=pet.id,
                owner_id=pet.user_id,
                contacting_user_id=contacting_user_id,
                created_at=now,
            )
        )
        pending = self.session.scalar(
            select(schema.LostPetFollowUp).where(
                schema.LostPetFollowUp.lost_pet_id == pet.id,
                schema.LostPetFollowUp.completed_at.is_(None),
            )
        )
        if pending is None:
            self.session.add(
                schema.LostPetFollowUp(
                    lost_pet_id=pet.id,
                    owner_id=pet.user_id,
                    due_at=now + timedelta(hours=1),
                    created_at=now,
                )
            )
        self.session.flush()
        return True

    def list_due_follow_ups(self, owner_id: UUID, now: datetime) -> list[LostPetFollowUpRecord]:
        rows = self.session.execute(
            select(schema.LostPetFollowUp, schema.LostPet.pet_name)
            .join(schema.LostPet, schema.LostPetFollowUp.lost_pet_id == schema.LostPet.id)
            .where(
                schema.LostPetFollowUp.owner_id == owner_id,
                schema.LostPetFollowUp.completed_at.is_(None),
                schema.LostPetFollowUp.due_at <= now,
                schema.LostPet.user_id == owner_id,
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
                schema.LostPet.is_resolved.is_(False),
            )
            .order_by(schema.LostPetFollowUp.due_at.asc())
        ).all()
        return [
            LostPetFollowUpRecord(
                id=follow_up.id,
                lost_pet_id=follow_up.lost_pet_id,
                pet_name=pet_name,
                due_at=follow_up.due_at,
            )
            for follow_up, pet_name in rows
        ]

    def answer_follow_up(
        self, follow_up_id: UUID, owner_id: UUID, answer_yes: bool, now: datetime
    ) -> tuple[str, UUID | None]:
        follow_up = self.session.get(schema.LostPetFollowUp, follow_up_id)
        if follow_up is None:
            return "not_found", None
        pet = self.session.scalar(
            select(schema.LostPet)
            .where(schema.LostPet.id == follow_up.lost_pet_id)
            .with_for_update()
        )
        follow_up = self.session.scalar(
            select(schema.LostPetFollowUp)
            .where(schema.LostPetFollowUp.id == follow_up_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if follow_up is None or pet is None:
            return "not_found", None
        if follow_up.owner_id != owner_id or pet.user_id != owner_id:
            return "forbidden", None
        if follow_up.completed_at is not None:
            return "completed", None
        if follow_up.due_at > now:
            return "not_due", None
        if pet.deleted_at is not None or not pet.is_public or pet.is_resolved:
            return "unavailable", None
        follow_up.completed_at = now
        follow_up.answer_yes = answer_yes
        if answer_yes:
            pet.is_resolved = True
            pet.updated_at = now
        self.session.flush()
        return "answered", pet.id

    def list_owned(self, owner_id: UUID, *, limit: int, cursor: str | None = None) -> LostPetPage:
        statement = (
            select(schema.LostPet)
            .options(selectinload(schema.LostPet.photos), selectinload(schema.LostPet.author))
            .where(
                schema.LostPet.user_id == owner_id,
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
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
        rows = self.session.scalars(
            statement.order_by(schema.LostPet.created_at.desc(), schema.LostPet.id.desc()).limit(
                limit + 1
            )
        ).all()
        return LostPetPage(
            items=[self._model_to_record(row) for row in rows[:limit]],
            next_cursor=self._encode_cursor(rows[limit - 1]) if len(rows) > limit else None,
            limit=limit,
        )

    def list_public(
        self,
        *,
        limit: int,
        cursor: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        valid_for_map: bool = False,
        bbox: tuple[float, float, float, float] | None = None,
    ) -> LostPetPage:
        statement = (
            select(schema.LostPet)
            .options(selectinload(schema.LostPet.photos), selectinload(schema.LostPet.author))
            .where(
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
                schema.LostPet.is_resolved.is_(False),
            )
        )
        if valid_for_map:
            statement = statement.where(
                schema.LostPet.is_resolved.is_(False),
                schema.LostPet.created_at >= datetime.now(UTC) - timedelta(days=30),
            )

        if bbox is not None:
            min_lon, min_lat, max_lon, max_lat = bbox
            envelope = func.ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
            statement = statement.where(schema.LostPet.last_seen_location.op("&&")(envelope))

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

    def list_map_markers(
        self,
        *,
        limit: int,
        bbox: tuple[float, float, float, float],
    ) -> LostPetMapPage:
        min_lon, min_lat, max_lon, max_lat = bbox
        envelope = func.ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
        statement = (
            select(
                schema.LostPet.id,
                schema.LostPet.pet_name,
                func.ST_Y(schema.LostPet.last_seen_location).label("latitude"),
                func.ST_X(schema.LostPet.last_seen_location).label("longitude"),
                schema.LostPet.is_resolved,
                schema.LostPet.created_at,
            )
            .where(
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
                schema.LostPet.is_resolved.is_(False),
                schema.LostPet.created_at >= datetime.now(UTC) - timedelta(days=30),
                schema.LostPet.last_seen_location.op("&&")(envelope),
            )
            .order_by(schema.LostPet.created_at.desc(), schema.LostPet.id.desc())
            .limit(limit)
        )
        rows = self.session.execute(statement).mappings().all()
        return LostPetMapPage(
            items=[
                LostPetMapMarker(
                    id=row["id"],
                    pet_name=row["pet_name"],
                    last_seen_location=GeoPoint(
                        latitude=float(row["latitude"]),
                        longitude=float(row["longitude"]),
                    ),
                    is_resolved=bool(row["is_resolved"]),
                    created_at=row["created_at"],
                )
                for row in rows
            ],
            limit=limit,
        )

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
