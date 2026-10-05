from __future__ import annotations

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.api.v1.routes.places import router as places_router
from app.core.dependencies import get_places_service
from app.features.places.application.schemas import (
    GenericListResponse,
    PlaceListItem,
    PlaceListQuery,
)
from app.features.places.domain.models import PlaceCategory as DomainPlaceCategory
from app.features.places.infrastructure.repositories import _primary_category
from app.infrastructure.db.enums import PlaceCategory as DbPlaceCategory
from app.infrastructure.db.models import schema


class _RecordingPlacesService:
    def __init__(self) -> None:
        self.query: PlaceListQuery | None = None

    def list_places(self, query: PlaceListQuery) -> GenericListResponse[PlaceListItem]:
        self.query = query
        return GenericListResponse[PlaceListItem](items=[], limit=query.limit)


def test_veterinary_pharmacy_is_supported_by_places_runtime() -> None:
    category = DomainPlaceCategory.VETERINARY_PHARMACY
    assert DbPlaceCategory.VETERINARY_PHARMACY.value == category.value
    assert category.value in schema.place_category_enum.enums
    assert _primary_category([DomainPlaceCategory.PET_SHOP, category]) == category

    service = _RecordingPlacesService()
    app = FastAPI()
    app.include_router(places_router, prefix="/api/v1")
    app.dependency_overrides[get_places_service] = lambda: service

    with TestClient(app) as client:
        response = client.get("/api/v1/places", params={"category": category.value})

    assert response.status_code == 200
    assert response.json()["data"]["items"] == []
    assert service.query is not None
    assert service.query.categories == [category]
