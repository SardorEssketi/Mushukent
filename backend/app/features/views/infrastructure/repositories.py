from __future__ import annotations

from uuid import UUID

from sqlalchemy import update
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.features.views.domain.repositories import PostViewRepository
from app.infrastructure.db.models import schema

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
