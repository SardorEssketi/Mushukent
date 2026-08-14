from __future__ import annotations

import base64
import json
from datetime import UTC, datetime
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import and_, func, literal, or_, select, update
from sqlalchemy.orm import Session

from app.features.cats.domain.models import CatStatus, GeoPoint
from app.features.comments.domain.models import (
    CommentOrder,
    CommentPage,
    CommentRecord,
    CommentUserSummary,
)
from app.features.comments.domain.repositories import (
    CommentCreateDraft,
    CommentRepository,
)
from app.features.posts.domain.models import (
    PostAuthorSummary,
    PostCatSummary,
    PostDetailRecord,
)
from app.infrastructure.db.models import schema


class SqlAlchemyCommentRepository(CommentRepository):
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

    def create(self, draft: CommentCreateDraft) -> CommentRecord:
        comment = schema.Comment(
            id=uuid4(),
            post_id=draft.post_id,
            lost_pet_id=draft.lost_pet_id,
            adoption_post_id=draft.adoption_post_id,
            user_id=draft.user_id,
            content=draft.content,
        )
        self.session.add(comment)
        self.session.flush()
        created = self.get_by_id(comment.id)
        if created is None:
            raise RuntimeError("Created comment could not be loaded.")
        return created

    def lost_pet_exists(self, lost_pet_id: UUID) -> bool:
        exists = self.session.scalar(
            select(schema.LostPet.id).where(
                schema.LostPet.id == lost_pet_id,
                schema.LostPet.deleted_at.is_(None),
                schema.LostPet.is_public.is_(True),
            )
        )
        return exists is not None

    def adoption_post_exists(self, adoption_post_id: UUID) -> bool:
        exists = self.session.scalar(
            select(schema.AdoptionPost.id).where(
                schema.AdoptionPost.id == adoption_post_id,
                schema.AdoptionPost.deleted_at.is_(None),
                schema.AdoptionPost.is_public.is_(True),
            )
        )
        return exists is not None

    def get_by_id(
        self,
        comment_id: UUID,
        *,
        include_deleted: bool = False,
        for_update: bool = False,
    ) -> CommentRecord | None:
        statement = self._comment_statement(include_deleted=include_deleted).where(
            schema.Comment.id == comment_id
        )
        if for_update:
            statement = statement.with_for_update(of=schema.Comment)
        row = self.session.execute(statement).mappings().first()
        if row is None:
            return None
        return self._row_to_comment(row)

    def list_for_post(
        self,
        post_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> CommentPage:
        statement = self._comment_statement(include_deleted=False).where(
            schema.Comment.post_id == post_id
        )
        statement = self._apply_cursor(statement, cursor, order, limit)
        rows = self.session.execute(statement).mappings().all()
        items = [self._row_to_comment(row) for row in rows[:limit]]
        next_cursor = (
            self._encode_cursor(rows[limit - 1]["created_at"], rows[limit - 1]["comment_id"])
            if len(rows) > limit
            else None
        )
        return CommentPage(items=items, next_cursor=next_cursor, limit=limit)

    def list_for_lost_pet(
        self,
        lost_pet_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> CommentPage:
        statement = self._comment_statement(include_deleted=False).where(
            schema.Comment.lost_pet_id == lost_pet_id
        )
        statement = self._apply_cursor(statement, cursor, order, limit)
        rows = self.session.execute(statement).mappings().all()
        items = [self._row_to_comment(row) for row in rows[:limit]]
        next_cursor = (
            self._encode_cursor(rows[limit - 1]["created_at"], rows[limit - 1]["comment_id"])
            if len(rows) > limit
            else None
        )
        return CommentPage(items=items, next_cursor=next_cursor, limit=limit)

    def list_for_adoption_post(
        self,
        adoption_post_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> CommentPage:
        statement = self._comment_statement(include_deleted=False).where(
            schema.Comment.adoption_post_id == adoption_post_id
        )
        statement = self._apply_cursor(statement, cursor, order, limit)
        rows = self.session.execute(statement).mappings().all()
        items = [self._row_to_comment(row) for row in rows[:limit]]
        next_cursor = (
            self._encode_cursor(rows[limit - 1]["created_at"], rows[limit - 1]["comment_id"])
            if len(rows) > limit
            else None
        )
        return CommentPage(items=items, next_cursor=next_cursor, limit=limit)

    def list_for_user(
        self,
        user_id: UUID,
        *,
        limit: int,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.DESC,
        include_private: bool,
    ) -> CommentPage:
        statement = self._comment_statement(include_deleted=False).where(
            schema.Comment.user_id == user_id
        )
        if not include_private:
            statement = statement.where(
                schema.Post.deleted_at.is_(None),
                schema.Post.is_public.is_(True),
                schema.Cat.deleted_at.is_(None),
                schema.Cat.is_active.is_(True),
                schema.Cat.merged_into.is_(None),
            )
        statement = self._apply_cursor(statement, cursor, order, limit)
        rows = self.session.execute(statement).mappings().all()
        items = [self._row_to_comment(row) for row in rows[:limit]]
        next_cursor = (
            self._encode_cursor(rows[limit - 1]["created_at"], rows[limit - 1]["comment_id"])
            if len(rows) > limit
            else None
        )
        return CommentPage(items=items, next_cursor=next_cursor, limit=limit)

    def mark_deleted(self, comment_id: UUID, *, deleted_at: datetime) -> bool:
        result = self.session.execute(
            update(schema.Comment)
            .where(schema.Comment.id == comment_id, schema.Comment.deleted_at.is_(None))
            .values(deleted_at=deleted_at)
        )
        return bool(getattr(result, "rowcount", 0))

    def increment_post_comment_count(self, post_id: UUID) -> None:
        self.session.execute(
            update(schema.Post)
            .where(schema.Post.id == post_id)
            .values(comment_count=schema.Post.comment_count + 1)
        )

    def decrement_post_comment_count(self, post_id: UUID) -> None:
        self.session.execute(
            update(schema.Post)
            .where(schema.Post.id == post_id)
            .values(comment_count=func.greatest(schema.Post.comment_count - 1, 0))
        )

    def increment_lost_pet_comment_count(self, lost_pet_id: UUID) -> None:
        self.session.execute(
            update(schema.LostPet)
            .where(schema.LostPet.id == lost_pet_id)
            .values(comment_count=schema.LostPet.comment_count + 1)
        )

    def decrement_lost_pet_comment_count(self, lost_pet_id: UUID) -> None:
        self.session.execute(
            update(schema.LostPet)
            .where(schema.LostPet.id == lost_pet_id)
            .values(comment_count=func.greatest(schema.LostPet.comment_count - 1, 0))
        )

    def increment_adoption_post_comment_count(self, adoption_post_id: UUID) -> None:
        self.session.execute(
            update(schema.AdoptionPost)
            .where(schema.AdoptionPost.id == adoption_post_id)
            .values(comment_count=schema.AdoptionPost.comment_count + 1)
        )

    def decrement_adoption_post_comment_count(self, adoption_post_id: UUID) -> None:
        self.session.execute(
            update(schema.AdoptionPost)
            .where(schema.AdoptionPost.id == adoption_post_id)
            .values(comment_count=func.greatest(schema.AdoptionPost.comment_count - 1, 0))
        )

    def _comment_statement(self, *, include_deleted: bool):
        statement = (
            select(
                schema.Comment.id.label("comment_id"),
                schema.Comment.post_id.label("post_id"),
                schema.Comment.lost_pet_id.label("lost_pet_id"),
                schema.Comment.adoption_post_id.label("adoption_post_id"),
                schema.Comment.user_id.label("comment_user_id"),
                schema.Comment.content.label("content"),
                schema.Comment.created_at.label("created_at"),
                schema.Comment.updated_at.label("updated_at"),
                schema.Comment.deleted_at.label("deleted_at"),
                schema.User.id.label("user_id"),
                schema.User.name.label("user_name"),
                schema.User.avatar_url.label("user_avatar_url"),
            )
            .select_from(schema.Comment)
            .outerjoin(schema.User, schema.Comment.user_id == schema.User.id)
            .outerjoin(schema.Post, schema.Comment.post_id == schema.Post.id)
            .outerjoin(schema.Cat, schema.Post.cat_id == schema.Cat.id)
            .outerjoin(schema.LostPet, schema.Comment.lost_pet_id == schema.LostPet.id)
            .outerjoin(
                schema.AdoptionPost,
                schema.Comment.adoption_post_id == schema.AdoptionPost.id,
            )
        )
        if not include_deleted:
            statement = statement.where(schema.Comment.deleted_at.is_(None))
        return statement

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

    def _apply_cursor(
        self,
        statement,
        cursor: str | None,
        order: CommentOrder,
        limit: int,
    ):
        order_desc = order == CommentOrder.DESC
        if cursor is not None:
            cursor_created_at, cursor_id = self._decode_cursor(cursor)
            if order_desc:
                statement = statement.where(
                    or_(
                        schema.Comment.created_at < cursor_created_at,
                        and_(
                            schema.Comment.created_at == cursor_created_at,
                            schema.Comment.id < cursor_id,
                        ),
                    )
                )
            else:
                statement = statement.where(
                    or_(
                        schema.Comment.created_at > cursor_created_at,
                        and_(
                            schema.Comment.created_at == cursor_created_at,
                            schema.Comment.id > cursor_id,
                        ),
                    )
                )
        order_created = (
            schema.Comment.created_at.desc() if order_desc else schema.Comment.created_at.asc()
        )
        order_id = schema.Comment.id.desc() if order_desc else schema.Comment.id.asc()
        return statement.order_by(order_created, order_id).limit(limit + 1)

    def _decode_cursor(self, cursor: str) -> tuple[datetime, UUID]:
        try:
            raw = base64.urlsafe_b64decode(cursor.encode("utf-8")).decode("utf-8")
            payload = json.loads(raw)
            created_at_value = payload["created_at"]
            if isinstance(created_at_value, str):
                created_at = datetime.fromisoformat(created_at_value.replace("Z", "+00:00"))
            else:
                raise ValueError
            comment_id = UUID(str(payload["id"]))
            return created_at, comment_id
        except Exception as exc:  # pragma: no cover - defensive cursor handling
            raise ValueError("Invalid cursor.") from exc

    def _encode_cursor(self, created_at: datetime, comment_id: UUID) -> str:
        payload = {
            "created_at": created_at.astimezone(UTC).isoformat().replace("+00:00", "Z"),
            "id": str(comment_id),
        }
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("utf-8")

    def _row_to_comment(self, row: Any) -> CommentRecord:
        user_id = row["user_id"]
        return CommentRecord(
            id=row["comment_id"],
            post_id=row["post_id"],
            lost_pet_id=row["lost_pet_id"],
            adoption_post_id=row["adoption_post_id"],
            user_id=row["comment_user_id"],
            content=row["content"],
            created_at=row["created_at"],
            updated_at=row["updated_at"],
            deleted_at=row["deleted_at"],
            user=(
                CommentUserSummary(
                    id=user_id,
                    name=row["user_name"],
                    avatar_url=row["user_avatar_url"],
                )
                if user_id is not None
                else None
            ),
        )

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
            location=(
                GeoPoint(
                    latitude=float(row["latitude"]),
                    longitude=float(row["longitude"]),
                )
                if row["latitude"] is not None and row["longitude"] is not None
                else None
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
