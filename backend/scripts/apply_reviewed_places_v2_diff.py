"""Guarded, rerunnable application of the immutable Places V2 production diff.

Default is read-only dry-run. Production writes require --apply --target
production and an exact approved-diff digest in PLACES_V2_DIFF_SHA. No matching
or deduplication is performed here; every decision comes from the reviewed diff.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from collections import Counter
from pathlib import Path
from uuid import UUID

from geoalchemy2.elements import WKTElement
from sqlalchemy import create_engine, select, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session, selectinload

from app.infrastructure.db.enums import PlaceCategory, PlaceSource
from app.infrastructure.db.models import schema

SNAPSHOT_SHA = "8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be"
DIFF_SHA = "dcbd169f467f89fdbd133a277c95435077891a1e5587f1ae4894fa2eb25577ee"
BASELINE_SHA = "27ae3058ad6ce114a117b8d8ab04876c86dd8beef4f24761dc1f57d2566c395c"
EXPECTED_ACTIONS = {
    "UPDATE_EXISTING": 89,
    "INSERT_NEW": 107,
    "KEEP_UNCHANGED": 36,
    "SKIP_UNRESOLVED": 45,
}
EXPECTED_HEAD = "20261002_0024"
INVENTORY_SQL = """
SELECT row_to_json(place_row)::text FROM (
  SELECT p.id, p.name, p.category::text AS category,
         ST_Y(p.location) AS latitude, ST_X(p.location) AS longitude,
         p.address, p.phone, p.phone_2, p.website, p.opening_hours,
         p.source::text AS source, p.source_id, p.is_active,
         p.created_at, p.updated_at, p.verified_at,
         ARRAY(SELECT l.category::text FROM place_category_links AS l
               WHERE l.place_id = p.id ORDER BY l.category::text) AS categories
  FROM places AS p ORDER BY p.id
) AS place_row
"""
SCALAR_FIELDS = {
    "name",
    "category",
    "address",
    "phone",
    "phone_2",
    "website",
    "opening_hours",
    "source_id",
}


def _load(path: Path, expected_sha: str) -> list[dict]:
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != expected_sha:
        raise RuntimeError(f"Input SHA-256 mismatch: {path.name}: {actual}")
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def _inputs(directory: Path) -> tuple[list[dict], list[dict], list[dict]]:
    snapshot = _load(directory / "places_frozen_release.jsonl", SNAPSHOT_SHA)
    diff = _load(directory / "production_deployment_review_final.jsonl", DIFF_SHA)
    baseline = _load(directory / "production_places_readonly_export.jsonl", BASELINE_SHA)
    actions = Counter(row["action"] for row in diff)
    if (
        len(snapshot) != 217
        or len(baseline) != 149
        or dict(actions) != EXPECTED_ACTIONS
        or len({r["id"] for r in snapshot}) != 217
        or len({r["id"] for r in baseline}) != 149
        or len({r["source_id"] for r in snapshot}) != 217
    ):
        raise RuntimeError("Reviewed input dimensions, actions, or identities differ")
    snapshot_by_id = {r["id"]: r for r in snapshot}
    baseline_by_id = {r["id"]: r for r in baseline}
    mapped = set()
    new_ids = set()
    seen_prod = set()
    for row in diff:
        action = row["action"]
        if action not in EXPECTED_ACTIONS:
            raise RuntimeError("Unreviewed action in diff")
        if row["entity"] == "production":
            uid = row["production_uuid"]
            if uid not in baseline_by_id or uid in seen_prod:
                raise RuntimeError("Production UUID missing or repeated in diff")
            seen_prod.add(uid)
        if action == "UPDATE_EXISTING":
            if not row.get("preserve_production_uuid") or row["v2_id"] not in snapshot_by_id:
                raise RuntimeError("Update has no reviewed UUID preservation")
            if (
                row["v2_id"] in mapped
                or row["v2_source_id"] != snapshot_by_id[row["v2_id"]]["source_id"]
            ):
                raise RuntimeError("Conflicting reviewed update identity")
            mapped.add(row["v2_id"])
            fields = {op["field"] for op in row["field_operations"]}
            if fields != SCALAR_FIELDS | {"latitude", "longitude"}:
                raise RuntimeError("Incomplete reviewed update fields")
            for op in row["field_operations"]:
                if op["production_value"] != baseline_by_id[row["production_uuid"]].get(
                    op["field"]
                ):
                    raise RuntimeError("Field precondition differs from reviewed baseline")
                if op["operation"] not in (
                    "UPDATE_FROM_V2",
                    "PRESERVE_PRODUCTION",
                    "NO_CHANGE",
                    "REVIEW",
                ):
                    raise RuntimeError("Unreviewed field operation")
                if op["operation"] == "UPDATE_FROM_V2" and op["result_value"] is None:
                    raise RuntimeError("Implicit NULL overwrite")
                if (
                    op["operation"] != "UPDATE_FROM_V2"
                    and op["result_value"] != op["production_value"]
                ):
                    raise RuntimeError("Non-update operation changes a production value")
            if not set(row["category_links_before"]) <= set(row["category_links_after"]):
                raise RuntimeError("Reviewed diff removes a category link")
            if sorted(row["category_links_before"]) != sorted(
                baseline_by_id[row["production_uuid"]]["categories"]
            ):
                raise RuntimeError("Category-link precondition differs")
        elif action == "INSERT_NEW":
            frozen = snapshot_by_id.get(row["v2_id"])
            if (
                frozen is None
                or row["v2_id"] in mapped
                or row["new_uuid"] != frozen["import_uuid"]
                or row["v2_source_id"] != frozen["source_id"]
                or row["new_uuid"] in new_ids
                or row["new_uuid"] in baseline_by_id
            ):
                raise RuntimeError("Conflicting reviewed insert identity")
            mapped.add(row["v2_id"])
            new_ids.add(row["new_uuid"])
            if set(row["insert_values"]) != SCALAR_FIELDS | {"latitude", "longitude"}:
                raise RuntimeError("Insert fields differ from reviewed diff")
            if row["insert_values"]["source_id"] != frozen["source_id"]:
                raise RuntimeError("Insert source ID differs from frozen V2")
        elif action in ("KEEP_UNCHANGED", "SKIP_UNRESOLVED"):
            if row.get("field_operations") or row.get("insert_values"):
                raise RuntimeError("Held/unchanged row contains a write operation")
    if len(seen_prod) != 149 or len(mapped) != 196:
        raise RuntimeError("Diff does not cover expected reviewed identities")
    return snapshot, diff, baseline


def _target_allowed(url: str, target: str, apply: bool) -> None:
    parsed = make_url(url)
    if parsed.drivername != "postgresql+psycopg":
        raise RuntimeError("PostgreSQL/psycopg URL required")
    if target == "production":
        if (
            parsed.host != "db"
            or parsed.database != "mushukistan"
            or parsed.username != "mushukistan"
        ):
            raise RuntimeError("Refusing an unexpected production database target")
        if apply and os.getenv("PLACES_V2_DIFF_SHA") != DIFF_SHA:
            raise RuntimeError(
                "Production apply requires the exact approved diff SHA in PLACES_V2_DIFF_SHA"
            )
    elif target == "isolated":
        if (
            parsed.host != "gate-db"
            or parsed.database != "v2_deploy_gate"
            or os.getenv("PLACES_V2_GATE_ONLY") != "1"
        ):
            raise RuntimeError("Refusing a non-isolated rehearsal target")
    else:
        raise RuntimeError("Unknown target")


def _inventory(session: Session) -> list[dict]:
    return [json.loads(value) for value in session.execute(text(INVENTORY_SQL)).scalars()]


def _values_equal(actual: dict, expected: dict, *, updated: bool) -> bool:
    for key in actual.keys() | expected.keys():
        if updated and key == "updated_at":
            continue
        if key in ("latitude", "longitude"):
            if abs(actual[key] - expected[key]) > 1e-8:
                return False
        elif actual.get(key) != expected.get(key):
            return False
    return True


def _post_state(actual: list[dict], baseline: list[dict], diff: list[dict]) -> bool:
    by_id = {r["id"]: r for r in actual}
    baseline_by_id = {r["id"]: r for r in baseline}
    inserts = {r["new_uuid"] for r in diff if r["action"] == "INSERT_NEW"}
    if len(by_id) != 256 or set(by_id) != set(baseline_by_id) | inserts:
        return False
    for row in diff:
        action = row["action"]
        if action in ("KEEP_UNCHANGED", "SKIP_UNRESOLVED") and row["entity"] == "production":
            uid = row["production_uuid"]
            if by_id[uid] != baseline_by_id[uid]:
                return False
        elif action == "UPDATE_EXISTING":
            uid = row["production_uuid"]
            expected = dict(baseline_by_id[uid])
            for op in row["field_operations"]:
                expected[op["field"]] = op["result_value"]
            expected["categories"] = sorted(row["category_links_after"])
            if not _values_equal(by_id[uid], expected, updated=True):
                return False
        elif action == "INSERT_NEW":
            uid = row["new_uuid"]
            actual_row = by_id[uid]
            expected = row["insert_values"]
            if (
                actual_row["id"] != uid
                or actual_row["source"] != "manual"
                or not actual_row["is_active"]
                or actual_row["categories"] != sorted(row["category_links"])
            ):
                return False
            for field, value in expected.items():
                if field in ("latitude", "longitude"):
                    if abs(actual_row[field] - value) > 1e-8:
                        return False
                elif actual_row.get(field) != value:
                    return False
    return True


def _apply(session: Session, diff: list[dict]) -> None:
    for row in diff:
        if row["action"] == "UPDATE_EXISTING":
            place = session.scalar(
                select(schema.Place)
                .options(selectinload(schema.Place.category_links))
                .where(schema.Place.id == UUID(row["production_uuid"]))
            )
            if place is None:
                raise RuntimeError("Approved production UUID disappeared")
            operations = {op["field"]: op for op in row["field_operations"]}
            for field in SCALAR_FIELDS:
                op = operations[field]
                if op["operation"] == "UPDATE_FROM_V2":
                    value = op["result_value"]
                    setattr(place, field, PlaceCategory(value) if field == "category" else value)
            if any(
                operations[key]["operation"] == "UPDATE_FROM_V2"
                for key in ("latitude", "longitude")
            ):
                lat = operations["latitude"]["result_value"]
                lon = operations["longitude"]["result_value"]
                place.location = WKTElement(f"POINT({lon} {lat})", srid=4326)
            existing_links = {str(link.category) for link in place.category_links}
            for category in row["category_links_after"]:
                if category not in existing_links:
                    place.category_links.append(
                        schema.PlaceCategoryLink(category=PlaceCategory(category))
                    )
        elif row["action"] == "INSERT_NEW":
            values = row["insert_values"]
            place = schema.Place(
                id=UUID(row["new_uuid"]),
                source=PlaceSource.MANUAL,
                source_id=values["source_id"],
                name=values["name"],
                category=PlaceCategory(values["category"]),
                location=WKTElement(
                    f"POINT({values['longitude']} {values['latitude']})", srid=4326
                ),
                address=values["address"],
                phone=values["phone"],
                phone_2=values["phone_2"],
                website=values["website"],
                opening_hours=values["opening_hours"],
                is_active=True,
            )
            place.category_links = [
                schema.PlaceCategoryLink(category=PlaceCategory(category))
                for category in row["category_links"]
            ]
            session.add(place)
    session.flush()


def execute(inputs: Path, target: str, apply: bool) -> dict:
    snapshot, diff, baseline = _inputs(inputs)
    del snapshot  # identity checks were completed before opening a DB connection
    url = os.environ.get("DATABASE_URL", "")
    _target_allowed(url, target, apply)
    engine = create_engine(url, pool_pre_ping=True)
    try:
        with Session(engine) as session, session.begin():
            if not apply:
                session.execute(text("SET TRANSACTION READ ONLY"))
            else:
                session.execute(
                    text("LOCK TABLE places, place_category_links IN SHARE ROW EXCLUSIVE MODE")
                )
            revision = session.execute(text("SELECT version_num FROM alembic_version")).scalar_one()
            if revision != EXPECTED_HEAD:
                raise RuntimeError(f"Wrong Alembic revision: {revision}")
            actual = _inventory(session)
            if _post_state(actual, baseline, diff):
                return {
                    "state": "ALREADY_APPLIED",
                    "updates": 0,
                    "inserts": 0,
                    "skipped_reviewed": 45,
                    "final_places": len(actual),
                    "writes": 0,
                }
            if actual != baseline:
                raise RuntimeError(
                    "Database differs from exact reviewed production baseline; no writes performed"
                )
            if not apply:
                return {
                    "state": "READY",
                    "updates": 89,
                    "inserts": 107,
                    "skipped_reviewed": 45,
                    "current_places": len(actual),
                    "writes": 0,
                }
            _apply(session, diff)
            after = _inventory(session)
            if not _post_state(after, baseline, diff):
                raise RuntimeError("Post-write invariants failed; transaction will roll back")
            return {
                "state": "APPLIED",
                "updates": 89,
                "inserts": 107,
                "deletes": 0,
                "skipped_reviewed": 45,
                "final_places": len(after),
                "writes": 196,
            }
    finally:
        engine.dispose()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--target", choices=("isolated", "production"), required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    print(json.dumps(execute(args.inputs, args.target, args.apply), sort_keys=True))


if __name__ == "__main__":
    main()
