# Comment counts

Status: implemented on branch `fix/comment-count-visibility` (Batch 1, issue #6).

## Bug

A publication card showed "1 comment" while the comment list was empty.

Two causes, both confirmed in the code on `main` at 82e97f2:

1. **Account deletion** (`UsersService.delete_me`, `backend/app/features/users/application/service.py`)
   soft-deleted and anonymized every comment of the account but never lowered the stored
   `comment_count` of the posts, lost-pet posts and adoption posts those comments were on.
   The comment lists hide soft-deleted comments, so the card kept counting them.
2. **Blocking.** Comment lists hide comments whose author has a block with the viewer in either
   direction (`exclude_blocked`), but every publication response returned the stored, global
   `comment_count`. `docs/BLOCKING.md` listed this as a known limit.

Normal comment creation, author deletion, moderator deletion (`DELETE /comments/{id}`) and the
report action `soft_delete_comment` already updated the stored counters atomically (`UPDATE ...
SET comment_count = comment_count +/- 1` in the same transaction, the comment row locked and
`mark_deleted` guarded by `deleted_at IS NULL`, so no double decrement).

## Rule

The `comment_count` returned with a publication is the number of comments the same viewer gets from
that publication's full comment list (all pages, top-level comments and replies). See
`docs/BLOCKING.md`, "Comment counts", and
`backend/app/infrastructure/repositories/comment_visibility.py`.

## Implementation

- `comment_visibility.py` holds the one visibility predicate (`apply_comment_visibility`: not
  soft-deleted, no block in either direction, anonymous viewers unaffected) and two ways to count
  with it: a correlated count column for SQL-built rows (posts, Needs Help posts, cat history) and a
  grouped count for a page of ORM-loaded lost-pet and adoption posts.
- The three comment-list queries use the same predicate.
- `delete_me` soft-deletes the account's still-active comments with one
  `UPDATE ... RETURNING` (only those rows are counted, so already-deleted comments are never
  decremented again and a concurrent delete of the same comment cannot double count), anonymizes
  the already-deleted ones, and lowers each table's stored counters in one `UPDATE ... FROM
  (VALUES ...)` per table, all in the existing account-deletion transaction.
- **Lock order.** Every path that changes a stored `comment_count` locks the publication row
  before the comment row: comment deletion by author or moderator and the report action
  `soft_delete_comment` (`lock_comment_target`), and account deletion, which first locks every
  publication it will update (its own, the ones it commented on and the posts it liked) table by
  table in id order (`_lock_affected_publications`). Two accounts with comments on each other's
  publications deleted at the same time deadlocked in every local test round without this; with it
  they wait for each other. If anything still fails, the whole deletion rolls back (one
  transaction; media files are only removed after commit), so a failure never leaves a partial
  deletion or a wrong counter (verified locally on deliberately deadlocked deletions).
- No schema change and no migration. The existing indexes `idx_comments_post_id`,
  `idx_comments_lost_pet_id`, `idx_comments_adoption_post_id` and the `user_blocks` indexes serve
  the counts.

## Query cost (measured locally)

On a disposable local PostGIS 15 container (`postgis/postgis:15-3.4`) seeded with 50,000 posts,
200,000 comments and a viewer with 100 blocks, `EXPLAIN ANALYZE` of the real repository queries
(page of 20):

| Query | Before | After |
|---|---|---|
| recent feed, signed-in viewer | 0.45-0.50 ms | 0.92-1.01 ms |
| recent feed, anonymous | 0.23-0.27 ms | 0.37-0.49 ms |
| popular feed, all time | 106-108 ms | 107 ms |
| grouped count, 20 publications | - | 0.14-0.18 ms |

With one post of 20,000 comments added on the first page, the anonymous recent feed took 3.6 ms
and the grouped count for 20 publications 7.6 ms: the cost grows with the number of comments on
the publications of the page, not with the table size. A covering partial index on
`comments (post_id, user_id) WHERE deleted_at IS NULL` would make this index-only if publications
with very many comments become common; it needs a migration and is not part of this change.

The count subplan ran 21 times (page + 1 look-ahead row), never per scanned row. The popular feed
cost is the existing sequential scan and existing per-row subplans, unchanged by this fix. These are
local measurements, not production figures.

## Existing data: reconciliation (optional, operator-run)

**Required for correctness? No.** No API response reads the stored `comment_count` columns any more,
so counters that drifted because of the old account-deletion bug are invisible to users once the
backend is deployed. The only remaining readers are two internal row-lock queries used to authorize
comment and like writes (`lock_visible_post` in the comments and likes repositories); they do not
return the value to clients.

Reconciling still makes the stored columns truthful again (useful for future features, analytics or
a later switch back to the stored value). It is a separate, manual step: it is not run by the
application, the deployment scripts or any Alembic migration, and nobody has run it against
production.

### Source of truth

For each publication: the number of rows in `comments` with that target and `deleted_at IS NULL`.
This is the global (viewer-independent) meaning the stored columns have always had.

### Affected tables

`posts.comment_count`, `lost_pets.comment_count`, `adoption_posts.comment_count`.

### Procedure

Prerequisites: the fixed backend is deployed first (so no new drift is created), a fresh verified
backup exists (`docs/BACKUP.md`), and the owner approves the write step for that run.

1. **Measure (read-only).** Run on a read-only session; it writes nothing:

   ```sql
   SELECT 'posts' AS table_name, count(*) AS drifted_rows,
          coalesce(sum(p.comment_count - coalesce(a.n, 0)), 0) AS net_stored_minus_actual
   FROM posts p
   LEFT JOIN (SELECT post_id, count(*) AS n FROM comments
              WHERE post_id IS NOT NULL AND deleted_at IS NULL GROUP BY post_id) a
          ON a.post_id = p.id
   WHERE p.comment_count <> coalesce(a.n, 0)
   UNION ALL
   SELECT 'lost_pets', count(*), coalesce(sum(l.comment_count - coalesce(a.n, 0)), 0)
   FROM lost_pets l
   LEFT JOIN (SELECT lost_pet_id, count(*) AS n FROM comments
              WHERE lost_pet_id IS NOT NULL AND deleted_at IS NULL GROUP BY lost_pet_id) a
          ON a.lost_pet_id = l.id
   WHERE l.comment_count <> coalesce(a.n, 0)
   UNION ALL
   SELECT 'adoption_posts', count(*), coalesce(sum(d.comment_count - coalesce(a.n, 0)), 0)
   FROM adoption_posts d
   LEFT JOIN (SELECT adoption_post_id, count(*) AS n FROM comments
              WHERE adoption_post_id IS NOT NULL AND deleted_at IS NULL
              GROUP BY adoption_post_id) a
          ON a.adoption_post_id = d.id
   WHERE d.comment_count <> coalesce(a.n, 0);
   ```

   Record the result in the gitignored `docs/private/PRODUCTION_STATE.md` (not in this public
   repository). Also measure how long the query takes; its duration on production is unknown.
   If every `drifted_rows` is 0, stop.

2. **Dry run.** Run one batch below with `ROLLBACK` instead of `COMMIT` and check the reported row
   count is at most 500 and matches the measurement.

3. **Correct, in small batches.** One batch per table (shown for `posts`; for the other tables
   replace `posts` with `lost_pets` / `adoption_posts` and `post_id` with `lost_pet_id` /
   `adoption_post_id`). Repeat each until it reports `UPDATE 0`.

   ```sql
   BEGIN ISOLATION LEVEL REPEATABLE READ;
   SET LOCAL lock_timeout = '2s';
   SET LOCAL statement_timeout = '30s';
   WITH drifted AS (
       SELECT p.id, coalesce(a.n, 0) AS actual
       FROM posts p
       LEFT JOIN (SELECT post_id, count(*) AS n FROM comments
                  WHERE post_id IS NOT NULL AND deleted_at IS NULL GROUP BY post_id) a
              ON a.post_id = p.id
       WHERE p.comment_count <> coalesce(a.n, 0)
       ORDER BY p.id
       LIMIT 500
   )
   UPDATE posts p SET comment_count = d.actual
   FROM drifted d
   WHERE p.id = d.id AND p.comment_count <> d.actual;
   COMMIT;
   ```

   Why it is safe while the app is running:
   - It only writes rows that differ and only sets them to the recomputed truth, so re-running it
     is harmless (idempotent).
   - Each batch locks at most 500 publication rows for one short transaction; there is no table
     lock. `lock_timeout` makes it give up rather than queue behind user traffic.
   - `REPEATABLE READ`: if a comment is created or deleted on one of those publications after the
     batch took its snapshot, that request also updates the publication row, and PostgreSQL aborts
     the batch with SQLSTATE `40001` ("could not serialize access") instead of writing a stale
     value. Just run the batch again.

4. **Verify.** Run step 1 again: every `drifted_rows` must be 0. Spot-check a few publications in
   the app (card count, detail count and comment list agree, signed in and signed out).

### Rollback / recovery

The correction only changes the three counter columns, which no API response reads. If a batch
needs undoing, restore those columns from the pre-run backup, or simply re-run step 3 (it always
converges to the recomputed truth). Nothing else is touched.

### Tested

Against a disposable local PostGIS database with deliberately drifted counters (too high and too
low, with soft-deleted comments present): the measurement found the drift, the dry run rolled back,
batches converged (500, 100, 0), the re-measurement showed 0 drifted rows in all three tables and a
re-run updated 0 rows. Not run against production.
