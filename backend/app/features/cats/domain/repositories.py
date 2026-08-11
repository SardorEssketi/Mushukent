from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol
from uuid import UUID

from app.features.cats.domain.models import (
    CatDetailRecord,
    CatListFilter,
    CatRecord,
    CatSummary,
    ObservationSortOrder,
    PostListItem,
)


@dataclass(slots=True)
class CatListPage:
    items: list[CatSummary]
    next_cursor: str | None
    limit: int


@dataclass(slots=True)
class PostListPage:
    items: list[PostListItem]
    next_cursor: str | None
    limit: int


class CatRepository(Protocol):
    def create(
        self,
        *,
        cat: CatRecord,
    ) -> CatRecord: ...

    def save(self, cat: CatRecord) -> CatRecord: ...

    def get_by_id(self, cat_id: UUID) -> CatRecord | None: ...

    def get_detail(self, cat_id: UUID) -> CatDetailRecord | None: ...

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
    ) -> CatListPage: ...

    def list_history(
        self,
        *,
        cat_id: UUID,
        limit: int,
        cursor: str | None = None,
        order: ObservationSortOrder = ObservationSortOrder.LATEST,
    ) -> PostListPage: ...
