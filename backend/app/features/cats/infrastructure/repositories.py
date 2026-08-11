from __future__ import annotations

import base64
import json
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from geoalchemy2 import Geography
from geoalchemy2.elements import WKTElement
from sqlalchemy import and_, cast, func, or_, select
from sqlalchemy.orm import Session

from app.features.cats.domain.models import (
    CatDetailRecord,
    CatListFilter,
    CatRecord,
    CatStatus,
    CatSummary,
    GeoPoint,
    ObservationAuthor,
    ObservationSortOrder,
    PostListItem,
)
from app.features.cats.domain.repositories import CatListPage, CatRepository, PostListPage
from app.infrastructure.db.models import schema


def _point_to_wkt(point: GeoPoint | None) -> WKTElement | None:
    if point is None:
        return None
    return WKTElement(f"POINT({point.longitude} {point.latitude})", srid=4326)


def _geometry_to_point(longitude: float | None, latitude: float | None) -> GeoPoint | None:
    if latitude is None or longitude is None:
        return None
    return GeoPoint(latitude=latitude, longitude=longitude)


def _encode_cursor(payload: dict[str, Any]) -> str:
    data = json.dumps(payload, separators=(",", ":"), sort_keys=True).encode("utf-8")
    return base64.urlsafe_b64encode(data).decode("ascii")


def _decode_cursor(cursor: str | None) -> dict[str, Any] | None:
    if cursor is None:
        return None
    try:
        raw = base64.urlsafe_b64decode(cursor.encode("ascii"))
        payload = json.loads(raw.decode("utf-8"))
    except Exception as exc:  # pragma: no cover - invalid cursors handled by callers
        raise ValueError("Invalid cursor.") from exc
    if not isinstance(payload, dict):
        raise ValueError("Invalid cursor.")
    return payload


class SqlAlchemyCatRepository(CatRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, *, cat: CatRecord) -> CatRecord:
        model = schema.Cat(
            id=cat.id,
            name=cat.name,
            status=schema.CatStatus(cat.status.value),
            approximate_age_smallyears=cat.approximate_age_smallyears,
            created_by=cat.created_by,
            first_seen_at=cat.first_seen_at,
            last_seen_at=cat.last_seen_at,
            cover_photo_url=cat.cover_photo_url,
            canonical_location=_point_to_wkt(cat.canonical_location),
            total_observations=cat.total_observations,
            total_contributors=cat.total_contributors,
            total_likes=cat.total_likes,
            is_active=cat.is_active,
            merged_into=cat.merged_into,
            deleted_at=cat.deleted_at,
        )
        self.session.add(model)
        self.session.flush()
        return self.get_by_id(model.id) or cat

    def save(self, cat: CatRecord) -> CatRecord:
        model = self.session.get(schema.Cat, cat.id)
        if model is None:
            raise ValueError(f"Cat {cat.id} no longer exists.")
        model.name = cat.name
        model.status = schema.CatStatus(cat.status.value)
        model.approximate_age_smallyears = cat.approximate_age_smallyears
        model.cover_photo_url = cat.cover_photo_url
        model.canonical_location = _point_to_wkt(cat.canonical_location)
        model.first_seen_at = cat.first_seen_at
        model.last_seen_at = cat.last_seen_at
        model.total_observations = cat.total_observations
        model.total_contributors = cat.total_contributors
        model.total_likes = cat.total_likes
        model.is_active = cat.is_active
        model.merged_into = cat.merged_into
        model.deleted_at = cat.deleted_at
        self.session.flush()
        return self.get_by_id(model.id) or cat

    def get_by_id(self, cat_id: UUID) -> CatRecord | None:
        statement = self._record_select_statement().where(schema.Cat.id == cat_id)
        row = self.session.execute(statement).one_or_none()
        return self._to_record_row(row) if row is not None else None

    def get_detail(self, cat_id: UUID) -> CatDetailRecord | None:
        cat = self.get_by_id(cat_id)
        if cat is None:
            return None

        history = self.list_history(cat_id=cat_id, limit=20).items
        (
            first_seen_at,
            last_seen_at,
            total_observations,
            total_contributors,
            total_likes,
        ) = self._aggregate_cat_stats(cat_id)
        return CatDetailRecord(
            id=cat.id,
            name=cat.name,
            status=cat.status,
            approximate_age_smallyears=cat.approximate_age_smallyears,
            cover_photo_url=cat.cover_photo_url,
            canonical_location=cat.canonical_location,
            first_seen_at=first_seen_at,
            last_seen_at=last_seen_at,
            total_observations=total_observations,
            total_contributors=total_contributors,
            total_likes=total_likes,
            created_at=cat.created_at,
            updated_at=cat.updated_at,
            created_by=cat.created_by,
            is_active=cat.is_active,
            merged_into=cat.merged_into,
            deleted_at=cat.deleted_at,
            observation_history=history,
        )

    def list_cats(
        self,
        *,
        filter_by: CatListFilter,
        limit: int,
        cursor: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        bbox: tuple[float, float, float, float] | None = None,
    ) -> CatListPage:
        statement = select(
            schema.Cat.id,
            schema.Cat.name,
            schema.Cat.status,
            schema.Cat.cover_photo_url,
            func.ST_X(schema.Cat.canonical_location).label("longitude"),
            func.ST_Y(schema.Cat.canonical_location).label("latitude"),
            schema.Cat.last_seen_at,
            schema.Cat.total_observations,
            schema.Cat.created_at,
        ).where(
            schema.Cat.deleted_at.is_(None),
            schema.Cat.is_active.is_(True),
            schema.Cat.merged_into.is_(None),
        )

        cursor_payload = _decode_cursor(cursor)
        map_recent_cutoff = datetime.now(UTC) - timedelta(days=10)
        recent_public_post_exists = select(1).where(
            schema.Post.cat_id == schema.Cat.id,
            schema.Post.deleted_at.is_(None),
            schema.Post.is_public.is_(True),
            schema.Post.created_at >= map_recent_cutoff,
        )

        if filter_by == CatListFilter.NEARBY:
            if latitude is None or longitude is None or radius_meters is None:
                raise ValueError("Nearby filter requires latitude, longitude and radius_meters.")
            statement = statement.where(schema.Cat.canonical_location.is_not(None))
            statement = statement.where(recent_public_post_exists.exists())
            reference_geom = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
            statement = statement.where(
                schema.Cat.canonical_location.op("&&")(
                    func.ST_Expand(reference_geom, radius_meters / 111_320.0)
                )
            )
            statement = statement.where(
                func.ST_DWithin(
                    cast(schema.Cat.canonical_location, Geography),
                    cast(reference_geom, Geography),
                    radius_meters,
                )
            )
            distance_expr = func.ST_Distance(
                cast(schema.Cat.canonical_location, Geography),
                cast(reference_geom, Geography),
            )
            statement = statement.add_columns(distance_expr.label("distance_meters"))
            statement = statement.order_by(distance_expr.asc(), schema.Cat.id.asc())
            if cursor_payload is not None:
                statement = statement.where(
                    or_(
                        distance_expr > float(cursor_payload["distance_meters"]),
                        and_(
                            distance_expr == float(cursor_payload["distance_meters"]),
                            schema.Cat.id > UUID(cursor_payload["id"]),
                        ),
                    )
                )
        elif bbox is not None:
            min_lon, min_lat, max_lon, max_lat = bbox
            envelope = func.ST_MakeEnvelope(min_lon, min_lat, max_lon, max_lat, 4326)
            statement = statement.where(schema.Cat.canonical_location.is_not(None))
            statement = statement.where(recent_public_post_exists.exists())
            statement = statement.where(schema.Cat.canonical_location.op("&&")(envelope))
            bbox_sort_key: Any = func.coalesce(schema.Cat.last_seen_at, schema.Cat.created_at)
            statement = statement.order_by(bbox_sort_key.desc(), schema.Cat.id.asc())
            if cursor_payload is not None:
                cursor_ts = datetime.fromisoformat(cursor_payload["sort_value"])
                statement = statement.where(
                    or_(
                        bbox_sort_key < cursor_ts,
                        and_(
                            bbox_sort_key == cursor_ts,
                            schema.Cat.id < UUID(cursor_payload["id"]),
                        ),
                    )
                )
        else:
            if filter_by == CatListFilter.RECENTLY_SEEN:
                sort_key_expr: Any = func.coalesce(
                    schema.Cat.last_seen_at,
                    schema.Cat.created_at,
                )
                statement = statement.order_by(sort_key_expr.desc(), schema.Cat.id.asc())
            elif filter_by == CatListFilter.NEEDS_HELP:
                statement = statement.where(schema.Cat.status == schema.CatStatus.NEEDS_HELP)
                sort_key_expr = func.coalesce(schema.Cat.last_seen_at, schema.Cat.created_at)
                statement = statement.order_by(sort_key_expr.desc(), schema.Cat.id.asc())
            else:
                sort_key_expr = schema.Cat.created_at
                statement = statement.order_by(sort_key_expr.desc(), schema.Cat.id.asc())
            if cursor_payload is not None:
                cursor_ts = datetime.fromisoformat(cursor_payload["sort_value"])
                statement = statement.where(
                    or_(
                        sort_key_expr < cursor_ts,
                        and_(
                            sort_key_expr == cursor_ts,
                            schema.Cat.id < UUID(cursor_payload["id"]),
                        ),
                    )
                )

        rows = self.session.execute(statement.limit(limit + 1)).all()
        has_next_page = len(rows) > limit
        rows = rows[:limit]
        items = [self._to_summary_row(row) for row in rows]
        next_cursor = self._build_next_cursor(items[-1], filter_by) if has_next_page else None
        return CatListPage(items=items, next_cursor=next_cursor, limit=limit)

    def list_history(
        self,
        *,
        cat_id: UUID,
        limit: int,
        cursor: str | None = None,
        order: ObservationSortOrder = ObservationSortOrder.LATEST,
    ) -> PostListPage:
        cursor_payload = _decode_cursor(cursor)
        sort_key = schema.Post.created_at
        statement = (
            select(
                schema.Post.id,
                schema.Post.cat_id,
                schema.Post.photo_url,
                schema.Post.thumb_url,
                schema.Post.description,
                schema.Post.created_at,
                schema.Post.like_count,
                schema.Post.comment_count,
                func.ST_X(schema.Post.location).label("longitude"),
                func.ST_Y(schema.Post.location).label("latitude"),
                schema.Cat.id.label("cat_id_summary"),
                schema.Cat.name.label("cat_name"),
                schema.Cat.status.label("cat_status"),
                schema.Cat.cover_photo_url.label("cat_cover_photo_url"),
                func.ST_X(schema.Cat.canonical_location).label("cat_longitude"),
                func.ST_Y(schema.Cat.canonical_location).label("cat_latitude"),
                schema.Cat.last_seen_at.label("cat_last_seen_at"),
                schema.Cat.total_observations.label("cat_total_observations"),
                schema.User.id.label("author_id"),
                schema.User.name.label("author_name"),
                schema.User.avatar_url.label("author_avatar_url"),
            )
            .join(schema.Cat, schema.Cat.id == schema.Post.cat_id)
            .outerjoin(schema.User, schema.User.id == schema.Post.user_id)
            .where(
                schema.Post.cat_id == cat_id,
                schema.Post.deleted_at.is_(None),
                schema.Cat.deleted_at.is_(None),
                schema.Cat.is_active.is_(True),
                schema.Cat.merged_into.is_(None),
                schema.Post.is_public.is_(True),
            )
        )

        if order == ObservationSortOrder.LATEST:
            statement = statement.order_by(sort_key.desc(), schema.Post.id.desc())
        else:
            statement = statement.order_by(sort_key.asc(), schema.Post.id.asc())

        if cursor_payload is not None:
            cursor_ts = datetime.fromisoformat(cursor_payload["sort_value"])
            if order == ObservationSortOrder.LATEST:
                statement = statement.where(
                    or_(
                        sort_key < cursor_ts,
                        and_(sort_key == cursor_ts, schema.Post.id < UUID(cursor_payload["id"])),
                    )
                )
            else:
                statement = statement.where(
                    or_(
                        sort_key > cursor_ts,
                        and_(sort_key == cursor_ts, schema.Post.id > UUID(cursor_payload["id"])),
                    )
                )

        rows = self.session.execute(statement.limit(limit + 1)).all()
        has_next_page = len(rows) > limit
        rows = rows[:limit]
        items = [self._to_post_item(row) for row in rows]
        next_cursor = self._build_history_cursor(items[-1], order) if has_next_page else None
        return PostListPage(items=items, next_cursor=next_cursor, limit=limit)

    def _aggregate_cat_stats(
        self,
        cat_id: UUID,
    ) -> tuple[datetime | None, datetime | None, int, int, int]:
        statement = select(
            func.min(schema.Post.created_at),
            func.max(schema.Post.created_at),
            func.count(schema.Post.id),
            func.count(func.distinct(schema.Post.user_id)),
            func.coalesce(func.sum(schema.Post.like_count), 0),
        ).where(
            schema.Post.cat_id == cat_id,
            schema.Post.deleted_at.is_(None),
        )
        first_seen_at, last_seen_at, total_observations, total_contributors, total_likes = (
            self.session.execute(statement).one()
        )
        return (
            first_seen_at,
            last_seen_at,
            int(total_observations or 0),
            int(total_contributors or 0),
            int(total_likes or 0),
        )

    def _record_select_statement(self):
        return select(
            schema.Cat.id,
            schema.Cat.name,
            schema.Cat.status,
            schema.Cat.approximate_age_smallyears,
            schema.Cat.cover_photo_url,
            func.ST_X(schema.Cat.canonical_location).label("longitude"),
            func.ST_Y(schema.Cat.canonical_location).label("latitude"),
            schema.Cat.first_seen_at,
            schema.Cat.last_seen_at,
            schema.Cat.total_observations,
            schema.Cat.total_contributors,
            schema.Cat.total_likes,
            schema.Cat.created_at,
            schema.Cat.updated_at,
            schema.Cat.created_by,
            schema.Cat.is_active,
            schema.Cat.merged_into,
            schema.Cat.deleted_at,
        )

    def _to_record_row(self, row: Any) -> CatRecord:
        if row is None:
            raise ValueError("Cat row missing.")
        return CatRecord(
            id=row.id,
            name=row.name,
            status=CatStatus(row.status),
            approximate_age_smallyears=row.approximate_age_smallyears,
            cover_photo_url=row.cover_photo_url,
            canonical_location=_geometry_to_point(row.longitude, row.latitude),
            first_seen_at=row.first_seen_at,
            last_seen_at=row.last_seen_at,
            total_observations=int(row.total_observations or 0),
            total_contributors=int(row.total_contributors or 0),
            total_likes=int(row.total_likes or 0),
            created_at=row.created_at,
            updated_at=row.updated_at,
            created_by=row.created_by,
            is_active=row.is_active,
            merged_into=row.merged_into,
            deleted_at=row.deleted_at,
        )

    def _to_summary_row(self, row: Any) -> CatSummary:
        return CatSummary(
            id=row.id,
            name=row.name,
            status=CatStatus(row.status),
            cover_photo_url=row.cover_photo_url,
            canonical_location=_geometry_to_point(row.longitude, row.latitude),
            last_seen_at=row.last_seen_at,
            total_observations=int(row.total_observations or 0),
            distance_meters=getattr(row, "distance_meters", None),
            created_at=row.created_at,
        )

    def _to_post_item(self, row: Any) -> PostListItem:
        cat_summary = CatSummary(
            id=row.cat_id_summary,
            name=row.cat_name,
            status=CatStatus(row.cat_status),
            cover_photo_url=row.cat_cover_photo_url,
            canonical_location=_geometry_to_point(row.cat_longitude, row.cat_latitude),
            last_seen_at=row.cat_last_seen_at,
            total_observations=int(row.cat_total_observations or 0),
        )
        author = None
        if row.author_id is not None:
            author = ObservationAuthor(
                id=row.author_id,
                name=row.author_name,
                avatar_url=row.author_avatar_url,
            )
        return PostListItem(
            id=row.id,
            cat=cat_summary,
            author=author,
            photo_url=row.photo_url,
            thumb_url=row.thumb_url,
            description=row.description,
            location=(
                GeoPoint(latitude=float(row.latitude), longitude=float(row.longitude))
                if row.latitude is not None and row.longitude is not None
                else None
            ),
            created_at=row.created_at,
            like_count=int(row.like_count or 0),
            comment_count=int(row.comment_count or 0),
        )

    def _build_next_cursor(self, item: CatSummary, filter_by: CatListFilter) -> str:
        if filter_by == CatListFilter.NEARBY:
            return _encode_cursor(
                {
                    "distance_meters": item.distance_meters,
                    "id": str(item.id),
                }
            )
        if filter_by == CatListFilter.RECENTLY_ADDED:
            sort_value = item.created_at or item.last_seen_at or datetime.now(UTC)
        else:
            sort_value = item.last_seen_at or item.created_at or datetime.now(UTC)
        return _encode_cursor({"sort_value": sort_value.isoformat(), "id": str(item.id)})

    def _build_history_cursor(self, item: PostListItem, order: ObservationSortOrder) -> str:
        return _encode_cursor(
            {
                "sort_value": item.created_at.isoformat(),
                "id": str(item.id),
                "order": order.value,
            }
        )
