"""Repair cats left without a canonical location by AUTH-205.

Before the fix, ``POST /posts`` with ``new_cat`` that had a name but no
``canonical_location`` (what the mobile client sends) created the cat with a
NULL canonical location, even though the publication itself had a point. The
map (``GET /cats?bbox=...``) only uses ``cats.canonical_location``, so such
cats never appeared there.

Repair policy (owner-approved): cover every post kind linked to a cat, never
repair a post whose location changed after creation, never overwrite a
canonical location, exclude anything ambiguous, and produce an auditable dry
run. A cat is *eligible* only when every condition below holds; otherwise it
is reported as *excluded* with a reason and left unchanged:

* the cat has ``canonical_location IS NULL`` and is not deleted or merged;
* exactly one *originating* post exists: created in the same transaction as
  the cat (same ``created_at``, both from the transaction's ``now()``) by the
  cat's creator (``no_originating_post`` / ``multiple_originating_posts``);
* that post is not deleted (``originating_post_deleted``);
* the post's edit history is provably complete. Missing history is not
  taken to mean "never edited". Completeness is proven only by database
  evidence: the post was created at or after the earliest ``post_history``
  row in the database (history logging was already live when it was
  created), or the row was never updated at all (``updated_at =
  created_at``; any edit or counter update moves ``updated_at``). Otherwise
  ``edit_history_incomplete``: listed for separate review;
* no history row records a location change (``location_changed_after_creation``,
  which includes a location removed or added by an edit), and every history
  snapshot has a well-formed location equal to the current one
  (``original_location_ambiguous``);
* the post has a location (``no_original_location``: created unlocated).

An eligible cat gets its originating post's location, which by the rules
above is its unchanged creation location: exactly what the fixed creation
path stores. No other column, post or cat is touched and an existing
canonical location is never overwritten.

Dry run by default: prints one JSON line per eligible and excluded cat and
writes nothing. ``--apply`` also requires ``--confirm-database`` to equal the
connected database name; each repaired row is printed as one JSON line for
the audit record. Do not run against any persistent database without the
owner's approval for that run (docs/CAT_LOCATION_REPAIR.md).
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
WITH history_epoch AS (
    SELECT min(created_at) AS first_history_at FROM post_history
),
unlocated AS (
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
           p.created_at AS post_created_at,
           p.updated_at AS post_updated_at,
           ST_Y(p.location) AS latitude,
           ST_X(p.location) AS longitude,
           count(*) OVER (PARTITION BY u.cat_id) AS origin_matches
    FROM unlocated u
    JOIN posts p
      ON p.cat_id = u.cat_id
     AND p.created_at = u.created_at
     AND p.user_id IS NOT DISTINCT FROM u.created_by
),
history_summary AS (
    SELECT h.post_id,
           count(*) AS history_rows,
           bool_or(NOT (h.before ? 'location') OR NOT (h.after ? 'location'))
               AS missing_location_key,
           bool_or(h.before -> 'location' IS DISTINCT FROM h.after -> 'location')
               AS location_changed
    FROM post_history h
    WHERE h.post_id IN (SELECT post_id FROM origin)
    GROUP BY h.post_id
)
SELECT u.cat_id,
       o.post_id,
       o.origin_matches,
       o.post_deleted_at IS NOT NULL AS post_deleted,
       o.latitude,
       o.longitude,
       coalesce(hs.history_rows, 0) AS history_rows,
       coalesce(hs.missing_location_key, false) AS missing_location_key,
       coalesce(hs.location_changed, false) AS location_changed,
       (
           (e.first_history_at IS NOT NULL AND o.post_created_at >= e.first_history_at)
           OR (hs.post_id IS NULL AND o.post_updated_at = o.post_created_at)
       ) AS history_complete
FROM unlocated u
CROSS JOIN history_epoch e
LEFT JOIN origin o ON o.cat_id = u.cat_id
LEFT JOIN history_summary hs ON hs.post_id = o.post_id
ORDER BY u.cat_id, o.post_id
"""

# Every snapshot of an eligible post must hold the current location; checked
# separately so a malformed or diverging snapshot is never trusted.
_SNAPSHOTS_MATCH_SQL = """
SELECT bool_and(
    coalesce(
        jsonb_typeof(h.before -> 'location' -> 'latitude') = 'number'
        AND jsonb_typeof(h.before -> 'location' -> 'longitude') = 'number'
        AND (h.before -> 'location' ->> 'latitude')::double precision = :latitude
        AND (h.before -> 'location' ->> 'longitude')::double precision = :longitude,
        false
    )
) AS all_match
FROM post_history h
WHERE h.post_id = :post_id
"""

_REPAIR_SQL = """
UPDATE cats c
SET canonical_location = p.location
FROM posts p
WHERE c.id = :cat_id
  AND p.id = :post_id
  AND p.cat_id = c.id
  AND p.deleted_at IS NULL
  AND p.location IS NOT NULL
  AND ST_Y(p.location) = :latitude
  AND ST_X(p.location) = :longitude
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

    def as_audit_record(self, *, applied: bool) -> dict[str, object]:
        return {
            "cat_id": str(self.cat_id),
            "source_post_id": str(self.post_id),
            "latitude": self.latitude,
            "longitude": self.longitude,
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


def _classify_row(connection: Connection, row) -> RepairCandidate | ExcludedCat:
    if row.post_id is None:
        return ExcludedCat(row.cat_id, None, "no_originating_post")
    if row.origin_matches != 1:
        return ExcludedCat(row.cat_id, None, "multiple_originating_posts")
    if row.post_deleted:
        return ExcludedCat(row.cat_id, row.post_id, "originating_post_deleted")
    if not row.history_complete:
        return ExcludedCat(row.cat_id, row.post_id, "edit_history_incomplete")
    if row.missing_location_key:
        return ExcludedCat(row.cat_id, row.post_id, "original_location_ambiguous")
    if row.location_changed:
        return ExcludedCat(row.cat_id, row.post_id, "location_changed_after_creation")
    if row.latitude is None or row.longitude is None:
        return ExcludedCat(row.cat_id, row.post_id, "no_original_location")

    latitude, longitude = float(row.latitude), float(row.longitude)
    if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
        return ExcludedCat(row.cat_id, row.post_id, "original_location_ambiguous")
    if row.history_rows:
        all_match = connection.execute(
            text(_SNAPSHOTS_MATCH_SQL),
            {"post_id": row.post_id, "latitude": latitude, "longitude": longitude},
        ).scalar_one()
        if all_match is not True:
            return ExcludedCat(row.cat_id, row.post_id, "original_location_ambiguous")
    return RepairCandidate(
        cat_id=row.cat_id, post_id=row.post_id, latitude=latitude, longitude=longitude
    )


def classify(connection: Connection) -> Classification:
    eligible: list[RepairCandidate] = []
    excluded: list[ExcludedCat] = []
    seen: set[UUID] = set()
    for row in connection.execute(text(_CLASSIFY_SQL)).all():
        if row.cat_id in seen:  # several originating posts: one line per cat
            continue
        seen.add(row.cat_id)
        result = _classify_row(connection, row)
        (eligible if isinstance(result, RepairCandidate) else excluded).append(result)
    return Classification(eligible=eligible, excluded=excluded)


def find_candidates(connection: Connection, *, limit: int = 500) -> list[RepairCandidate]:
    return classify(connection).eligible[:limit]


def apply_repairs(
    connection: Connection, candidates: Sequence[RepairCandidate]
) -> list[RepairCandidate]:
    """Apply the repair; returns only the rows actually changed.

    Each UPDATE re-checks the conditions, including that the post still has
    the classified coordinates, so a cat that gained a canonical location or
    a post that was deleted or moved after selection is skipped.
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
            classification = classify(connection)
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
