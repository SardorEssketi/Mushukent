# Proposed fixes (not applied)

Companion to `REPORT.md`. These are proposals for review. Nothing here has been applied to
application code, migrations or production configuration. Where a gain is quoted it was measured
on the emulated host with the query shape shown (`loadtest/tools/query_experiments.sql`). Gains
for code changes that were not built and run are labelled **estimate**.

Order = recommended order of work (see REPORT.md section 7).

---

## FIX-1 Fail fast instead of piling up (LT-02, LT-18): statement and pool timeouts

Today: no `statement_timeout`, and the SQLAlchemy pool waits 30 s for a connection. Under overload,
queries keep running for minutes after the client left, all 15 connections stay busy, and every
other request waits 30 s and then gets a 500. Proposal: bound the work per request and shed load
early with a 503 the client can show.

```diff
--- a/backend/app/infrastructure/db/session.py
+++ b/backend/app/infrastructure/db/session.py
@@ class DatabaseSessionManager:
     def __init__(self, database_url: str) -> None:
-        self.engine = create_engine(database_url, pool_pre_ping=True)
+        self.engine = create_engine(
+            database_url,
+            pool_pre_ping=True,
+            pool_size=5,
+            max_overflow=10,
+            # Wait at most 3 s for a connection; beyond that the box is saturated and a quick
+            # 503 is better than a 30 s wait followed by a 500.
+            pool_timeout=3,
+            connect_args={
+                # Server-side guards: a request never holds a backend for minutes.
+                "options": "-c statement_timeout=8000 -c lock_timeout=3000"
+                " -c idle_in_transaction_session_timeout=15000",
+            },
+        )
```

Plus an error handler that maps `sqlalchemy.exc.TimeoutError` (pool) and
`psycopg.errors.QueryCanceled` (statement timeout) to `503 SERVICE_BUSY` with `Retry-After: 5`.
Migrations (`alembic/env.py`) use their own engine and keep running without these limits. The
publication flow already treats an unknown commit outcome explicitly
(`CommitOutcomeUnknownError`); its tests should be re-run with the timeouts on.

nginx: `proxy_read_timeout 180s` on `/api/` lets a request sit for 3 minutes. Keep 180 s only for
the upload routes and use about 30 s elsewhere (infrastructure change; owner approval).

Effort S. Risk: an 8 s statement timeout will surface slow queries as 503s, so ship it after FIX-2.

## FIX-2 `nearby` feed: KNN on a geography index (LT-03)

Today's plan is fragile: `ST_DWithin(CAST(location AS geography), …)` is estimated at 3 rows
(actual 7,583), so the serial plan is a 10,065 × 7,583 nested loop. The parallel plan dodges it
only by luck. And even a good plan computes and sorts a distance for **every** post inside the
radius: 77,142 posts within 5 km of the centre at 10× data.

**The fix that scales (measured at 10×): nearest-first KNN.** Page 1 goes from **1,101 ms to 39 ms**
and page 10 takes **2 ms**; only the rows a page needs are read.

```sql
-- migration (CREATE INDEX CONCURRENTLY outside a transaction)
CREATE INDEX CONCURRENTLY idx_posts_location_geog_knn
  ON posts USING gist ((location::geography)) WHERE deleted_at IS NULL AND is_public;
CREATE INDEX CONCURRENTLY idx_lost_pets_location_geog_knn
  ON lost_pets USING gist ((last_seen_location::geography))
  WHERE deleted_at IS NULL AND is_public AND NOT is_resolved;
```

Query shape per branch: `ORDER BY location::geography <-> :point LIMIT :n` with **only** the
distance operator in that ORDER BY (an extra `, id` tie-break disables the index ordering), the
cursor as `location::geography <-> :point > :cursor_distance` (or equal with `id > :cursor_id`),
then `ST_DWithin(…, radius)` and the `(distance, created_at, type_rank, id)` tie-break in the outer
query. Use the same `<->` value for both the order and the cursor. It is a sphere distance (the
current `ST_Distance` is spheroid, ~0.3% different), so the cursor stays consistent. The partial
index predicates must match the query's `WHERE` exactly for the planner to use them. Effort M.

**Minimum patch if the migration has to wait (measured at 1× only):** a geometry `&&` box
prefilter fixes today's fragile plan (serial **7,767 ms → 69 ms**; 1 km radius 2 ms). It does
**not** scale: at 10× it measured 1,797 ms, because the box still contains every post in the radius.

```diff
--- a/backend/app/features/feed/infrastructure/repositories.py
+++ b/backend/app/features/feed/infrastructure/repositories.py
@@ def list_mixed_feed_keys(...):
         reference_geom = None
+        search_box = None
         if filter_by == "nearby":
             ...
             reference_geom = func.ST_SetSRID(func.ST_MakePoint(longitude, latitude), 4326)
+            # Geometry box around the point (degrees), so the GiST index on the geometry column
+            # is usable and the planner gets a sane row estimate. Longitude degrees shrink with
+            # latitude; the box is slightly larger than the circle, ST_DWithin below is exact.
+            dlat = radius_meters / 110_574.0
+            dlon = radius_meters / (111_320.0 * max(math.cos(math.radians(latitude)), 0.01))
+            search_box = func.ST_Expand(reference_geom, dlon, dlat)
@@
         if reference_geom is not None:
             post_index = post_index.where(
                 schema.Post.location.is_not(None),
+                schema.Post.location.op("&&")(search_box),
                 func.ST_DWithin(
@@
         if reference_geom is not None:
             lost_pet_index = lost_pet_index.where(
+                schema.LostPet.last_seen_location.op("&&")(search_box),
                 func.ST_DWithin(
```

The same two-axis expansion fixes the cats `nearby` filter, which today expands by
`radius/111_320` on both axes and **misses 13% of the cats inside the radius** (LT-14,
`backend/app/features/cats/infrastructure/repositories.py:254-257`):

```diff
-                    func.ST_Expand(reference_geom, radius_meters / 111_320.0)
+                    func.ST_Expand(
+                        reference_geom,
+                        radius_meters / (111_320.0 * max(math.cos(math.radians(latitude)), 0.01)),
+                        radius_meters / 110_574.0,
+                    )
```

The two-axis expansion is needed regardless (correctness of the cats filter); the box prefilter
for the feed is only the stop-gap described above.

## FIX-3 `POST /views/seen`: one query per stage instead of ~4 per item (LT-05)

Today each item runs the full post-detail `get_by_id` (comment-count subquery, liked/saved/edited
`EXISTS`, then a separate photo query), an insert and an update. That's about 80 statements and
145–200 ms per batch of 20, which is ~40% of a feed user's server cost. Proposal (sketch):

```python
# views/application/service.py, record_seen(): replace the per-item loop
visible = repo.visible_targets(session, items, viewer)   # 1 query per kind:
#   SELECT id, user_id FROM posts p JOIN cats c ... WHERE p.id = ANY(:ids) AND <visibility>
#   AND NOT blocked_between(...)
rows = [(kind, pid) for (kind, pid), owner in visible.items() if counts_for(viewer, owner)]
created = session.execute(                              # 1 statement
    pg_insert(PostView).values([...]).on_conflict_do_nothing()
    .returning(PostView.post_kind, PostView.post_id)).all()
session.execute(text(                                   # 1 statement per kind
    "UPDATE posts SET view_count = view_count + 1 FROM unnest(:ids) AS t(id) "
    "WHERE posts.id = t.id RETURNING posts.id, posts.view_count"), {"ids": ids})
```

Keep the `(kind, id)` lock order (sort the ids) to stay deadlock-free. **Estimate:** 10–20 ms per
batch. Client side, consider flushing every 30 s instead of 10 s. The count is not time-critical.
Effort M.

## FIX-4 Map `GET /cats` bbox: index the LATERAL lookup (LT-04)

Measured SQL part at z14: **19.6 → 10.8 ms** with:

```sql
-- new Alembic migration (CONCURRENTLY outside a transaction)
CREATE INDEX CONCURRENTLY idx_posts_cat_public_recent
  ON posts (cat_id, created_at DESC, id DESC)
  WHERE deleted_at IS NULL AND is_public;
```

The rest of the 70–120 ms per pan is building and serialising up to 100 cats in Python. Larger
follow-ups that need a decision: keep `cats.latest_public_post_at/kind` denormalised (maintained on
post create/delete/moderation) so the query is a pure bbox index scan; and quantise the client
bbox to a tile grid so identical requests can be cached (by Cloudflare or in-process for 15–30 s).
Effort S (index) / M (denormalisation).

## FIX-5 `recent` mixed feed: limit each branch before the merge (LT-06)

Measured key query: **26 ms → 1.3 ms** (and it stops growing with the number of posts).

```diff
-        mixed_feed = union_all(*source_indexes).subquery("mixed_feed")
+        # Order and limit every branch by the same key the merge uses, so each branch is an
+        # index scan on the partial created_at index instead of a full scan + sort.
+        def bounded(branch, created_col, id_col):
+            if cursor is not None:
+                branch = branch.where(<the same timestamp_boundary on this branch's columns>)
+            return branch.order_by(created_col.desc(), id_col.desc()).limit(limit + 1)
+        mixed_feed = union_all(
+            bounded(post_index, schema.Post.created_at, schema.Post.id),
+            bounded(lost_pet_index, schema.LostPet.created_at, schema.LostPet.id),
+            ...
+        ).subquery("mixed_feed")
```

Pushing the cursor into each branch must keep the `(created_at, type_rank, id)` tie-break exactly;
`test_feed_map.py` covers the ordering. Separately, investigate why a signed-in first page costs
~80 ms more than a guest page (hydration with `is_liked_by_me`/`is_saved_by_me`/comment
visibility). Effort M.

## FIX-6 Uploads must not be able to kill the API (LT-10)

Two concurrent publications of 5 photos at ~25 MP OOM-killed the backend (exit 137). One account
can send 10 per minute. Each image is decoded at full size twice (`validate_upload` calls
`image.load()`, then `process_observation_image` decodes again) plus the EXIF-transpose copies.

```diff
--- a/backend/app/infrastructure/storage/images.py
+++ b/backend/app/infrastructure/storage/images.py
@@ def validate_upload(...):
-                image.load()
-                transposed: Image.Image = ImageOps.exif_transpose(image)
-                width, height = transposed.size
+                # Header-only validation: size and orientation come from the header/EXIF; the
+                # full decode happens once, in process_*.
+                image.verify()
+                width, height = _oriented_size(image)
@@ def process_observation_image(...):
         with Image.open(io.BytesIO(content)) as image:
+            if image.format == "JPEG":
+                # Decode at 1/2..1/8 scale straight from the JPEG: a 25 MP photo becomes
+                # ~1.6-6 MP in memory instead of ~75 MB RGB.
+                image.draft("RGB", (self.observation_longest_side * 2,) * 2)
             image.load()
```

And in `backend/app/api/v1/uploads.py`: `CapacityLimiter(2)` → `CapacityLimiter(1)` on a
single-core host (the work is CPU-bound anyway), plus a per-user "one publication in flight" guard
(409). Consider lowering `Image.MAX_IMAGE_PIXELS` to ~16 MP, since the client never sends more
than 1920 px. Re-run `loadtest/tools/upload_stress.py --concurrent 10 --files 5 --size max` to
validate. Effort M.

## FIX-7 Rate-limit buckets that work behind carrier NAT (LT-08, LT-09)

40 users behind one IP produced **15.5% 429s** (guests 36–57%), and 21% when tokens had expired.
Proposals (policy decision for the owner):

1. Count **read-only public GETs** in the public-read bucket, not the 30/min anonymous one:
   `/lost-pets/map`, `/lost-pets/{id}`, `/posts/{id}`, `/posts/{id}/comments`, `/cats/{id}`,
   `/cats/{id}/posts`, `/places/{id}`, `/adoption-posts/{id}` (`backend/app/core/rate_limit.py:176-183`).
2. Put view counting (`/views/seen`, `/…/{id}/views`) in its own generous bucket (it is telemetry;
   dropping it is harmless, and today it competes with real reads).
3. Raise the per-IP ceilings to CGNAT-tolerant values (e.g. public-read 600/min, anon 120/min per
   IP), keeping per-user limits for signed-in traffic; consider keying guests by IP + install id
   for reads (the install id is untrusted, so only for *raising* the per-IP ceiling, never alone).
4. Key `POST /auth/refresh` by the refresh session (a valid, unexpired refresh token) instead of
   by IP; keep login/register per IP.
5. Client: send the bearer token on the marker tap and places requests (`map_screen.dart:513-518`,
   `mushukistan_api.dart:87,107`) so signed-in users never spend the per-IP anonymous bucket;
   show a "too many requests, retrying in N s" state and honour `Retry-After` instead of the generic
   "Could not load this section" with an immediate Retry.

Effort S–M.

## FIX-8 Notification worker: one bad row must not stop every push (LT-12, LT-13)

```diff
--- a/backend/app/features/notifications/application/worker.py
+++ b/backend/app/features/notifications/application/worker.py
@@ def deliver(self, now: datetime) -> int:
         for job_id in self._claim(now):
-            with self.manager.session_scope() as session:
-                ...
-                token = self.cipher.decrypt(device.token_encrypted.encode()).decode()
+            try:
+                with self.manager.session_scope() as session:
+                    ...
+                    token = self.cipher.decrypt(device.token_encrypted.encode()).decode()
+            except Exception as exc:  # one job, not the whole pass
+                self._fail_job(job_id, type(exc).__name__)
+                logger.warning("notification_job_failed", job_id=str(job_id),
+                               error_type=type(exc).__name__)
+                continue
```

Throughput: `run_forever` delivers at most one claim of 50 per 30 s (~100 pushes/min). Loop
`deliver` while it returns a full batch (with a short sleep), so a backlog of a few thousand drains
in minutes rather than half an hour. Effort S.

## FIX-9 nginx: re-resolve the backend (LT-11)

`proxy_pass http://backend:8000;` resolves once at nginx start. After the backend container gets a
new IP (recreate, or restarts in a different order), every API call is a 502 until nginx is
reloaded (reproduced: 22,378 × 502). Infrastructure change (owner approval):

```diff
--- a/infrastructure/nginx/default.conf
+++ b/infrastructure/nginx/default.conf
+    resolver 127.0.0.11 valid=10s ipv6=off;
@@ location /api/ {
-        proxy_pass http://backend:8000;
+        set $backend_upstream http://backend:8000;
+        proxy_pass $backend_upstream;
```

(With a variable, `proxy_pass` keeps the request URI as is, which matches the current behaviour
for `location /api/` without a URI part.) Effort S.

## FIX-10 Postgres on a single core (LT-17), after FIX-2

`max_parallel_workers_per_gather = 0` in the production Compose `db` command. On one core a
parallel worker adds no CPU, but each one re-initialises PostGIS (a 0.4 ms scan took 1.1 s inside a
worker) and adds memory. **Do not apply before FIX-2**: with parallel query off, today's `nearby`
plan goes from ~1 s to 6–9 s. Effort S (infrastructure; approval).

## FIX-11 Popular feed index (F-21, LT-07)

```sql
CREATE INDEX CONCURRENTLY idx_posts_popular
  ON posts (like_count DESC, created_at DESC, id DESC)
  WHERE deleted_at IS NULL AND is_public;
```

23 ms sequential scan at 30k posts today; low priority until posts grow.

## Capacity (LT-01): needs an architecture/hosting decision

Even with FIX-2..5 the projection (estimate, not measured) is ~6 ms of CPU per active user per
second, i.e. ~110 users per core at 70% utilisation. 300 concurrent users need roughly 3 cores for
app + database, so one of:

* a 4 vCPU / 8 GB host for the same single-box layout; or
* the database on its own host or a managed Postgres (2 vCPU), the app box kept small; and then
* only after the database stops being the bottleneck: more uvicorn workers. This requires the
  shared rate-limit store (Redis), because the in-memory limiter is per process
  (`rate_limit.py`, `prod_preflight.py` enforce one worker today).

Re-run `bash loadtest/run.sh run target` against the new layout before calling it done.
