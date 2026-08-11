from __future__ import annotations

from typing import Any
from uuid import UUID

from sqlalchemy import delete, func, literal, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.features.cats.domain.models import CatStatus, GeoPoint
from app.features.likes.domain.repositories import LikeRepository
from app.features.posts.domain.models import PostAuthorSummary, PostCatSummary, PostDetailRecord
from app.infrastructure.db.models import schema


class SqlAlchemyLikeRepository(LikeRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def lock_visible_post(
        self,
        post_id: UUID,
        *,
        viewer_user_id: UUID | None,
    ) -> PostDetailRecord | None:
        statement = self._post_statement(
            viewer_user_id=viewer_user_id,
            include_deleted=False,
        ).where(schema.Post.id == post_id)
        row = self.session.execute(statement.with_for_update(of=schema.Post)).mappings().first()
        if row is None:
            return None
        return self._row_to_post_detail(row)

    def create_like(self, post_id: UUID, user_id: UUID) -> bool:
        stmt = (
            pg_insert(schema.Like)
            .values(post_id=post_id, user_id=user_id)
            .on_conflict_do_nothing(index_elements=[schema.Like.post_id, schema.Like.user_id])
            .returning(schema.Like.id)
        )
        row = self.session.execute(stmt).first()
        return row is not None

    def delete_like(self, post_id: UUID, user_id: UUID) -> bool:
        result = self.session.execute(
            delete(schema.Like).where(
                schema.Like.post_id == post_id,
                schema.Like.user_id == user_id,
            )
        )
        return bool(getattr(result, "rowcount", 0))

    def increment_post_like_count(self, post_id: UUID) -> None:
        self.session.execute(
            update(schema.Post)
            .where(schema.Post.id == post_id)
            .values(like_count=schema.Post.like_count + 1)
        )

    def decrement_post_like_count(self, post_id: UUID) -> None:
        self.session.execute(
            update(schema.Post)
            .where(schema.Post.id == post_id)
            .values(like_count=func.greatest(schema.Post.like_count - 1, 0))
        )

    def _post_statement(self, *, viewer_user_id: UUID | None, include_deleted: bool):
        liked_by_me = literal(False)
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

    def _row_to_post_detail(self, row: Any) -> PostDetailRecord:
        post_status = row["post_status"]
        cat_status = row["cat_status"]
        author_id = row["author_id"]
        return PostDetailRecord(
            id=row["post_id"],
            cat_id=row["post_cat_id"],
            user_id=row["post_user_id"],
            photo_url=row["photo_url"],
            thumb_url=row["thumb_url"],
            photo_urls=[row["photo_url"]],
            description=row["description"],
            location=GeoPoint(
                latitude=float(row["latitude"]),
                longitude=float(row["longitude"]),
            ),
            status=CatStatus(post_status) if post_status is not None else None,
            is_public=bool(row["is_public"]),
            like_count=int(row["like_count"] or 0),
            comment_count=int(row["comment_count"] or 0),
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            deleted_at=row["deleted_at"],
            author=(
                PostAuthorSummary(
                    id=author_id,
                    name=row["author_name"],
                    avatar_url=row["author_avatar_url"],
                )
                if author_id is not None
                else None
            ),
            cat=PostCatSummary(
                id=row["cat_id"],
                name=row["cat_name"],
                cover_photo_url=row["cat_cover_photo_url"],
                status=CatStatus(cat_status),
                is_active=bool(row["cat_is_active"]),
                merged_into=row["cat_merged_into"],
                deleted_at=row["cat_deleted_at"],
            ),
            is_liked_by_me=False,
        )
