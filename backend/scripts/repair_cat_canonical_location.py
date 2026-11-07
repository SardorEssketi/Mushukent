"""Repair cats left without a canonical location by AUTH-205.

Before the fix, ``POST /posts`` with ``new_cat`` that had a name but no
``canonical_location`` (what the mobile client sends) created the cat with a
NULL canonical location, even though the publication itself had a point. The
map (``GET /cats?bbox=...``) only uses ``cats.canonical_location``, so such
cats never appeared there.

Repair rule (deterministic, conservative, idempotent). A cat is *eligible*
only when every condition holds; otherwise it is reported as *excluded* with
a reason and left unchanged:

* the cat has ``canonical_location IS NULL`` and is not deleted or merged;
* exactly one *originating* post exists: created in the same transaction as
  the cat (same ``created_at``, both from the transaction's ``now()``) by the
  cat's creator (``no_originating_post`` / ``multiple_originating_posts``);
* that post is not deleted (``originating_post_deleted``);
* its *original* creation location is known unambiguously. Every post edit
  writes a ``post_history`` row with a ``before`` snapshot in the same
  transaction (editing and history were introduced together), so:

  - no history row: the current location is the creation location;
  - otherwise the earliest history row's ``before.location`` is; a tie for
    the earliest row, a missing ``location`` key or invalid coordinates make
    it ``original_location_ambiguous``;
  - an original without a point is ``no_original_location`` (the cat was
    correctly created unlocated; a location added by a later edit is a
    separate case, see docs/CAT_LOCATION_REPAIR.md);
* the post still has a location (``location_removed_by_owner``: the owner
  removed it, so no point is published again).

An eligible cat gets its originating post's *original* coordinates, exactly
what the fixed creation path would have stored. ``location_edited`` in the
output marks posts whose location changed after creation;
``--skip-edited-locations`` leaves those out. No other column, post or cat is
touched and an existing canonical location is never overwritten.

Dry run by default: prints one JSON line per eligible and excluded cat and
writes nothing. ``--apply`` also requires ``--confirm-database`` to equal the
connected database name; each repaired row is printed as one JSON line for
the audit record. Do not run against production without the owner's approval
for that run (docs/DEPLOYMENT.md).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections.abc import Sequence
from dataclasses import dataclass
from uuid import UUID

from sqlalchemy import Connection, create_engine, text

_CLASSIFY_SQL = """
WITH unlocated AS (
    SELECT c.id AS cat_id, c.created_at, c.created_by
    FROM cats c
    WHERE c.canonical_location IS NULL
      AND c.deleted_at IS NULL
      AND c.merged_into IS NULL
),
origin AS (
    SELECT u.cat_id,
           p.id AS post_id,
           p.deleted_at AS post_deleted_at,
           ST_Y(p.location) AS current_latitude,
           ST_X(p.location) AS current_longitude,
           count(*) OVER (PARTITION BY u.cat_id) AS origin_matches
    FROM unlocated u
    JOIN posts p
      ON p.cat_id = u.cat_id
     AND p.created_at = u.created_at
     AND p.user_id IS NOT DISTINCT FROM u.created_by
),
first_history AS (
    SELECT o.post_id,
           count(*) AS earliest_rows,
           (array_agg(h.before ORDER BY h.id))[1] AS before
    FROM origin o
    JOIN post_history h ON h.post_id = o.post_id
    WHERE h.created_at = (
        SELECT min(h2.created_at) FROM post_history h2 WHERE h2.post_id = o.post_id
    )
    GROUP BY o.post_id
)
SELECT u.cat_id,
       o.post_id,
       o.origin_matches,
       o.post_deleted_at IS NOT NULL AS post_deleted,
       o.current_latitude,
       o.current_longitude,
       fh.post_id IS NOT NULL AS has_history,
       fh.earliest_rows,
       fh.before ? 'location' AS history_has_location_key,
       jsonb_typeof(fh.before -> 'location') AS history_location_type,
       jsonb_typeof(fh.before -> 'location' -> 'latitude') AS history_latitude_type,
       jsonb_typeof(fh.before -> 'location' -> 'longitude') AS history_longitude_type,
       CASE WHEN jsonb_typeof(fh.before -> 'location' -> 'latitude') = 'number'
            THEN (fh.before -> 'location' ->> 'latitude')::double precision END
           AS history_latitude,
       CASE WHEN jsonb_typeof(fh.before -> 'location' -> 'longitude') = 'number'
            THEN (fh.before -> 'location' ->> 'longitude')::double precision END
           AS history_longitude
FROM unlocated u
LEFT JOIN origin o ON o.cat_id = u.cat_id
LEFT JOIN first_history fh ON fh.post_id = o.post_id
ORDER BY u.cat_id, o.post_id
"""

_REPAIR_SQL = """
UPDATE cats c
SET canonical_location = ST_SetSRID(ST_MakePoint(:longitude, :latitude), 4326)
FROM posts p
WHERE c.id = :cat_id
  AND p.id = :post_id
  AND p.cat_id = c.id
  AND p.deleted_at IS NULL
  AND p.location IS NOT NULL
  AND c.canonical_location IS NULL
  AND c.deleted_at IS NULL
  AND c.merged_into IS NULL
"""


@dataclass(frozen=True, slots=True)
class RepairCandidate:
    cat_id: UUID
    post_id: UUID
    latitude: float
    longitude: float
    location_edited: bool = False

    def as_audit_record(self, *, applied: bool) -> dict[str, object]:
        return {
            "cat_id": str(self.cat_id),
            "source_post_id": str(self.post_id),
            "latitude": self.latitude,
            "longitude": self.longitude,
            "location_edited": self.location_edited,
            "applied": applied,
        }


@dataclass(frozen=True, slots=True)
class ExcludedCat:
    cat_id: UUID
    post_id: UUID | None
    reason: str

    def as_audit_record(self) -> dict[str, object]:
        return {
            "cat_id": str(self.cat_id),
            "source_post_id": str(self.post_id) if self.post_id else None,
            "excluded": self.reason,
        }


@dataclass(frozen=True, slots=True)
class Classification:
    eligible: list[RepairCandidate]
    excluded: list[ExcludedCat]


def _valid(latitude: float | None, longitude: float | None) -> bool:
    return (
        latitude is not None
        and longitude is not None
        and -90 <= latitude <= 90
        and -180 <= longitude <= 180
    )


def _classify_row(row) -> RepairCandidate | ExcludedCat:
    if row.post_id is None:
        return ExcludedCat(row.cat_id, None, "no_originating_post")
    if row.origin_matches != 1:
        return ExcludedCat(row.cat_id, None, "multiple_originating_posts")
    if row.post_deleted:
        return ExcludedCat(row.cat_id, row.post_id, "originating_post_deleted")

    if row.has_history:
        if row.earliest_rows != 1 or not row.history_has_location_key:
            return ExcludedCat(row.cat_id, row.post_id, "original_location_ambiguous")
        if row.history_location_type == "null":
            return ExcludedCat(row.cat_id, row.post_id, "no_original_location")
        if (
            row.history_location_type != "object"
            or row.history_latitude_type != "number"
            or row.history_longitude_type != "number"
            or not _valid(row.history_latitude, row.history_longitude)
        ):
            return ExcludedCat(row.cat_id, row.post_id, "original_location_ambiguous")
        latitude, longitude = float(row.history_latitude), float(row.history_longitude)
    else:
        if row.current_latitude is None or row.current_longitude is None:
            return ExcludedCat(row.cat_id, row.post_id, "no_original_location")
        latitude, longitude = float(row.current_latitude), float(row.current_longitude)

    if row.current_latitude is None or row.current_longitude is None:
        return ExcludedCat(row.cat_id, row.post_id, "location_removed_by_owner")
    edited = (latitude, longitude) != (
        float(row.current_latitude),
        float(row.current_longitude),
    )
    return RepairCandidate(
        cat_id=row.cat_id,
        post_id=row.post_id,
        latitude=latitude,
        longitude=longitude,
        location_edited=edited,
    )


def classify(connection: Connection, *, skip_edited_locations: bool = False) -> Classification:
    eligible: list[RepairCandidate] = []
    excluded: list[ExcludedCat] = []
    seen: set[UUID] = set()
    for row in connection.execute(text(_CLASSIFY_SQL)).all():
        if row.cat_id in seen:  # several originating posts: one line per cat
            continue
        seen.add(row.cat_id)
        result = _classify_row(row)
        if isinstance(result, RepairCandidate) and skip_edited_locations:
            if result.location_edited:
                result = ExcludedCat(result.cat_id, result.post_id, "location_edited_skipped")
        (eligible if isinstance(result, RepairCandidate) else excluded).append(result)
    return Classification(eligible=eligible, excluded=excluded)


def find_candidates(
    connection: Connection, *, limit: int = 500, skip_edited_locations: bool = False
) -> list[RepairCandidate]:
    return classify(connection, skip_edited_locations=skip_edited_locations).eligible[:limit]


def apply_repairs(
    connection: Connection, candidates: Sequence[RepairCandidate]
) -> list[RepairCandidate]:
    """Apply the repair; returns only the rows actually changed.

    Each UPDATE re-checks the conditions, so a cat that gained a canonical
    location (or whose post was deleted or lost its point) after selection
    is skipped.
    """
    repaired: list[RepairCandidate] = []
    for candidate in candidates:
        result = connection.execute(
            text(_REPAIR_SQL),
            {
                "cat_id": candidate.cat_id,
                "post_id": candidate.post_id,
                "latitude": candidate.latitude,
                "longitude": candidate.longitude,
            },
        )
        if result.rowcount == 1:
            repaired.append(candidate)
    return repaired


def _parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument(
        "--database-url",
        default=os.getenv("DATABASE_URL"),
        help="SQLAlchemy URL; defaults to $DATABASE_URL.",
    )
    parser.add_argument("--limit", type=int, default=500, help="Maximum cats per run.")
    parser.add_argument("--apply", action="store_true", help="Write the repair (default: dry run).")
    parser.add_argument(
        "--confirm-database",
        help="Required with --apply: the name of the database being changed.",
    )
    parser.add_argument(
        "--skip-edited-locations",
        action="store_true",
        help="Exclude cats whose originating post location changed after creation.",
    )
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = _parse_args(argv)
    if not args.database_url:
        print("DATABASE_URL or --database-url is required.", file=sys.stderr)
        return 2
    if not 1 <= args.limit <= 5000:
        print("--limit must be between 1 and 5000.", file=sys.stderr)
        return 2

    engine = create_engine(args.database_url)
    try:
        with engine.begin() as connection:
            database_name = connection.execute(text("SELECT current_database()")).scalar_one()
            if args.apply and args.confirm_database != database_name:
                print(
                    f"Refusing to write: --confirm-database must equal '{database_name}'.",
                    file=sys.stderr,
                )
                return 2
            classification = classify(connection, skip_edited_locations=args.skip_edited_locations)
            candidates = classification.eligible[: args.limit]
            if not args.apply:
                for candidate in candidates:
                    print(json.dumps(candidate.as_audit_record(applied=False)))
                for excluded in classification.excluded:
                    print(json.dumps(excluded.as_audit_record()))
                print(
                    f"dry run in '{database_name}': {len(classification.eligible)} eligible "
                    f"(showing {len(candidates)}), {len(classification.excluded)} excluded; "
                    "nothing written.",
                    file=sys.stderr,
                )
                return 0
            repaired = apply_repairs(connection, candidates)
            for candidate in repaired:
                print(json.dumps(candidate.as_audit_record(applied=True)))
            print(
                f"applied: {len(repaired)} of {len(candidates)} candidate(s) in '{database_name}'.",
                file=sys.stderr,
            )
            return 0
    finally:
        engine.dispose()


if __name__ == "__main__":
    raise SystemExit(main())
