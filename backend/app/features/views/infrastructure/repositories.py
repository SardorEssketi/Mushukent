from __future__ import annotations

from uuid import UUID

from sqlalchemy import and_, or_, select, update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.features.views.domain.repositories import PostViewRepository
from app.infrastructure.db.models import schema
from app.infrastructure.repositories.blocking import exclude_blocked

COUNTED_MODELS = {
    "post": schema.Post,
    "lost_pet": schema.LostPet,
    "adoption": schema.AdoptionPost,
}


class SqlAlchemyPostViewRepository(PostViewRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def record(
        self, post_kind: str, post_id: UUID, *, user_id: UUID | None, guest_key: str | None
    ) -> bool:
        stmt = (
            pg_insert(schema.PostView)
            .values(post_kind=post_kind, post_id=post_id, user_id=user_id, guest_key=guest_key)
            .on_conflict_do_nothing()
            .returning(schema.PostView.id)
        )
        return self.session.execute(stmt).first() is not None

    def increment_view_count(self, post_kind: str, post_id: UUID) -> int:
        model = COUNTED_MODELS[post_kind]
        return int(
            self.session.execute(
                update(model)
                .where(model.id == post_id)
                .values(view_count=model.view_count + 1)
                .returning(model.view_count)
            ).scalar_one()
        )

    # ---- set-based batch path (POST /views/seen, load audit FIX-3) -----------------------------

    def visible_targets(
        self,
        post_kind: str,
        post_ids: list[UUID],
        *,
        viewer_user_id: UUID | None,
        viewer_is_moderator: bool,
    ) -> dict[UUID, tuple[UUID | None, int]]:
        """(author id, view count) of the ids this viewer may see; one query per kind.

        Same rules as opening the item: posts are visible when not deleted and the viewer is a
        moderator, the author, or the post is public with a visible cat; lost-pet and adoption
        posts when public and not deleted. Blocks in either direction hide the item.
        """
        if not post_ids:
            return {}
        model = COUNTED_MODELS[post_kind]
        statement = select(model.id, model.user_id, model.view_count).where(
            model.id.in_(post_ids), model.deleted_at.is_(None)
        )
        if post_kind == "post":
            statement = statement.join(schema.Cat, schema.Post.cat_id == schema.Cat.id)
            if not viewer_is_moderator:
                public = and_(
                    schema.Post.is_public.is_(True),
                    schema.Cat.deleted_at.is_(None),
                    schema.Cat.is_active.is_(True),
                    schema.Cat.merged_into.is_(None),
                )
                statement = statement.where(
                    or_(schema.Post.user_id == viewer_user_id, public)
                    if viewer_user_id is not None
                    else public
                )
        else:
            statement = statement.where(model.is_public.is_(True))
        statement = exclude_blocked(statement, viewer_user_id, model.user_id)
        return {
            row.id: (row.user_id, int(row.view_count or 0))
            for row in self.session.execute(statement)
        }

    def record_many(
        self,
        targets: list[tuple[str, UUID]],
        *,
        user_id: UUID | None,
        guest_key: str | None,
    ) -> set[tuple[str, UUID]]:
        """Insert one view per target; returns the targets that were new for this viewer.

        Values are inserted in (kind, id) order, so two overlapping batches wait on each other's
        unique-index entries in the same order and cannot deadlock.
        """
        if not targets:
            return set()
        ordered = sorted(targets, key=lambda target: (target[0], str(target[1])))
        stmt = (
            pg_insert(schema.PostView)
            .values(
                [
                    {
                        "post_kind": kind,
                        "post_id": post_id,
                        "user_id": user_id,
                        "guest_key": guest_key,
                    }
                    for kind, post_id in ordered
                ]
            )
            .on_conflict_do_nothing()
            .returning(schema.PostView.post_kind, schema.PostView.post_id)
        )
        return {(row.post_kind, row.post_id) for row in self.session.execute(stmt)}

    def increment_view_counts(self, post_kind: str, post_ids: list[UUID]) -> dict[UUID, int]:
        """+1 for each id, locking the rows in id order first (one statement)."""
        if not post_ids:
            return {}
        model = COUNTED_MODELS[post_kind]
        locked = (
            select(model.id)
            .where(model.id.in_(post_ids))
            .order_by(model.id)
            .with_for_update()
            .subquery()
        )
        rows = self.session.execute(
            update(model)
            .where(model.id == locked.c.id)
            .values(view_count=model.view_count + 1)
            .returning(model.id, model.view_count)
        )
        return {row.id: int(row.view_count) for row in rows}
