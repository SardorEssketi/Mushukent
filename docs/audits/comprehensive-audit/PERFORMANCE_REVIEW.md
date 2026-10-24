# Performance Review (updated after phase 2)

Everything labelled **Measured** was run on this Windows workstation (Docker Postgres, local backend, headless Chrome). Single user, sequential requests, no network latency. Treat absolute numbers as relative indicators, not production figures. **Predicted** means reasoning, not measurement.

## Measured: backend and database (synthetic data)
Dataset in a disposable PostGIS database: 5,000 users, 100,000 cats, 200,000 posts, 600,000 comments, 200,000 likes (random Tashkent coordinates). Median of 5 requests, authenticated:

| Endpoint | Median | Max | Response size |
|---|---|---|---|
| `GET /feed?filter=recent&limit=30` | 94.7 ms | 132 ms | 18.5 KB |
| `GET /feed?filter=popular&limit=30` | 163.6 ms | 169 ms | 18.5 KB |
| `GET /feed?filter=needs_help&limit=30` | 21.4 ms | 29 ms | 18.4 KB |
| `GET /feed` page 2 (cursor) | 93.4 ms | 106 ms | 18.5 KB |
| `GET /cats?limit=20` | 78.4 ms | 90 ms | 5.5 KB |
| `GET /posts/{id}` | 15.3 ms | 30 ms | 0.7 KB |
| `GET /posts/{id}/comments?limit=20` | 20.8 ms | 56 ms | 1.2 KB |
| `GET /places` | 8.1 ms | 42 ms | 47 B (no places loaded) |

The only statements over 50 ms in the Postgres log were the mixed-feed `UNION` query (61-71 ms) and the posts query behind `popular` (about 140 ms with joins).

**Popular feed plan (`EXPLAIN (ANALYZE, BUFFERS)`):** Parallel Seq Scan over all 200,000 posts (filter `deleted_at IS NULL AND is_public`) feeding a top-N heapsort; execution 30.6 ms for the core ordering. The indexes on `posts` are `created_at`, `cat_id`, `user_id`, `kind`, a partial `created_at`, and a GiST on `location`; none supports `(like_count, created_at, id)`. This is linear in the number of posts. **Predicted:** about ten times slower at 2 million posts; not measured. Priority: low until posts reach the hundreds of thousands (F-21).

Indexes that already exist and look right for the access patterns I exercised: `idx_comments_post_id`, `idx_likes_post_id`, `uq_likes_post_id_user_id`, `posts_location_gist`.

## Measured: map
- Cold load of `/map` issued 6 API calls: four `places?category=...&map_only=true&limit=200` and one each of `cats?filter=recently_added&bbox=...&limit=100` and `lost-pets/map?bbox=...&limit=100`, plus 63 OSM tile requests.
- 3 drags and 4 wheel-zooms produced 12 requests (one `cats` + one `lost-pets/map` per settled viewport). No duplicate or out-of-order bursts, consistent with the documented debounce.
- With 3,000 seeded cats in a 0.2 x 0.12 degree area the screen showed clustered pins, and the response is capped at 100 per viewport (F-22). Frame rate / jank was **not measured**.

## Measured: web bundle and startup
- `main.dart.js`: 4,855,313 bytes raw, 1,371,031 bytes gzipped. Total web build directory 46 MB (CanvasKit assets included).
- Local first Flutter frame: about 2.0-2.1 s on all three viewport sizes after navigation (localhost, no throttling). Not representative of mobile networks; no throttled run was performed.
- Cold start of `/profile` with a stale access token: three `GET /users/me` plus one `POST /auth/refresh` (F-24).
- The feed first load made a single `/feed?filter=recent&limit=30` call.

## Measured: upload handling
- 16 MP JPEG accepted; 36 MP rejected by the pixel cap; 6+ photos rejected. Uploads are read fully into memory per request (`api/v1/uploads.py:48-71`, up to 5 files); nginx allows 55 MB bodies. Peak memory under concurrent uploads was **not measured**.

## Measured: rate limiter
- 50,000 distinct keys stay in memory indefinitely (F-03).

## Not measured
Android startup/memory/APK size (build only), Flutter frame timings and widget rebuild counts, memory leaks, image cache behaviour, connection pool saturation, concurrent-user load, throttled-network behaviour, map rendering with thousands of simultaneous markers (the API caps it at 100).

## Prioritised optimisations (evidence-based only)
1. Fix F-02/F-03 (correctness first; the limiter is the only throttle).
2. Add a partial index for the popular feed once the posts table is large (measured sequential scan, F-21).
3. Remove duplicate `GET /users/me` calls at start-up (F-24); cheap and measurable.
4. Tell users when the map is truncated (F-22) or raise the cap with server-side clustering; decide from real usage data.
5. Measure before touching anything else: run a load test (k6/locust) against the stack and a Lighthouse run on throttled mobile.
