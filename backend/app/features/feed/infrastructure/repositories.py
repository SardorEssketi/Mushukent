from __future__ import annotations

from uuid import UUID

from geoalchemy2 import Geography
from sqlalchemy import Float, and_, cast, func, literal, or_, select, union_all

from app.features.feed.domain.models import (
    FEED_ITEM_TYPE_RANK,
    FeedCursorPosition,
    FeedItemKey,
    FeedItemType,
    FeedKeyPage,
)
from app.features.posts.domain.models import PostRecord
from app.features.posts.infrastructure.repositories import SqlAlchemyPostRepository
from app.infrastructure.db.models import schema
from app.infrastructure.repositories.blocking import exclude_blocked


class SqlAlchemyFeedRepository(SqlAlchemyPostRepository):
    def list_mixed_feed_keys(
        self,
        *,
        limit: int,
        cursor: FeedCursorPosition | None,
        filter_by: str,
        viewer_user_id: UUID | None,
        viewer_is_moderator: bool,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
    ) -> FeedKeyPage:
        if filter_by not in {"recent", "nearby"}:
            raise ValueError("Mixed feed supports only recent and nearby filters.")
        if filter_by == "nearby":
            if latitude is None or longitude is None or radius_meters is None:
                raise ValueError("Nearby feed requires latitude, longitude and radius_meters.")
            return self._nearby_feed_keys(
                limit=limit,
                cursor=cursor,
                viewer_user_id=viewer_user_id,
                viewer_is_moderator=viewer_is_moderator,
                latitude=latitude,
                longitude=longitude,
                radius_meters=radius_meters,
            )

        reference_geom = None
        if filter_by == "nearby":
            if latitude is None or longitude is None or radius_meters is None:
                raise ValueError("Nearby feed requires latitude, longitude and radius_meters.")
            reference_geom = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)

        post_distance = cast(literal(None), Float)
        if reference_geom is not None:
            post_distance = func.ST_Distance(
                cast(schema.Post.location, Geography),
                cast(reference_geom, Geography),
            )
        post_index = (
            select(
                schema.Post.id.label("item_id"),
                schema.Post.created_at.label("created_at"),
                literal(FeedItemType.OBSERVATION.value).label("item_type"),
                literal(FEED_ITEM_TYPE_RANK[FeedItemType.OBSERVATION]).label("type_rank"),
                post_distance.label("distance_meters"),
            )
            .select_from(schema.Post)
            .join(schema.Cat, schema.Post.cat_id == schema.Cat.id)
            .where(schema.Post.deleted_at.is_(None))
        )
        if not viewer_is_moderator:
            post_index = self._apply_feed_visibility(
                post_index,
                viewer_user_id=viewer_user_id,
            )
        post_index = exclude_blocked(post_index, viewer_user_id, schema.Post.user_id)
        if reference_geom is not None:
            post_index = post_index.where(
                schema.Post.location.is_not(None),
                func.ST_DWithin(
                    cast(schema.Post.location, Geography),
                    cast(reference_geom, Geography),
                    radius_meters,
                ),
            )

        lost_pet_distance = cast(literal(None), Float)
        if reference_geom is not None:
            lost_pet_distance = func.ST_Distance(
                cast(schema.LostPet.last_seen_location, Geography),
                cast(reference_geom, Geography),
            )
        lost_pet_index = select(
            schema.LostPet.id.label("item_id"),
            schema.LostPet.created_at.label("created_at"),
            literal(FeedItemType.LOST_PET.value).label("item_type"),
            literal(FEED_ITEM_TYPE_RANK[FeedItemType.LOST_PET]).label("type_rank"),
            lost_pet_distance.label("distance_meters"),
        ).where(
            schema.LostPet.deleted_at.is_(None),
            schema.LostPet.is_public.is_(True),
            schema.LostPet.is_resolved.is_(False),
        )
        lost_pet_index = exclude_blocked(lost_pet_index, viewer_user_id, schema.LostPet.user_id)
        if reference_geom is not None:
            lost_pet_index = lost_pet_index.where(
                func.ST_DWithin(
                    cast(schema.LostPet.last_seen_location, Geography),
                    cast(reference_geom, Geography),
                    radius_meters,
                )
            )

        source_indexes = [post_index, lost_pet_index]
        if filter_by == "recent":
            adoption_index = select(
                schema.AdoptionPost.id.label("item_id"),
                schema.AdoptionPost.created_at.label("created_at"),
                literal(FeedItemType.ADOPTION.value).label("item_type"),
                literal(FEED_ITEM_TYPE_RANK[FeedItemType.ADOPTION]).label("type_rank"),
                cast(literal(None), Float).label("distance_meters"),
            ).where(
                schema.AdoptionPost.deleted_at.is_(None),
                schema.AdoptionPost.is_public.is_(True),
                schema.AdoptionPost.is_resolved.is_(False),
            )
            adoption_index = exclude_blocked(
                adoption_index, viewer_user_id, schema.AdoptionPost.user_id
            )
            source_indexes.append(adoption_index)

        mixed_feed = union_all(*source_indexes).subquery("mixed_feed")
        statement = select(mixed_feed)
        if cursor is not None:
            cursor_rank = FEED_ITEM_TYPE_RANK[cursor.item_type]
            timestamp_boundary = or_(
                mixed_feed.c.created_at < cursor.created_at,
                and_(
                    mixed_feed.c.created_at == cursor.created_at,
                    or_(
                        mixed_feed.c.type_rank < cursor_rank,
                        and_(
                            mixed_feed.c.type_rank == cursor_rank,
                            mixed_feed.c.item_id < cursor.item_id,
                        ),
                    ),
                ),
            )
            if filter_by == "nearby":
                if cursor.distance_meters is None:
                    raise ValueError("Nearby feed cursor is missing distance.")
                statement = statement.where(
                    or_(
                        mixed_feed.c.distance_meters > cursor.distance_meters,
                        and_(
                            mixed_feed.c.distance_meters == cursor.distance_meters,
                            timestamp_boundary,
                        ),
                    )
                )
            else:
                statement = statement.where(timestamp_boundary)

        if filter_by == "nearby":
            statement = statement.order_by(
                mixed_feed.c.distance_meters.asc(),
                mixed_feed.c.created_at.desc(),
                mixed_feed.c.type_rank.desc(),
                mixed_feed.c.item_id.desc(),
            )
        else:
            statement = statement.order_by(
                mixed_feed.c.created_at.desc(),
                mixed_feed.c.type_rank.desc(),
                mixed_feed.c.item_id.desc(),
            )

        rows = self.session.execute(statement.limit(limit + 1)).mappings().all()
        return FeedKeyPage(
            items=[
                FeedItemKey(
                    created_at=row["created_at"],
                    item_type=FeedItemType(row["item_type"]),
                    item_id=row["item_id"],
                    distance_meters=(
                        float(row["distance_meters"])
                        if row["distance_meters"] is not None
                        else None
                    ),
                )
                for row in rows[:limit]
            ],
            has_next=len(rows) > limit,
        )

    def _nearby_feed_keys(
        self,
        *,
        limit: int,
        cursor: FeedCursorPosition | None,
        viewer_user_id: UUID | None,
        viewer_is_moderator: bool,
        latitude: float,
        longitude: float,
        radius_meters: int,
    ) -> FeedKeyPage:
        """Nearest-first page via KNN on the geography GiST indexes (load audit FIX-2).

        Order: (distance, created_at DESC, type_rank DESC, id DESC); ``distance`` is the sphere
        distance ``geography <-> point``, used for both the order and the cursor. The radius
        filter is the same spheroid ``ST_DWithin`` as before, so the set of items is unchanged.

        An index can only order by distance, so each branch runs in two index-assisted steps:
        1. KNN: the distance ``bound`` of the (limit + 1)-th nearest row after the cursor;
        2. range: every row after the cursor within ``bound``, ties included.
        Any row of the global top (limit + 1) lies within its branch's bound, so the merge below
        never drops a row that belongs on the page, even with many rows at one spot.
        """
        point = func.geography(func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326))

        def after_cursor(distance, created_at, item_id, rank: int):
            if cursor is None:
                return None
            if cursor.distance_meters is None:
                raise ValueError("Nearby feed cursor is missing distance.")
            cursor_rank = FEED_ITEM_TYPE_RANK[cursor.item_type]
            if rank < cursor_rank:
                same_time = literal(True)
            elif rank == cursor_rank:
                same_time = item_id < cursor.item_id
            else:
                same_time = literal(False)
            return or_(
                distance > cursor.distance_meters,
                and_(
                    distance == cursor.distance_meters,
                    or_(
                        created_at < cursor.created_at,
                        and_(created_at == cursor.created_at, same_time),
                    ),
                ),
            )

        def branch(base, geog, created_at, item_id, item_type: FeedItemType):
            rank = FEED_ITEM_TYPE_RANK[item_type]
            distance = geog.op("<->")(point)
            filters = [func.ST_DWithin(geog, point, radius_meters)]
            boundary = after_cursor(distance, created_at, item_id, rank)
            if boundary is not None:
                filters.append(boundary)
            knn = (
                base(distance.label("distance"))
                .where(*filters)
                .order_by(distance)
                .limit(limit + 1)
                .subquery()
            )
            bound = select(func.max(knn.c.distance)).scalar_subquery()
            return base(
                item_id.label("item_id"),
                created_at.label("created_at"),
                literal(item_type.value).label("item_type"),
                literal(rank).label("type_rank"),
                distance.label("distance_meters"),
            ).where(
                *filters,
                # Index-assisted (sphere, use_spheroid=false) range scan, then the exact bound.
                func.ST_DWithin(geog, point, bound + 0.01, False),
                distance <= bound,
            )

        def posts(*columns):
            statement = (
                select(*columns)
                .select_from(schema.Post)
                .join(schema.Cat, schema.Post.cat_id == schema.Cat.id)
                .where(schema.Post.deleted_at.is_(None), schema.Post.location.is_not(None))
            )
            if not viewer_is_moderator:
                statement = self._apply_feed_visibility(statement, viewer_user_id=viewer_user_id)
            return exclude_blocked(statement, viewer_user_id, schema.Post.user_id)

        def lost_pets(*columns):
            statement = select(*columns).where(
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
                schema.LostPet.is_resolved.is_(False),
            )
            return exclude_blocked(statement, viewer_user_id, schema.LostPet.user_id)

        mixed = union_all(
            branch(
                posts,
                func.geography(schema.Post.location),
                schema.Post.created_at,
                schema.Post.id,
                FeedItemType.OBSERVATION,
            ),
            branch(
                lost_pets,
                func.geography(schema.LostPet.last_seen_location),
                schema.LostPet.created_at,
                schema.LostPet.id,
                FeedItemType.LOST_PET,
            ),
        ).subquery("nearby_feed")
        statement = (
            select(mixed)
            .order_by(
                mixed.c.distance_meters.asc(),
                mixed.c.created_at.desc(),
                mixed.c.type_rank.desc(),
                mixed.c.item_id.desc(),
            )
            .limit(limit + 1)
        )
        rows = self.session.execute(statement).mappings().all()
        return FeedKeyPage(
            items=[
                FeedItemKey(
                    created_at=row["created_at"],
                    item_type=FeedItemType(row["item_type"]),
                    item_id=row["item_id"],
                    distance_meters=float(row["distance_meters"]),
                )
                for row in rows[:limit]
            ],
            has_next=len(rows) > limit,
        )

    def get_feed_posts_by_ids(
        self,
        post_ids: list[UUID],
        *,
        viewer_user_id: UUID | None,
        viewer_is_moderator: bool,
    ) -> list[PostRecord]:
        if not post_ids:
            return []
        statement = self._base_statement(
            viewer_user_id=viewer_user_id,
            include_deleted=False,
        )
        if not viewer_is_moderator:
            statement = self._apply_feed_visibility(
                statement,
                viewer_user_id=viewer_user_id,
            )
        statement = exclude_blocked(statement, viewer_user_id, schema.Post.user_id)
        rows = self.session.execute(statement.where(schema.Post.id.in_(post_ids))).mappings().all()
        return self._rows_to_records(rows)
