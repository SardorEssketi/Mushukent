from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from app.features.places.domain.models import PlaceCategory, PlaceSummary


@dataclass(slots=True)
class PlaceListPage:
    items: list[PlaceSummary]
    next_cursor: str | None
    limit: int


class PlaceRepository(Protocol):
    def list_places(
        self,
        *,
        categories: list[PlaceCategory] | None,
        limit: int,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        bbox: tuple[float, float, float, float] | None = None,
    ) -> PlaceListPage: ...
