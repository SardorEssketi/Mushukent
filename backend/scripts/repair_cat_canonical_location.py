"""Repair cats left without a canonical location by AUTH-205.

Before the fix, ``POST /posts`` with ``new_cat`` that had a name but no
``canonical_location`` (what the mobile client sends) created the cat with a
NULL canonical location, even though the publication itself had a point. The
map (``GET /cats?bbox=...``) only uses ``cats.canonical_location``, so such
cats never appeared there.

Repair rule (deterministic, conservative, idempotent):

* the cat has ``canonical_location IS NULL`` and is not deleted or merged;
* its *originating* publication is the post created in the same transaction
  as the cat: same ``created_at`` (both use the transaction's ``now()``) and
  ``posts.user_id = cats.created_by``; if more than one post matches, the cat
  is skipped as ambiguous;
* that post is not deleted and has a location.

The cat's canonical location is set to that post's current location. No other
column is touched, no other post is consulted and existing canonical
locations are never changed. Cats created through ``POST /cats`` without a
location, or whose originating post has no location or was deleted, are left
as they are.

Dry run by default: lists the candidates and writes nothing. ``--apply``
also requires ``--confirm-database`` to equal the connected database name.
Every repaired row is printed as one JSON line (cat id, source post id,
coordinates) for the audit record. Do not run against production without the
owner's approval for that run (docs/DEPLOYMENT.md).
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

_CANDIDATES_SQL = """
WITH origin AS (
    SELECT c.id AS cat_id,
           p.id AS post_id,
           p.location,
           p.deleted_at AS post_deleted_at,
           count(*) OVER (PARTITION BY c.id) AS origin_matches
    FROM cats c
    JOIN posts p
      ON p.cat_id = c.id
     AND p.created_at = c.created_at
     AND p.user_id IS NOT DISTINCT FROM c.created_by
    WHERE c.canonical_location IS NULL
      AND c.deleted_at IS NULL
      AND c.merged_into IS NULL
)
SELECT o.cat_id,
       o.post_id,
       ST_Y(o.location) AS latitude,
       ST_X(o.location) AS longitude
FROM origin o
WHERE o.origin_matches = 1
  AND o.post_deleted_at IS NULL
  AND o.location IS NOT NULL
ORDER BY o.cat_id
LIMIT :limit
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


def find_candidates(connection: Connection, *, limit: int = 500) -> list[RepairCandidate]:
    rows = connection.execute(text(_CANDIDATES_SQL), {"limit": limit}).all()
    return [
        RepairCandidate(
            cat_id=row.cat_id,
            post_id=row.post_id,
            latitude=float(row.latitude),
            longitude=float(row.longitude),
        )
        for row in rows
    ]


def apply_repairs(
    connection: Connection, candidates: Sequence[RepairCandidate]
) -> list[RepairCandidate]:
    """Apply the repair; returns only the rows actually changed.

    Each UPDATE re-checks the conditions, so a cat that gained a canonical
    location (or whose post was deleted) after ``find_candidates`` is skipped.
    """
    repaired: list[RepairCandidate] = []
    for candidate in candidates:
        result = connection.execute(
            text(_REPAIR_SQL),
            {"cat_id": candidate.cat_id, "post_id": candidate.post_id},
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
            candidates = find_candidates(connection, limit=args.limit)
            if not args.apply:
                for candidate in candidates:
                    print(json.dumps(candidate.as_audit_record(applied=False)))
                print(
                    f"dry run: {len(candidates)} candidate(s) in '{database_name}'; "
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
