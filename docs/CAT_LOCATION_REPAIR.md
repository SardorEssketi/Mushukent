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

Rule, per cat. A cat is *eligible* only if every condition holds; otherwise the dry run lists
it as *excluded* with the reason in brackets and the script never changes it:

- `canonical_location IS NULL`, not deleted, not merged;
- exactly one *originating* post: created in the same transaction as the cat (identical
  `created_at`, both from the transaction's `now()`) by the cat's creator
  (`no_originating_post`, `multiple_originating_posts`);
- that post is not deleted (`originating_post_deleted`);
- its **original** creation location is known unambiguously. Post editing and `post_history`
  were introduced together, and every effective edit writes a `before`/`after` snapshot in the
  same transaction (the only code path that changes `posts.location`). So with no history row
  the current location is the creation location; otherwise the earliest history row's
  `before.location` is. A tie for the earliest row, a missing `location` key or non-numeric or
  out-of-range coordinates give `original_location_ambiguous`; an original without a point
  gives `no_original_location`;
- the post still has a location (`location_removed_by_owner`: a point the owner removed is
  not published again).

An eligible cat gets the originating post's original coordinates: exactly what the fixed
creation path stores. `location_edited: true` in the output marks posts moved after creation;
`--skip-edited-locations` excludes them (`location_edited_skipped`). Nothing else changes: no
other post is consulted, existing canonical locations are never overwritten, ownership, history
and counters are untouched. Each UPDATE re-checks the conditions, so the script is idempotent and
safe to re-run.

Procedure (after the fixed backend is deployed and a verified backup exists, `docs/BACKUP.md`):

1. Dry run (writes nothing; one JSON line per eligible cat with `cat_id`, `source_post_id`,
   coordinates and `location_edited`, and per excluded cat with its reason; counts on stderr):
   `python scripts/repair_cat_canonical_location.py --database-url <url>`
2. Record the counts in the gitignored `docs/private/PRODUCTION_STATE.md`, not here.
3. Apply, with the owner's approval for that run:
   `python scripts/repair_cat_canonical_location.py --database-url <url> --apply --confirm-database <db name>`
   (at most `--limit`, default 500, cats per run; repeat until the dry run reports 0 eligible).
   Keep the printed JSON lines as the audit record.

Rollback: set `canonical_location = NULL` for the `cat_id`s in the audit record.

Owner decisions still open: the rule covers every post kind (named ordinary observations were
equally hidden from the Map), not only Needs Help; and whether posts moved after creation are
repaired at their original point (default) or skipped (`--skip-edited-locations`).

## Related, not covered: location added by a later edit

Post edits never update the cat (unchanged behaviour). A post created without a location
(allowed for ordinary observations), then edited into Needs Help with a location, keeps a cat
with a NULL canonical location and stays off the Map, named or unnamed. This is a different root
cause from AUTH-205 (the edit path, not creation), it is not fixed here, and the repair reports
such cats as `no_original_location`. It needs a separate owner decision.
