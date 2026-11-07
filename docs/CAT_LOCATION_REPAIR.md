# Cat canonical location repair (AUTH-205)

## Defect

`GET /cats?bbox=...` (the Map) and `filter=nearby` select cats by `cats.canonical_location`
only. Before the fix, `POST /posts` with a `new_cat` that had a name but no
`canonical_location` (what the mobile client sends) stored the cat with a NULL canonical
location although the publication had a valid point. Named Needs Help (and named ordinary)
publications therefore never appeared on the Map. Unnamed publications were not affected.

The fix makes a new cat fall back to the publication `location` when `new_cat` has no
explicit `canonical_location` (`PostService._resolve_cat_for_create`). An explicit
`canonical_location` still wins; publications without a location still create an unlocated
cat. Post edits do not move the cat, as before.

## Existing data: repair (operator-run, owner approval required)

Records created before the fix stay invisible on the Map until repaired. The repair is a
separate, manual step: it is not an Alembic migration, the application and deployment scripts
never run it, and it has not been run against any persistent database.

Script: `backend/scripts/repair_cat_canonical_location.py` (tests:
`backend/tests/test_cat_location_repair.py`).

Rule, per cat:

- `canonical_location IS NULL`, not deleted, not merged;
- exactly one *originating* post: created in the same transaction as the cat (identical
  `created_at`, both from the transaction's `now()`) by the cat's creator;
- that post is not deleted and has a location.

The cat's `canonical_location` becomes that post's current location. Nothing else changes: no
other post is consulted, existing canonical locations are never overwritten, ownership,
history and counters are untouched. Cats created through `POST /cats` without a location, or
whose originating post was deleted or has no point, are left NULL. Each UPDATE re-checks the
conditions, so the script is idempotent and safe to re-run.

Procedure (after the fixed backend is deployed and a verified backup exists, `docs/BACKUP.md`):

1. Dry run (writes nothing; prints one JSON line per candidate with `cat_id`,
   `source_post_id`, coordinates):
   `python scripts/repair_cat_canonical_location.py --database-url <url>`
2. Record the candidate count in the gitignored `docs/private/PRODUCTION_STATE.md`, not here.
3. Apply, with the owner's approval for that run:
   `python scripts/repair_cat_canonical_location.py --database-url <url> --apply --confirm-database <db name>`
   (at most `--limit`, default 500, cats per run; repeat until the dry run reports 0). Keep the
   printed JSON lines as the audit record.

Rollback: set `canonical_location = NULL` for the `cat_id`s in the audit record.

Owner decisions still open: the rule covers every post kind (named ordinary observations were
equally hidden from the Map), not only Needs Help; and it uses the originating post's current
location, which reflects later owner edits of that post.
