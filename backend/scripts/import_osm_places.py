from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from dataclasses import dataclass

from geoalchemy2.elements import WKTElement
from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session, sessionmaker

from app.infrastructure.db.enums import PlaceCategory, PlaceSource
from app.infrastructure.db.models import schema

OVERPASS_URL = "https://overpass-api.de/api/interpreter"
TASHKENT_BBOX = (41.1800, 69.0500, 41.4300, 69.4200)
USER_AGENT = "mushukistan-backend/0.1 osm-place-import"


@dataclass(slots=True)
class OsmPlace:
    source_id: str
    name: str
    category: PlaceCategory
    latitude: float
    longitude: float
    address: str | None
    phone: str | None
    website: str | None
    opening_hours: str | None


def build_query(bbox: tuple[float, float, float, float]) -> str:
    south, west, north, east = bbox
    bbox_text = f"{south},{west},{north},{east}"
    return f"""
[out:json][timeout:35];
(
  nwr["amenity"="veterinary"]({bbox_text});
  nwr["shop"="pet"]({bbox_text});
  nwr["amenity"="animal_shelter"]({bbox_text});
  nwr["animal_shelter"="cat"]({bbox_text});
  nwr["animal_boarding"="cat"]({bbox_text});
);
out center tags;
"""


def fetch_overpass(query: str, *, overpass_url: str = OVERPASS_URL) -> dict[str, object]:
    encoded = urllib.parse.urlencode({"data": query}).encode("utf-8")
    request = urllib.request.Request(
        overpass_url,
        data=encoded,
        headers={
            "Content-Type": "application/x-www-form-urlencoded",
            "User-Agent": USER_AGENT,
        },
        method="POST",
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def parse_places(payload: dict[str, object]) -> list[OsmPlace]:
    elements = payload.get("elements", [])
    if not isinstance(elements, list):
        return []

    places: list[OsmPlace] = []
    seen: set[str] = set()
    for element in elements:
        if not isinstance(element, dict):
            continue
        tags = element.get("tags")
        if not isinstance(tags, dict):
            continue
        source_id = f"{element.get('type')}/{element.get('id')}"
        if source_id in seen:
            continue
        seen.add(source_id)

        latitude = element.get("lat")
        longitude = element.get("lon")
        center = element.get("center")
        if (latitude is None or longitude is None) and isinstance(center, dict):
            latitude = center.get("lat")
            longitude = center.get("lon")
        if latitude is None or longitude is None:
            continue

        category = _category_for_tags(tags)
        name = _clean_text(tags.get("name")) or _fallback_name(category)
        places.append(
            OsmPlace(
                source_id=source_id,
                name=name,
                category=category,
                latitude=float(latitude),
                longitude=float(longitude),
                address=_address_for_tags(tags),
                phone=_first_text(tags, "phone", "contact:phone", "mobile", "contact:mobile"),
                website=_first_text(tags, "website", "contact:website"),
                opening_hours=_clean_text(tags.get("opening_hours")),
            )
        )
    return places


def upsert_places(session: Session, places: list[OsmPlace]) -> tuple[int, int]:
    created = 0
    updated = 0
    for place in places:
        existing = session.scalars(
            select(schema.Place).where(
                schema.Place.source == PlaceSource.OSM,
                schema.Place.source_id == place.source_id,
            )
        ).one_or_none()
        if existing is None:
            existing = schema.Place(source=PlaceSource.OSM, source_id=place.source_id)
            session.add(existing)
            created += 1
        else:
            updated += 1

        existing.name = place.name
        existing.category = place.category
        existing.location = WKTElement(f"POINT({place.longitude} {place.latitude})", srid=4326)
        existing.address = place.address
        existing.phone = place.phone
        existing.website = place.website
        existing.opening_hours = place.opening_hours
        existing.is_active = True
        existing.category_links = [schema.PlaceCategoryLink(category=place.category)]
    session.flush()
    return created, updated


def _category_for_tags(tags: dict[object, object]) -> PlaceCategory:
    if tags.get("amenity") == "veterinary":
        return PlaceCategory.VETERINARY
    if tags.get("shop") == "pet":
        return PlaceCategory.PET_SHOP
    return PlaceCategory.SHELTER


def _fallback_name(category: PlaceCategory) -> str:
    if category == PlaceCategory.VETERINARY:
        return "Veterinary clinic"
    if category == PlaceCategory.PET_SHOP:
        return "Pet shop"
    return "Animal shelter"


def _first_text(tags: dict[object, object], *keys: str) -> str | None:
    for key in keys:
        value = _clean_text(tags.get(key))
        if value is not None:
            return value
    return None


def _clean_text(value: object) -> str | None:
    if not isinstance(value, str):
        return None
    stripped = value.strip()
    return stripped or None


def _address_for_tags(tags: dict[object, object]) -> str | None:
    parts = [
        _clean_text(tags.get("addr:street")),
        _clean_text(tags.get("addr:housenumber")),
        _clean_text(tags.get("addr:city")),
    ]
    address = ", ".join(part for part in parts if part)
    return address or None


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Import Tashkent cat-support places from OSM.")
    parser.add_argument("--database-url", default=os.getenv("DATABASE_URL"))
    parser.add_argument("--overpass-url", default=OVERPASS_URL)
    parser.add_argument("--dry-run", action="store_true")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    if not args.database_url:
        print("DATABASE_URL is required.", file=sys.stderr)
        return 2

    payload = fetch_overpass(build_query(TASHKENT_BBOX), overpass_url=args.overpass_url)
    places = parse_places(payload)
    if args.dry_run:
        print(f"Fetched {len(places)} places.")
        return 0

    engine = create_engine(args.database_url, pool_pre_ping=True)
    session_factory = sessionmaker(bind=engine, class_=Session, expire_on_commit=False)
    with session_factory.begin() as session:
        created, updated = upsert_places(session, places)
    print(f"Imported {len(places)} places: {created} created, {updated} updated.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
