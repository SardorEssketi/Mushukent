from __future__ import annotations

import base64
import json
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from geoalchemy2 import Geography
from geoalchemy2.elements import WKTElement
from sqlalchemy import and_, cast, exists, func, literal, or_, select, update
from sqlalchemy.orm import Session

from app.features.cats.domain.models import CatStatus, GeoPoint
from app.features.posts.domain.models import (
    CatObservationStats,
    PostAuthorSummary,
    PostCatSummary,
    PostDetailRecord,
    PostPage,
    PostRecord,
    PostSortOrder,
)
from app.features.posts.domain.repositories import PostCreateDraft, PostRepository
from app.infrastructure.db.models import schema


class SqlAlchemyPostRepository(PostRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def create(self, draft: PostCreateDraft) -> PostDetailRecord:
        post = schema.Post(
            id=draft.id,
            cat_id=draft.cat_id,
            user_id=draft.user_id,
            photo_url=draft.photo_url,
            thumb_url=draft.thumb_url,
            description=draft.description,
            location=(
                WKTElement(
                    f"POINT({draft.location_longitude} {draft.location_latitude})",
                    srid=4326,
                )
                if draft.location_latitude is not None and draft.location_longitude is not None
                else None
            ),
            status=draft.status,
            is_public=draft.is_public,
            like_count=0,
            comment_count=0,
        )
        self.session.add(post)
        post.photos = [
            schema.PostPhoto(
                id=photo.id,
                photo_url=photo.photo_url,
                thumb_url=photo.thumb_url,
                position=photo.position,
            )
            for photo in draft.photos
        ]
        self.session.flush()
        created = self.get_by_id(post.id, viewer_user_id=draft.user_id)
        if created is None:
            raise RuntimeError("Created post could not be loaded.")
        return created

    def get_by_id(
        self,
        post_id: UUID,
        *,
        include_deleted: bool = False,
        viewer_user_id: UUID | None = None,
    ) -> PostDetailRecord | None:
        statement = self._base_statement(
            viewer_user_id=viewer_user_id,
            include_deleted=include_deleted,
        )
        statement = statement.where(schema.Post.id == post_id)
        row = self.session.execute(statement).mappings().first()
        if row is None:
            return None
        return self._row_to_detail(row)

    def list_for_user(
        self,
        user_id: UUID,
        *,
        limit: int,
        cursor: str | None,
        sort: PostSortOrder,
        include_private: bool,
        require_visible_cat: bool,
        viewer_user_id: UUID | None = None,
    ) -> PostPage:
        statement = self._base_list_statement(
            viewer_user_id=viewer_user_id,
            include_private=include_private,
            require_visible_cat=require_visible_cat,
        ).where(schema.Post.user_id == user_id)
        statement = self._apply_cursor(statement, cursor, sort, limit)
        rows = self.session.execute(statement).mappings().all()
        items = [self._row_to_record(row) for row in rows[:limit]]
        next_cursor = (
            self._encode_cursor(rows[limit - 1]["created_at"], rows[limit - 1]["post_id"])
            if len(rows) > limit
            else None
        )
        return PostPage(items=items, next_cursor=next_cursor, limit=limit)

    def list_for_cat(
        self,
        cat_id: UUID,
        *,
        limit: int,
        cursor: str | None,
        sort: PostSortOrder,
        include_private: bool,
        require_visible_cat: bool,
        viewer_user_id: UUID | None = None,
    ) -> PostPage:
        statement = self._base_list_statement(
            viewer_user_id=viewer_user_id,
            include_private=include_private,
            require_visible_cat=require_visible_cat,
        ).where(schema.Post.cat_id == cat_id)
        statement = self._apply_cursor(statement, cursor, sort, limit)
        rows = self.session.execute(statement).mappings().all()
        items = [self._row_to_record(row) for row in rows[:limit]]
        next_cursor = (
            self._encode_cursor(rows[limit - 1]["created_at"], rows[limit - 1]["post_id"])
            if len(rows) > limit
            else None
        )
        return PostPage(items=items, next_cursor=next_cursor, limit=limit)

    def list_feed(
        self,
        *,
        limit: int,
        cursor: str | None,
        filter_by: str,
        popular_period: str,
        viewer_user_id: UUID | None,
        viewer_is_moderator: bool,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
    ) -> PostPage:
        statement = self._base_statement(
            viewer_user_id=viewer_user_id,
            include_deleted=False,
        )
        if not viewer_is_moderator:
            statement = self._apply_feed_visibility(statement, viewer_user_id=viewer_user_id)

        filter_name = filter_by.lower()
        if filter_name == "recent":
            statement = self._apply_recent_feed(statement, cursor, limit, cursor_filter="recent")
        elif filter_name == "popular":
            statement = self._apply_popular_period(statement, popular_period)
            statement = self._apply_popular_feed(statement, cursor, limit)
        elif filter_name in {"injured", "needs_help"}:
            status = (
                schema.CatStatus.INJURED
                if filter_name == "injured"
                else schema.CatStatus.NEEDS_HELP
            )
            statement = statement.where(schema.Cat.status == status)
            statement = self._apply_recent_feed(
                statement,
                cursor,
                limit,
                cursor_filter=filter_name,
            )
        elif filter_name == "nearby":
            statement = self._apply_nearby_feed(
                statement,
                cursor,
                limit,
                latitude=latitude,
                longitude=longitude,
                radius_meters=radius_meters,
            )
        else:  # pragma: no cover - validated before repository call
            raise ValueError("Invalid feed filter.")

        rows = self.session.execute(statement).mappings().all()
        has_next_page = len(rows) > limit
        rows = rows[:limit]
        items = [self._row_to_record(row) for row in rows]
        next_cursor = (
            self._build_feed_cursor(filter_name, rows[limit - 1]) if has_next_page else None
        )
        return PostPage(items=items, next_cursor=next_cursor, limit=limit)

    def mark_deleted(self, post_id: UUID, *, deleted_at: datetime, deleted_by: UUID | None) -> bool:
        result = self.session.execute(
            update(schema.Post)
            .where(schema.Post.id == post_id, schema.Post.deleted_at.is_(None))
            .values(deleted_at=deleted_at)
        )
        return bool(getattr(result, "rowcount", 0))

    def recalculate_cat_stats(self, cat_id: UUID) -> CatObservationStats:
        statement = select(
            func.min(schema.Post.created_at),
            func.max(schema.Post.created_at),
            func.count(schema.Post.id),
            func.count(func.distinct(schema.Post.user_id)),
            func.coalesce(func.sum(schema.Post.like_count), 0),
        ).where(schema.Post.cat_id == cat_id, schema.Post.deleted_at.is_(None))
        row = self.session.execute(statement).one()
        first_seen_at, last_seen_at, total_observations, total_contributors, total_likes = row
        stats = CatObservationStats(
            first_seen_at=first_seen_at,
            last_seen_at=last_seen_at,
            total_observations=int(total_observations or 0),
            total_contributors=int(total_contributors or 0),
            total_likes=int(total_likes or 0),
        )
        self.session.execute(
            update(schema.Cat)
            .where(schema.Cat.id == cat_id)
            .values(
                first_seen_at=stats.first_seen_at,
                last_seen_at=stats.last_seen_at,
                total_observations=stats.total_observations,
                total_contributors=stats.total_contributors,
                total_likes=stats.total_likes,
            )
        )
        return stats

    def _base_statement(
        self,
        *,
        viewer_user_id: UUID | None,
        include_deleted: bool,
    ):
        liked_by_me = (
            exists(
                select(1).where(
                    schema.Like.post_id == schema.Post.id,
                    schema.Like.user_id == viewer_user_id,
                )
            )
            if viewer_user_id is not None
            else literal(False)
        )
        statement = (
            select(
                schema.Post.id.label("post_id"),
                schema.Post.cat_id.label("post_cat_id"),
                schema.Post.user_id.label("post_user_id"),
                schema.Post.photo_url.label("photo_url"),
                schema.Post.thumb_url.label("thumb_url"),
                schema.Post.description.label("description"),
                schema.Post.status.label("post_status"),
                schema.Post.is_public.label("is_public"),
                schema.Post.like_count.label("like_count"),
                schema.Post.comment_count.label("comment_count"),
                schema.Post.created_at.label("created_at"),
                schema.Post.updated_at.label("updated_at"),
                schema.Post.deleted_at.label("deleted_at"),
                func.ST_Y(schema.Post.location).label("latitude"),
                func.ST_X(schema.Post.location).label("longitude"),
                schema.Cat.id.label("cat_id"),
                schema.Cat.name.label("cat_name"),
                schema.Cat.cover_photo_url.label("cat_cover_photo_url"),
                schema.Cat.status.label("cat_status"),
                schema.Cat.is_active.label("cat_is_active"),
                schema.Cat.merged_into.label("cat_merged_into"),
                schema.Cat.deleted_at.label("cat_deleted_at"),
                schema.User.id.label("author_id"),
                schema.User.name.label("author_name"),
                schema.User.avatar_url.label("author_avatar_url"),
                liked_by_me.label("is_liked_by_me"),
            )
            .select_from(schema.Post)
            .join(schema.Cat, schema.Post.cat_id == schema.Cat.id)
            .outerjoin(schema.User, schema.Post.user_id == schema.User.id)
        )
        if not include_deleted:
            statement = statement.where(schema.Post.deleted_at.is_(None))
        return statement

    def _base_list_statement(
        self,
        *,
        viewer_user_id: UUID | None,
        include_private: bool,
        require_visible_cat: bool,
    ):
        statement = self._base_statement(viewer_user_id=viewer_user_id, include_deleted=False)
        if not include_private:
            statement = statement.where(schema.Post.is_public.is_(True))
        if require_visible_cat:
            statement = statement.where(
                schema.Cat.deleted_at.is_(None),
                schema.Cat.is_active.is_(True),
                schema.Cat.merged_into.is_(None),
            )
        return statement

    def _apply_feed_visibility(self, statement, *, viewer_user_id: UUID | None):
        cat_visible = and_(
            schema.Cat.deleted_at.is_(None),
            schema.Cat.is_active.is_(True),
            schema.Cat.merged_into.is_(None),
        )
        if viewer_user_id is None:
            return statement.where(schema.Post.is_public.is_(True), cat_visible)
        return statement.where(
            or_(
                schema.Post.user_id == viewer_user_id,
                and_(schema.Post.is_public.is_(True), cat_visible),
            )
        )

    def _apply_recent_feed(
        self,
        statement,
        cursor: str | None,
        limit: int,
        *,
        cursor_filter: str,
    ):
        if cursor is not None:
            cursor_created_at, cursor_id = self._decode_feed_cursor(cursor, cursor_filter)
            statement = statement.where(
                or_(
                    schema.Post.created_at < cursor_created_at,
                    and_(
                        schema.Post.created_at == cursor_created_at,
                        schema.Post.id < cursor_id,
                    ),
                )
            )
        return statement.order_by(schema.Post.created_at.desc(), schema.Post.id.desc()).limit(
            limit + 1
        )

    def _apply_popular_feed(self, statement, cursor: str | None, limit: int):
        if cursor is not None:
            cursor_like_count, cursor_created_at, cursor_id = self._decode_feed_cursor(
                cursor,
                "popular",
            )
            statement = statement.where(
                or_(
                    schema.Post.like_count < cursor_like_count,
                    and_(
                        schema.Post.like_count == cursor_like_count,
                        or_(
                            schema.Post.created_at < cursor_created_at,
                            and_(
                                schema.Post.created_at == cursor_created_at,
                                schema.Post.id < cursor_id,
                            ),
                        ),
                    ),
                )
            )
        return statement.order_by(
            schema.Post.like_count.desc(),
            schema.Post.created_at.desc(),
            schema.Post.id.desc(),
        ).limit(limit + 1)

    def _apply_popular_period(self, statement, popular_period: str):
        if popular_period == "day":
            return statement.where(
                schema.Post.created_at >= datetime.now(UTC) - timedelta(hours=24)
            )
        if popular_period == "month":
            return statement.where(schema.Post.created_at >= datetime.now(UTC) - timedelta(days=30))
        return statement

    def _apply_nearby_feed(
        self,
        statement,
        cursor: str | None,
        limit: int,
        *,
        latitude: float | None,
        longitude: float | None,
        radius_meters: int | None,
    ):
        if latitude is None or longitude is None or radius_meters is None:
            raise ValueError("Nearby feed requires latitude, longitude and radius_meters.")

        reference_geom = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
        distance_expr = func.ST_Distance(
            cast(schema.Post.location, Geography),
            cast(reference_geom, Geography),
        )
        statement = statement.where(schema.Post.location.is_not(None))
        statement = statement.where(
            schema.Post.location.op("&&")(func.ST_Expand(reference_geom, radius_meters / 111_320.0))
        )
        statement = statement.where(
            func.ST_DWithin(
                cast(schema.Post.location, Geography),
                cast(reference_geom, Geography),
                radius_meters,
            )
        )
        statement = statement.add_columns(distance_expr.label("distance_meters"))

        if cursor is not None:
            cursor_distance, cursor_created_at, cursor_id = self._decode_feed_cursor(
                cursor,
                "nearby",
            )
            statement = statement.where(
                or_(
                    distance_expr > cursor_distance,
                    and_(
                        distance_expr == cursor_distance,
                        or_(
                            schema.Post.created_at < cursor_created_at,
                            and_(
                                schema.Post.created_at == cursor_created_at,
                                schema.Post.id < cursor_id,
                            ),
                        ),
                    ),
                )
            )
        return statement.order_by(
            distance_expr.asc(),
            schema.Post.created_at.desc(),
            schema.Post.id.desc(),
        ).limit(limit + 1)

    def _apply_cursor(
        self,
        statement,
        cursor: str | None,
        sort: PostSortOrder,
        limit: int,
    ):
        order_desc = sort == PostSortOrder.LATEST
        if cursor is not None:
            cursor_created_at, cursor_id = self._decode_cursor(cursor)
            if order_desc:
                statement = statement.where(
                    or_(
                        schema.Post.created_at < cursor_created_at,
                        and_(
                            schema.Post.created_at == cursor_created_at,
                            schema.Post.id < cursor_id,
                        ),
                    )
                )
            else:
                statement = statement.where(
                    or_(
                        schema.Post.created_at > cursor_created_at,
                        and_(
                            schema.Post.created_at == cursor_created_at,
                            schema.Post.id > cursor_id,
                        ),
                    )
                )
        order_created = (
            schema.Post.created_at.desc() if order_desc else schema.Post.created_at.asc()
        )
        order_id = schema.Post.id.desc() if order_desc else schema.Post.id.asc()
        statement = statement.order_by(order_created, order_id).limit(limit + 1)
        return statement

    def _decode_cursor(self, cursor: str) -> tuple[datetime, UUID]:
        try:
            raw = base64.urlsafe_b64decode(cursor.encode("utf-8")).decode("utf-8")
            payload = json.loads(raw)
            created_at_value = payload["created_at"]
            if isinstance(created_at_value, str):
                created_at = datetime.fromisoformat(created_at_value.replace("Z", "+00:00"))
            else:
                raise ValueError
            post_id = UUID(str(payload["id"]))
            return created_at, post_id
        except Exception as exc:  # pragma: no cover - defensive cursor handling
            raise ValueError("Invalid cursor.") from exc

    def _decode_feed_cursor(self, cursor: str, expected_filter: str) -> tuple[Any, ...]:
        try:
            raw = base64.urlsafe_b64decode(cursor.encode("utf-8")).decode("utf-8")
            payload = json.loads(raw)
            if payload.get("filter") != expected_filter:
                raise ValueError
            created_at_value = payload["created_at"]
            if isinstance(created_at_value, str):
                created_at = datetime.fromisoformat(created_at_value.replace("Z", "+00:00"))
            else:
                raise ValueError
            post_id = UUID(str(payload["id"]))
            if expected_filter == "popular":
                return int(payload["like_count"]), created_at, post_id
            if expected_filter == "nearby":
                return float(payload["distance_meters"]), created_at, post_id
            return created_at, post_id
        except Exception as exc:  # pragma: no cover - defensive cursor handling
            raise ValueError("Invalid cursor.") from exc

    def _encode_cursor(self, created_at: datetime, post_id: UUID) -> str:
        payload = {
            "created_at": created_at.astimezone(UTC).isoformat().replace("+00:00", "Z"),
            "id": str(post_id),
        }
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("utf-8")

    def _build_feed_cursor(self, filter_by: str, row: Any) -> str:
        payload: dict[str, Any] = {
            "filter": filter_by,
            "created_at": row["created_at"].astimezone(UTC).isoformat().replace("+00:00", "Z"),
            "id": str(row["post_id"]),
        }
        if filter_by == "popular":
            payload["like_count"] = int(row["like_count"] or 0)
        if filter_by == "nearby":
            payload["distance_meters"] = float(row["distance_meters"])
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("utf-8")

    def _row_to_detail(self, row: Any) -> PostDetailRecord:
        return PostDetailRecord(
            **self._row_to_dict(row),
            is_liked_by_me=bool(row["is_liked_by_me"]),
        )

    def _row_to_record(self, row: Any) -> PostRecord:
        return PostRecord(**self._row_to_dict(row))

    def _row_to_dict(self, row: Any) -> dict[str, Any]:
        mapping = row
        post_status = mapping["post_status"]
        cat_status = mapping["cat_status"]
        author_id = mapping["author_id"]
        return {
            "id": mapping["post_id"],
            "cat_id": mapping["post_cat_id"],
            "user_id": mapping["post_user_id"],
            "photo_url": mapping["photo_url"],
            "thumb_url": mapping["thumb_url"],
            "photo_urls": self._photo_urls_for_post(mapping["post_id"], mapping["photo_url"]),
            "description": mapping["description"],
            "location": (
                GeoPoint(
                    latitude=float(mapping["latitude"]),
                    longitude=float(mapping["longitude"]),
                )
                if mapping["latitude"] is not None and mapping["longitude"] is not None
                else None
            ),
            "status": CatStatus(post_status) if post_status is not None else None,
            "is_public": bool(mapping["is_public"]),
            "like_count": int(mapping["like_count"] or 0),
            "comment_count": int(mapping["comment_count"] or 0),
            "created_at": mapping["created_at"],
            "updated_at": mapping["updated_at"],
            "deleted_at": mapping["deleted_at"],
            "author": (
                PostAuthorSummary(
                    id=author_id,
                    name=mapping["author_name"],
                    avatar_url=mapping["author_avatar_url"],
                )
                if author_id is not None
                else None
            ),
            "cat": PostCatSummary(
                id=mapping["cat_id"],
                name=mapping["cat_name"],
                cover_photo_url=mapping["cat_cover_photo_url"],
                status=CatStatus(cat_status),
                is_active=bool(mapping["cat_is_active"]),
                merged_into=mapping["cat_merged_into"],
                deleted_at=mapping["cat_deleted_at"],
            ),
        }

    def _photo_urls_for_post(self, post_id: UUID, fallback_photo_url: str) -> list[str]:
        rows = (
            self.session.execute(
                select(schema.PostPhoto.photo_url)
                .where(schema.PostPhoto.post_id == post_id)
                .order_by(schema.PostPhoto.position.asc(), schema.PostPhoto.id.asc())
            )
            .scalars()
            .all()
        )
        urls = [url for url in rows if url]
        return urls or [fallback_photo_url]
