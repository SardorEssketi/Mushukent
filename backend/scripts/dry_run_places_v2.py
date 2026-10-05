"""Offline V2 import rehearsal in an isolated in-memory database.

This cannot contact production. It validates stable keys, insert/update/skip
semantics, and readback through the public place response schema. It does not
replace a later PostGIS migration and repository integration test.
"""

from __future__ import annotations

import json
import sqlite3
import sys
from collections import Counter
from pathlib import Path
from uuid import UUID, uuid5

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "backend"))

from backend.scripts.build_places_v2 import OUT, TASHKENT_BOUNDS, read_jsonl  # noqa: E402
from backend.scripts.qa_places_v2_release import CATEGORY_MAP, NAMESPACE  # noqa: E402

from app.features.cats.domain.models import GeoPoint  # noqa: E402
from app.features.places.application.schemas import PlaceListItem  # noqa: E402
from app.features.places.domain.models import PlaceCategory, PlaceSource, PlaceSummary  # noqa: E402


def import_row(place: dict) -> dict:
    """Map one V2 location; identity never changes with name or coordinates."""
    if place["category"] not in CATEGORY_MAP:
        raise ValueError(f"Unsupported category: {place['category']}")
    if place["source_id"] != "places_v2:" + place["id"]:
        raise ValueError(f"Invalid stable source key: {place['source_id']}")
    if UUID(place["import_uuid"]) != uuid5(NAMESPACE, place["source_id"]):
        raise ValueError(f"Import UUID differs from stable source key: {place['id']}")
    if not place["name"] or place["latitude"] is None or place["longitude"] is None:
        raise ValueError(f"Missing required map identity: {place['id']}")
    if not (
        TASHKENT_BOUNDS[0] <= place["latitude"] <= TASHKENT_BOUNDS[1]
        and TASHKENT_BOUNDS[2] <= place["longitude"] <= TASHKENT_BOUNDS[3]
    ):
        raise ValueError(f"Point outside Tashkent bounds: {place['id']}")
    if not place["address"] and place["field_confidence"].get("location_evidence") not in {
        "high",
        "medium",
    }:
        raise ValueError(f"Insufficient physical-location evidence: {place['id']}")
    return {
        "id": place["import_uuid"],
        "source_id": place["source_id"],
        "name": place["name"],
        "category": CATEGORY_MAP[place["category"]],
        "latitude": place["latitude"],
        "longitude": place["longitude"],
        "address": place["address"],
        "phone": (place["phones"] or [None, None])[0],
        "phone_2": (place["phones"] or [None, None])[1] if len(place["phones"]) > 1 else None,
        "website": place["website"],
        "instagram": place["instagram"],
        "telegram": place["telegram"],
        "opening_hours": place["opening_hours"],
        "description": place["description"],
        "verified_at": place["verified_at"],
    }


def make_database() -> sqlite3.Connection:
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    db.execute(
        """CREATE TABLE places (
        source_id TEXT PRIMARY KEY, id TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
        category TEXT NOT NULL, latitude REAL NOT NULL, longitude REAL NOT NULL,
        address TEXT, phone TEXT, phone_2 TEXT, website TEXT, instagram TEXT,
        telegram TEXT, opening_hours TEXT, description TEXT, verified_at TEXT
    )"""
    )
    return db


def upsert(db: sqlite3.Connection, row: dict) -> str:
    current = db.execute("SELECT * FROM places WHERE source_id = ?", (row["source_id"],)).fetchone()
    if current is None:
        columns = list(row)
        db.execute(
            f"INSERT INTO places ({', '.join(columns)}) VALUES ({', '.join('?' for _ in columns)})",
            tuple(row.values()),
        )
        return "insert"
    if current["id"] != row["id"]:
        return "conflict"
    changed = [key for key in row if current[key] != row[key]]
    if not changed:
        return "skip"
    columns = [key for key in row if key != "source_id"]
    db.execute(
        f"UPDATE places SET {', '.join(key + ' = ?' for key in columns)} WHERE source_id = ?",
        tuple(row[key] for key in columns) + (row["source_id"],),
    )
    return "update"


def api_readback(row: sqlite3.Row) -> PlaceListItem:
    category = PlaceCategory(row["category"])
    summary = PlaceSummary(
        id=UUID(row["id"]),
        name=row["name"],
        category=category,
        categories=[category],
        location=GeoPoint(latitude=row["latitude"], longitude=row["longitude"]),
        address=row["address"],
        phone=row["phone"],
        phone_2=row["phone_2"],
        website=row["website"],
        instagram=row["instagram"],
        telegram=row["telegram"],
        opening_hours=row["opening_hours"],
        description=row["description"],
        source=PlaceSource.MANUAL,
        source_id=row["source_id"],
    )
    return PlaceListItem.model_validate(summary, from_attributes=True)


def dry_run() -> dict:
    places = read_jsonl(OUT / "places_release_candidate.jsonl")
    db = make_database()
    counts = Counter()
    failures = []
    mapped = []
    for place in places:
        try:
            mapped.append(import_row(place))
        except (ValueError, KeyError, IndexError) as error:
            failures.append({"place_id": place.get("id"), "error": str(error)})
    with db:
        for row in mapped:
            counts[upsert(db, row)] += 1
    readback_failures = []
    for row in db.execute("SELECT * FROM places"):
        try:
            payload = api_readback(row).model_dump(mode="json")
            if payload["source_id"] != row["source_id"] or payload["category"] != row["category"]:
                raise ValueError("API representation differs from stored row")
        except Exception as error:
            readback_failures.append({"source_id": row["source_id"], "error": str(error)})
    repeat = Counter()
    with db:
        for row in mapped:
            repeat[upsert(db, row)] += 1
    report = {
        "database": "isolated SQLite :memory:",
        "postgis_repository_tested": False,
        "human_approval_status": "pending",
        "input_places": len(places),
        "inserts": counts["insert"],
        "updates": counts["update"],
        "skips": counts["skip"],
        "conflicts": counts["conflict"],
        "failures": failures,
        "api_schema_readback": len(mapped) - len(readback_failures),
        "api_schema_readback_failures": readback_failures,
        "repeat_run_skips": repeat["skip"],
        "note": (
            "Technical rehearsal only. PostgreSQL/PostGIS migration and HTTP repository "
            "readback remain required before approval."
        ),
    }
    (OUT / "isolated_dry_run_report.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    db.close()
    return report


if __name__ == "__main__":
    print(json.dumps(dry_run(), indent=2, ensure_ascii=False))
