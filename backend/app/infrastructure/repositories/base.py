from __future__ import annotations

from abc import ABC
from datetime import UTC, datetime
from typing import Generic, TypeVar
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from app.infrastructure.db.mixins import SoftDeleteMixin

ModelT = TypeVar("ModelT")
SoftDeleteModelT = TypeVar("SoftDeleteModelT", bound=SoftDeleteMixin)


class RepositoryBase(ABC, Generic[ModelT]):
    """Shared SQLAlchemy repository helpers.

    Concrete repositories will extend this base once feature-specific use cases
    are implemented.
    """

    def __init__(self, session: Session, model: type[ModelT]) -> None:
        self.session = session
        self.model = model

    def add(self, entity: ModelT) -> ModelT:
        self.session.add(entity)
        return entity

    def get_by_id(self, entity_id: UUID) -> ModelT | None:
        return self.session.get(self.model, entity_id)

    def list_all(self) -> list[ModelT]:
        statement = select(self.model)
        return list(self.session.scalars(statement).all())

    def delete(self, entity: ModelT) -> None:
        self.session.delete(entity)


class SoftDeleteRepository(RepositoryBase[SoftDeleteModelT], Generic[SoftDeleteModelT]):
    """Repository helper for soft-deletable records."""

    def soft_delete(self, entity: SoftDeleteModelT) -> SoftDeleteModelT:
        entity.deleted_at = datetime.now(UTC)
        self.session.add(entity)
        return entity

    def restore(self, entity: SoftDeleteModelT) -> SoftDeleteModelT:
        entity.deleted_at = None
        self.session.add(entity)
        return entity
