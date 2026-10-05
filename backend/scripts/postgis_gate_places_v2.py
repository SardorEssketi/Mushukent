"""Import and verify the immutable Places V2 snapshot in isolated PostGIS only.

This command refuses every database URL except the dedicated Docker gate DB.
It never writes the research snapshot or other V2 data files.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter
from datetime import datetime
from pathlib import Path
from uuid import UUID

from backend.scripts.dry_run_places_v2 import import_row
from fastapi.testclient import TestClient
from geoalchemy2.elements import WKTElement
from sqlalchemy import create_engine, func, select, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session, selectinload

from app.features.places.application.schemas import PlaceDetailResponse
from app.features.places.infrastructure.repositories import SqlAlchemyPlaceRepository
from app.infrastructure.db.enums import PlaceCategory, PlaceSource
from app.infrastructure.db.models import schema

ROOT = Path(__file__).resolve().parents[2]
SNAPSHOT = ROOT / "data" / "places_v2" / "output" / "places_frozen_release.jsonl"
ALIASES = ROOT / "data" / "places_v2" / "output" / "places_release_aliases.jsonl"
EXPECTED_SHA256 = "8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be"
BBOX = "69.05,41.18,69.47,41.43"


def gate_database_url() -> str:
    url = os.environ.get("DATABASE_URL", "")
    parsed = make_url(url)
    if (
        os.environ.get("PLACES_V2_GATE_ONLY") != "1"
        or parsed.host != "gate-db"
        or parsed.database != "v2_gate"
        or parsed.username != "v2_gate"
        or parsed.drivername != "postgresql+psycopg"
    ):
        raise RuntimeError("Refusing a non-isolated database URL")
    return url


def frozen_rows() -> tuple[list[dict], list[dict]]:
    digest = hashlib.sha256(SNAPSHOT.read_bytes()).hexdigest()
    if digest != EXPECTED_SHA256:
        raise RuntimeError(f"Frozen snapshot hash mismatch: {digest}")
    raw = [json.loads(line) for line in SNAPSHOT.read_text(encoding="utf-8").splitlines()]
    if len(raw) != 217 or len({row["source_id"] for row in raw}) != 217:
        raise RuntimeError("Frozen snapshot must contain 217 unique places")
    aliases = [json.loads(line) for line in ALIASES.read_text(encoding="utf-8").splitlines()]
    if len(aliases) != 3 or any(
        alias["retired_source_id"] in {row["source_id"] for row in raw} for alias in aliases
    ):
        raise RuntimeError("Retired alias appears in the frozen snapshot")
    mapped = [import_row(row) for row in raw]
    return mapped, aliases


def _expected_value(row: dict, key: str):
    if key == "verified_at":
        return datetime.fromisoformat(row[key]) if row[key] else None
    if key == "category":
        return PlaceCategory(row[key])
    return row[key]


FIELDS = (
    "name",
    "category",
    "address",
    "phone",
    "phone_2",
    "website",
    "instagram",
    "telegram",
    "opening_hours",
    "description",
    "verified_at",
)


def _same(place: schema.Place, row: dict) -> bool:
    return (
        all(getattr(place, key) == _expected_value(row, key) for key in FIELDS)
        and abs(place.latitude - row["latitude"]) < 1e-8
        and abs(place.longitude - row["longitude"]) < 1e-8
        and {link.category for link in place.category_links} == {PlaceCategory(row["category"])}
        and place.is_active
    )


def _assign(place: schema.Place, row: dict) -> None:
    for key in FIELDS:
        setattr(place, key, _expected_value(row, key))
    place.location = WKTElement(f"POINT({row['longitude']} {row['latitude']})", srid=4326)
    place.is_active = True
    place.category_links = [schema.PlaceCategoryLink(category=PlaceCategory(row["category"]))]


def import_snapshot() -> dict:
    database_url = gate_database_url()
    rows, aliases = frozen_rows()
    counts: Counter[str] = Counter()
    engine = create_engine(database_url, pool_pre_ping=True)
    try:
        with Session(engine) as session, session.begin():
            version = session.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
            if version != "20261002_0024":
                raise RuntimeError(f"Wrong migration version: {version}")
            for row in rows:
                uid = UUID(row["id"])
                existing = session.scalar(
                    select(schema.Place)
                    .options(selectinload(schema.Place.category_links))
                    .where(
                        schema.Place.source == PlaceSource.MANUAL,
                        schema.Place.source_id == row["source_id"],
                    )
                )
                if existing:
                    if existing.id != uid:
                        counts["conflicts"] += 1
                    elif _same(existing, row):
                        counts["skips"] += 1
                    else:
                        _assign(existing, row)
                        counts["updates"] += 1
                    continue
                if session.get(schema.Place, uid) is not None:
                    counts["conflicts"] += 1
                    continue
                place = schema.Place(id=uid, source=PlaceSource.MANUAL, source_id=row["source_id"])
                _assign(place, row)
                session.add(place)
                counts["inserts"] += 1
            if counts["conflicts"]:
                raise RuntimeError(f"Stable-ID conflicts: {counts['conflicts']}")
            session.flush()
        with Session(engine) as session:
            final_count = session.scalar(select(func.count()).select_from(schema.Place))
            present = {
                source_id for (source_id,) in session.execute(select(schema.Place.source_id))
            }
        if final_count != 217 or present != {row["source_id"] for row in rows}:
            raise RuntimeError("Database count or source IDs differ from frozen release")
        if any(alias["retired_source_id"] in present for alias in aliases):
            raise RuntimeError("Retired alias created a physical place")
        return {
            "snapshot_sha256": EXPECTED_SHA256,
            "inserts": counts["inserts"],
            "updates": counts["updates"],
            "skips": counts["skips"],
            "conflicts": counts["conflicts"],
            "failures": 0,
            "database_place_count": final_count,
        }
    finally:
        engine.dispose()


def verify_snapshot() -> dict:
    database_url = gate_database_url()
    rows, aliases = frozen_rows()
    engine = create_engine(database_url, pool_pre_ping=True)
    expected_sources = {row["source_id"] for row in rows}
    try:
        with Session(engine) as session:
            repo = SqlAlchemyPlaceRepository(session)
            actual_sources = {
                source_id for (source_id,) in session.execute(select(schema.Place.source_id))
            }
            if actual_sources != expected_sources:
                raise RuntimeError("Database source IDs do not match frozen release")
            for row in rows:
                item = repo.get_place(UUID(row["id"]))
                if item is None:
                    raise RuntimeError(f"Repository cannot read {row['source_id']}")
                payload = PlaceDetailResponse.model_validate(item, from_attributes=True).model_dump(
                    mode="json"
                )
                if (
                    payload["source_id"] != row["source_id"]
                    or payload["category"] != row["category"]
                    or abs(payload["location"]["latitude"] - row["latitude"]) > 1e-8
                    or abs(payload["location"]["longitude"] - row["longitude"]) > 1e-8
                ):
                    raise RuntimeError(f"Repository serialization differs: {row['source_id']}")
            within_bounds = session.scalar(
                text(
                    """
                SELECT count(*) FROM places WHERE ST_Contains(
                    ST_MakeEnvelope(69.05, 41.18, 69.47, 41.43, 4326), location)
            """
                )
            )
            if within_bounds != 217:
                raise RuntimeError(f"Only {within_bounds} places inside Flutter map bounds")
            if any(alias["retired_source_id"] in actual_sources for alias in aliases):
                raise RuntimeError("Retired alias exists in database")

        # Exercise the real FastAPI route and its repository dependency, not a mocked service.
        from app.main import create_app

        with TestClient(create_app()) as client:
            for row in rows:
                response = client.get(f"/api/v1/places/{row['id']}")
                if response.status_code != 200:
                    raise RuntimeError(
                        f"API detail failed: {row['source_id']} {response.status_code}"
                    )
                payload = response.json()["data"]
                if (
                    payload["source_id"] != row["source_id"]
                    or payload["category"] != row["category"]
                ):
                    raise RuntimeError(f"API detail differs: {row['source_id']}")
            category_counts = {}
            bbox_counts = {}
            for research_category, api_category in (
                ("pet_store", "pet_shop"),
                ("veterinary_clinic", "veterinary"),
                ("veterinary_pharmacy", "veterinary_pharmacy"),
                ("animal_shelter", "shelter"),
            ):
                response = client.get(
                    "/api/v1/places", params={"category": api_category, "limit": 200}
                )
                if response.status_code != 200:
                    raise RuntimeError(f"API category filter failed: {api_category}")
                category_ids = {item["id"] for item in response.json()["data"]["items"]}
                expected_category_ids = {
                    row["id"] for row in rows if row["category"] == api_category
                }
                if category_ids != expected_category_ids:
                    raise RuntimeError(f"API category IDs differ: {api_category}")
                category_counts[research_category] = len(category_ids)
                response = client.get(
                    "/api/v1/places",
                    params={
                        "category": api_category,
                        "bbox": BBOX,
                        "map_only": "true",
                        "limit": 200,
                    },
                )
                if response.status_code != 200:
                    raise RuntimeError(f"API map bbox failed: {api_category}")
                map_ids = {item["id"] for item in response.json()["data"]["items"]}
                if map_ids != expected_category_ids:
                    raise RuntimeError(f"API map bounds miss pins: {api_category}")
                bbox_counts[research_category] = len(map_ids)
            nearby_checked = 0
            for row in (
                rows[0],
                rows[len(rows) // 4],
                rows[len(rows) // 2],
                rows[3 * len(rows) // 4],
                rows[-1],
            ):
                response = client.get(
                    "/api/v1/places",
                    params={
                        "lat": row["latitude"],
                        "lon": row["longitude"],
                        "radius_meters": 100,
                        "map_only": "true",
                        "limit": 200,
                    },
                )
                if response.status_code != 200 or row["id"] not in {
                    item["id"] for item in response.json()["data"]["items"]
                }:
                    raise RuntimeError(f"API nearby spatial query missed {row['source_id']}")
                nearby_checked += 1
        if sum(category_counts.values()) != 217:
            raise RuntimeError("API category totals differ from frozen release")
        return {
            "database_place_count": len(actual_sources),
            "repository_readback": 217,
            "api_detail_readback": 217,
            "category_filter_counts": category_counts,
            "map_bbox_counts": bbox_counts,
            "postgis_within_map_bounds": within_bounds,
            "nearby_queries_checked": nearby_checked,
            "retired_aliases_absent": len(aliases),
            "stable_ids_match": 217,
        }
    finally:
        engine.dispose()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["import", "verify"])
    args = parser.parse_args()
    result = import_snapshot() if args.mode == "import" else verify_snapshot()
    print(json.dumps(result, ensure_ascii=False, indent=2))
