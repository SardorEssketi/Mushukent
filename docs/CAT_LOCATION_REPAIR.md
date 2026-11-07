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

Policy (owner-approved 2026-11-07): cover every post kind linked to a cat; never repair a post
whose location changed after creation; never overwrite a canonical location; exclude anything
ambiguous; auditable dry run.

Rule, per cat. A cat is *eligible* only if every condition holds; otherwise the dry run lists
it as *excluded* with the reason in brackets and the script never changes it:

- `canonical_location IS NULL`, not deleted, not merged;
- exactly one *originating* post: created in the same transaction as the cat (identical
  `created_at`, both from the transaction's `now()`) by the cat's creator
  (`no_originating_post`, `multiple_originating_posts`);
- that post is not deleted (`originating_post_deleted`);
- its edit history is **provably complete** (`edit_history_incomplete` otherwise). Missing
  history is never taken to mean "never edited", because `post_history` only exists since
  migration 0017 and older rows have none. Completeness is accepted only on database evidence:
  - the post was created at or after the earliest `post_history` row in the database (history
    logging was live when it was created; editing and history shipped together in aa7ca9a, and
    every effective edit writes its snapshot in the same transaction), or
  - the row was never updated at all (`updated_at = created_at`; edits and like/comment
    counter updates all move `updated_at`);
- no history row records a location change, including a location added or removed by an edit
  (`location_changed_after_creation`), even if it was later moved back;
- every history snapshot has a well-formed location equal to the post's current point
  (`original_location_ambiguous`);
- the post has a location (`no_original_location`: created unlocated).

An eligible cat gets the originating post's location, which these rules prove is its unchanged
creation location: exactly what the fixed creation path stores. Nothing else changes: no other
post is consulted, existing canonical locations are never overwritten, ownership, history and
counters are untouched. Each UPDATE re-checks the conditions, including the post's coordinates,
so the script is idempotent and safe to re-run.

Excluded cats are not lost: the dry run prints each with its reason. `edit_history_incomplete`
and `location_changed_after_creation` records need a separate, manual owner review.

Procedure (after the fixed backend is deployed and a verified backup exists, `docs/BACKUP.md`):

1. Dry run (writes nothing; one JSON line per eligible cat with `cat_id`, `source_post_id` and
   coordinates, and per excluded cat with its reason; counts on stderr):
   `python scripts/repair_cat_canonical_location.py --database-url <url>`
2. Record the counts in the gitignored `docs/private/PRODUCTION_STATE.md`, not here.
3. Apply, with the owner's approval for that run:
   `python scripts/repair_cat_canonical_location.py --database-url <url> --apply --confirm-database <db name>`
   (at most `--limit`, default 500, cats per run; repeat until the dry run reports 0 eligible).
   Keep the printed JSON lines as the audit record.

Rollback: set `canonical_location = NULL` for the `cat_id`s in the audit record.

## Related, not covered: location added by a later edit

Post edits never update the cat (unchanged behaviour). A post created without a location
(allowed for ordinary observations), then edited into Needs Help with a location, keeps a cat
with a NULL canonical location and stays off the Map, named or unnamed. This is a different root
cause from AUTH-205 (the edit path, not creation), it is not fixed here, and the repair reports
such cats as `no_original_location`. It needs a separate owner decision.
