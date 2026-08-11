from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from enum import StrEnum
from uuid import UUID

from app.features.cats.domain.models import GeoPoint


class PlaceCategory(StrEnum):
    PET_SHOP = "pet_shop"
    VETERINARY = "veterinary"
    SHELTER = "shelter"


class PlaceSource(StrEnum):
    OSM = "osm"
    MANUAL = "manual"


@dataclass(slots=True)
class PlaceSummary:
    id: UUID
    name: str
    category: PlaceCategory
    location: GeoPoint
    address: str | None = None
    phone: str | None = None
    website: str | None = None
    opening_hours: str | None = None
    source: PlaceSource = PlaceSource.MANUAL
    source_id: str | None = None
    verified_at: datetime | None = None
    distance_meters: float | None = None
