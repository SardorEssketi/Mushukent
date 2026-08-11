from __future__ import annotations

from typing import Protocol

from app.core.security import api_error
from app.features.places.application.schemas import (
    GenericListResponse,
    PlaceListItem,
    PlaceListQuery,
    to_place_list_response,
)
from app.features.places.domain.repositories import PlaceRepository
from app.infrastructure.db.session import DatabaseSessionManager


class PlaceRepositoryFactory(Protocol):
    def __call__(self, session) -> PlaceRepository: ...


class PlacesService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: PlaceRepositoryFactory,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory

    def list_places(self, query: PlaceListQuery) -> GenericListResponse[PlaceListItem]:
        bbox = self._parse_bbox(query.bbox)
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            page = repository.list_places(
                categories=query.categories,
                limit=query.limit,
                latitude=query.latitude,
                longitude=query.longitude,
                radius_meters=query.radius_meters,
                bbox=bbox,
            )
            return to_place_list_response(
                page.items,
                next_cursor=page.next_cursor,
                limit=page.limit,
            )

    @staticmethod
    def _parse_bbox(bbox: str | None) -> tuple[float, float, float, float] | None:
        if bbox is None:
            return None
        parts = [part.strip() for part in bbox.split(",") if part.strip()]
        if len(parts) != 4:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["invalid"]},
            )
        try:
            min_lon, min_lat, max_lon, max_lat = (float(part) for part in parts)
        except ValueError as exc:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["invalid"]},
            ) from exc
        if not (
            -180 <= min_lon <= 180
            and -180 <= max_lon <= 180
            and -90 <= min_lat <= 90
            and -90 <= max_lat <= 90
        ):
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["out_of_range"]},
            )
        if min_lon >= max_lon or min_lat >= max_lat:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["invalid_bounds"]},
            )
        return (min_lon, min_lat, max_lon, max_lat)
