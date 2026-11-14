# Load test: can Mushukistan serve 200–300 concurrently active users? (Feed and Map)

Date: 2026-11-13. Branch `perf/load-test`. Backend image under test: the image of the live backend
release (`8939818`, Alembic `20261110_0031`), unmodified. Everything below ran on an **emulated
host** on a workstation. Production was not touched: no load, no writes, no SSH.

Evidence labels: **Verified** = measured or reproduced here; **From code** = read, not reproduced;
**Not checked** = not done, with the reason.

> **Superseded capacity numbers (2026-11-14).** This report's capacity statements (the knee at
> 60–80 users, "~11 ms of CPU per user-second", the 10× knee at 40 users and the latency-vs-users
> figures) are superseded by `FIXES_RESULTS.md`, section "Superseded measurements". Two reasons:
> the box here was one full workstation core, several times faster than the production core, and
> the harness healthcheck loaded the load-test shim every 10 s, taking ~13% of that core. The
> functional findings (no statement timeout, overload turning into an outage, upload memory,
> carrier-NAT 429s, worker poison pill, nginx resolver) still stand. The text below is unchanged.

---

## 1. Verdict

**No. Not on the current box and not with the current queries, and it gets worse as content grows** (at 10× data the box saturates at 40 users). With fixes it is reachable, but
only with both of these: (a) query fixes that cut the database cost of the Feed, Map and view
counting by several times, and (b) more CPU, or the database moved off the web box. Neither alone
is enough.

What breaks first, at what load, and why (all **Verified** on the emulated host):

1. **The single CPU core saturates at about 60–80 concurrent users** (stress test, section 3).
   At 60 users the p50 is 166 ms and the p95 1.9 s. At 80 users the p50 is 2.5 s and the p95 6.8 s.
   At 100 users it collapses (p95 at the 60 s timeout, 18% of requests fail for the user). The
   latency targets (Feed p95 < 500 ms, map < 700 ms) are **already missed at 20 users**: Feed
   p95 1.8 s, map pins p95 0.76 s, caused by bursts of `nearby` and map queries on the one core. The
   average user in the load model costs about **11 ms of CPU per second** (nginx + backend +
   Postgres), so one core is 100% busy at ~90 users and should not be run past ~60. The workstation
   core is faster than a typical shared cloud vCPU, so production will be at or below these numbers.
2. **Postgres is the bottleneck, not Python.** At saturation the database used 63–98% of the core
   and the backend 10–35%. In the 300-user run the database spent ~3,900 s executing queries in a
   1,500 s window, i.e. it needed ~2.6 cores. The top costs: the map `GET /cats` bbox query
   (LATERAL "latest post" per cat), the `nearby` feed (no usable spatial index; 1.2 s per page 2
   even when idle), the `recent` mixed feed (full scan + sort of all posts per page), and
   `POST /views/seen` (about 80 SQL statements per batch).
3. **Overload does not degrade gracefully. It turns into an outage.** There is no
   `statement_timeout`, so Postgres keeps executing queries for clients that gave up minutes ago
   (seen running for 450–615 s after their clients left). They hold all 15 pool connections, every
   other request waits 30 s for a connection and then fails with 500, and the database container hit
   its memory limit: **four Postgres OOM kills with crash recovery** (each drops every connection).
   After the 300-user run ended, the box was **still unusable 10 minutes later** until the stuck
   queries were cancelled by hand.
4. Separately from capacity, **guests behind a shared mobile IP (CGNAT) get 429s** at a handful of
   users per IP, because post detail, map lost-pet pins, marker taps and view batches all use the
   30/min per-IP anonymous bucket (H3, section 5). With 40 users on one IP, 15.5% of all requests
   got 429 (55% of guest feed requests), 21% when their tokens had expired.
5. **One account can crash the API** by publishing two posts at once with full-size photos
   (5 × ~25 MP): the backend process is OOM-killed (LT-10). App-sized photos are fine.

At 300 users the target scenario served 13 req/s of the ~70 req/s demanded, with p50 14.7 s and
p95 60 s (load-generator timeout). The app's own request timeout is 15 s, so **48.7% of requests
would have failed for real users** (> 15 s, 5xx or no answer). It failed every pass criterion
except "zero 429 for users with their own IP".

The basemap tiles are not served by us, so our backend cannot blank them. But with responses
slower than the client's 15 s timeout, the map shows its "Could not load this section" banner
instead of pins (From code: `map_screen.dart:887-910`; latencies measured). Tile policy risk is
separate (H4).

---

## 2. Load model and assumptions

PostHog was reachable through the granted connector, but production traffic is too small for
ratios (pre-launch volume; the exact figures stay private). So the model is built from
the client code, and its assumptions are stated here. 300 concurrent sessions is roughly two
orders of magnitude above anything production has seen.

**Mix (300 concurrent sessions):** 35% guests / 65% signed in.

| Persona | Share | What it does (client behaviour modelled from the Flutter code) | Req/min/user |
|---|---|---|---|
| Guest, feed | 21% | feed page every ~25 s (20 cards, `views/seen` batch per page), opens a post every ~75 s (`GET /posts/{id}`, comments, `POST /posts/{id}/views`) | ~7 |
| Guest, map | 14% | map open (places cache miss in 1 of 4 sessions: 4 categories, capped bboxes split), settled pan every ~8 s (2 requests: `cats` bbox + `lost-pets/map`), marker tap every ~30 s | ~17 |
| Signed in, feed | 29% | as guest feed, plus a like every ~45 s (unlike on 409 half the time), a comment every 5 min, a save every ~7 min | ~12.5 |
| Signed in, map | 23% | as guest map, marker tap every ~25 s | ~20 |
| Signed in, posting | 13% | feed page every ~40 s, publishes an observation with 1–3 photos (~1.4 MB each, what the app produces at 1920 px / q90) every ~10 min with an `Idempotency-Key` | ~6 |

Every signed-in client also runs the background timers found in the code: unread count every
1 min (`notification_push.dart`), lost-pet + adoption follow-up checks every 1 min
(`lost_pet_follow_up_listener.dart`). That's 3 req/min. Sessions last an exponential 8 min on
average; each new session is a cold start (3× `GET /users/me` as in F-24, unread count, two
follow-up checks). Token refresh: on 401 the user calls `POST /auth/refresh` and retries, as the
client does. The spike test starts every signed-in user with an **expired** access token.

**Requests that the client sends without a bearer token even when signed in**
(`authenticated: false` / `includeViewerContext: false`, **From code**): the map marker tap
`GET /cats/{id}/posts` (`map_screen.dart:513-518`), `GET /places`, `GET /places/{id}`, leaderboards.
These are counted per client IP, not per user. The model reproduces that.

**Rates.** 300 users ≈ **70 req/s average** (≈ 4,200 req/min), **~200 req/s at a 3× peak**. Per
endpoint at 300 users (average): `cats` bbox and `lost-pets/map` ~13 req/s each, `views/seen` ~6,
feed pages ~6, post detail trio ~5, background polls ~10, likes ~2, uploads ~0.07 (≈4 posts/min).

**Rate-limit bucket usage per user (production limits).** Signed-in feed user: ~10/min of the
60/min user bucket. Signed-in map user: ~11/min user bucket plus ~2.4/min in the per-IP anon bucket
(marker taps). Guest feed: ~4.8/min anon (per IP) + 2.4/min public-read (per IP). Guest map:
~9.5/min anon + ~7.5/min public-read (per IP).

**Data volume.** "Realistic" (1×) dataset for a service with 300 concurrent users (my assumption:
~12k registered accounts): 12,000 users, 10,000 cats, 30,000 posts (+39,000 photos), 60,000
comments, ~247,000 likes, ~1.19 M post views, ~20,000 saved posts, 800 lost pets, 400 adoption
posts, 1,000 places (4 categories), 100,000 notifications, 30% of users with nearby alerts on, 40%
with an Android device. Locations cluster around the Tashkent centre inside the client's
`tashkentMapBounds`. Popularity is power-law (likes, views, comments). The places import scripts
fetch from Overpass/2GIS, so places are synthetic (not checked against the real places set). The
10× dataset multiplies everything except places. Seeding: `loadtest/seed/seed.py`.

**Identities.** 600 accounts get access tokens minted with the stack's throwaway secret (plus an
expired token and a real refresh session each), so the login endpoint (10/min per IP) is never on
the path. Each simulated client has its own IP in `X-Forwarded-For`, which the backend honours
because the immediate peer (nginx) is in `TRUSTED_PROXY_CIDRS`. The CGNAT runs put N users on one IP.

Tool: **Locust** (FastHttpUser). Python lets the scenario reuse the token and seed code and model
per-user background timers and per-IP identity directly; k6 was not installed. A single Locust
process was never the bottleneck: the box saturated at ~20 req/s.

---

## 3. Results

### Emulated host

| Item | Emulation |
|---|---|
| CPU | db, backend, notification worker and nginx all pinned to **one shared core** (`cpuset: "0"`) |
| Memory | no swap; caps db 768 MB, backend 768 MB, worker 192 MB, nginx 64 MB (sum ≈1.8 GB) |
| Size reference | sized from the operator's private production notes (details are not repeated here) |
| Backend | live release image, `APP_ENV=production`, production single-worker uvicorn command, production rate limits, PostHog enabled (pointed at a sink) |
| Edge | production `infrastructure/nginx/default.conf` verbatim, over TLS (self-signed cert for the same names) |
| Database | `postgis/postgis:15-3.4`, default settings (as in production), plus `pg_stat_statements`, lock-wait and slow-statement logging for observation |
| External | R2 (S3 API), PostHog (events + OTLP logs) and FCM replaced by local sinks with 40 ms (R2/PostHog) and 120 ms (FCM) latency, outside the box. OSM tiles never requested |
| Not emulated | Cloudflare in front of the web hosts, real mobile/evening network latency (server-side measurements only), the workstation's faster CPU core |

The emulation splits memory per container; the real host shares it. The **OOM threshold** is
therefore approximate. The **CPU result is not**: section 3.3 derives it from uncontended
per-request costs and does not depend on the memory split.

### 3.1 Scenario results (server side, measured at the load generator through nginx)

| Scenario | Users | Served req/s | p50 | p95 | p99 | 429 | 5xx | Timeouts (60 s) | Notes |
|---|---|---|---|---|---|---|---|---|---|
| Baseline | 10 | 2.9 | 26 ms | 258 ms | 981 ms | 0 | 0 | 0 | `nearby` page 2+ p50 1.1 s already |
| Target (hold window 600–1500 s) | 300 | 13.4 | 14.7 s | 60.0 s | 60.1 s | 0 | 0.35% | 15.0% | oscillates between ~13 s p50 and full stalls; 579 pool timeouts; Postgres OOM-killed twice |
| Stress step 20 | 20 | 5.7 | 45 ms | 934 ms | 1.8 s | 0 | 0 | 0 | |
| Stress step 40 | 40 | 10.5 | 83 ms | 1.1 s | 3.0 s | 0 | 0 | 0 | feed p95 already > 500 ms |
| Stress step 60 | 60 | 15.3 | 166 ms | 1.9 s | 3.5 s | 0 | 0 | 0 | last step before the knee |
| Stress step 80 | 80 | 16.6 | 2.5 s | 6.8 s | 12.9 s | 0 | 0 | 0 | **knee** |
| Stress step 100 | 100 | 7.9 | 4.6 s | 60 s | 60 s | 0 | 8.1% | 7.8% | collapse; Postgres OOM-killed |
| Stress step 140 | 140 | 18.8 | 5.8 s | 9.1 s | 10.6 s | 0 | 0 | 0 | brief recovery between stalls |
| Stress step 160 | 160 | 2.5 | 60 s | 60 s | 60 s | 0 | 5.7% | 91% | stall; Postgres OOM-killed |
| Spike 0→300 in 60 s, expired tokens | 300 | 22.3 / 20.7 | 8.7 s / 13.5 s | 16.2 s / 21.6 s | 18.9 s / 25.1 s | 0 | 0 / 2.3% | 0 | first two 3-min windows; refresh p50 3.9 s |
| Spike recovery (drop to 30 users) | 30 | 8.3 → 4.8 | 80 → 30 ms | 10.7 s → 429 ms | | 0 | 0 | 0 | recovered within ~3 min |
| Soak, 1 h at the highest stable step | 60 | 14.0 | 106 ms | 1.4 s | 3.3 s | 0 | 0 | 0 | 14 of 50,529 over 15 s; no memory, connection or latency drift; Feed p95 3.4–10 s and map p95 0.8–1.8 s per 10-min window. A 200-user soak was not run: the box fails within minutes at ~100 users (target and stress runs) |
| 10× data, 40 users (5 min hold) | 40 | 6.9 | 1.4 s | 14.6 s | 42.6 s | 0 | 3.6% | 0.4% | **8.2% user-visible failures**; Feed p50 9–10 s, map p95 7.7 s; at 1× the same 40 users were fine. A 300-user run at 10× was not needed: it fails at 40 |
| CGNAT: 40 users on 1 IP | 40 | 9.6 | 29 ms | 448 ms | 1.4 s | **15.5%** | 0 | 0 | guest feed 55%, guest map 36%, signed-in map 7% rejected |
| CGNAT: 40 users on 1 IP, expired tokens | 40 | 9.9 | 23 ms | 444 ms | 1.5 s | **21.4%** | 0 | 0 | 81 of 107 refreshes 429 |
| Uploads: 20 at once, 3 × 1.4 MB (app-sized) | 20 | | 2–14.7 s per post | | | 0 | 0 | 0 | all 201; backend peak 479 MB; probe feed p50 190 → 447 ms during the burst |
| Uploads: 2 at once, 5 × 7.25 MB (24.6 MP) | 2 | | | | | | 2 × 502 | | **backend OOM-killed** (exit 137); 1 at a time succeeds |

Full tables per endpoint are in each run's `summary.md` (see `loadtest/README.md`). The step
numbers are whole-step aggregates, including the first seconds of each step.

Per-endpoint at the 300-user target (hold window): every endpoint had p50 8–24 s, including
`GET /notifications/unread-count` and `GET /users/me`, which cost ~10 ms each when the box is
idle. **Slow requests block fast ones**: there is one core and one pool, so a like or an
unread-count waits behind map and feed queries (H1).

### 3.2 Box metrics during the 300-user target

- CPU: box mean 95% of the single core; Postgres p95 97%, backend mean 30%.
- Memory: box peak 1.34 GB; Postgres at its 768 MB cap (page-cache thrash: ~91 GB read from disk
  during the run, 22 M file refaults, 571 k hits on the cgroup limit) and **OOM-killed**; backend
  peak 555 MB.
- Postgres connections: up to 25 (15 backend pool + parallel workers + worker); 13 active on
  average, up to 21; lock waits up to 6 ungranted locks; deadlocks 0.
- Connection pool: all 15 checked out most of the time; worst wait 31 s; **579 pool timeouts**
  (`QueuePool limit of size 5 overflow 10 reached`), i.e. 500s.
- Notification push backlog stayed small (≤ 7). The worker kept up because few lost pets were
  created.

### 3.3 Uncontended cost per request (idle box, sequential)

Measured through nginx with a new TLS connection per request; the TLS/connection overhead on
this path was ~30 ms (a kept-alive `/health` costs 3.5 ms), so subtract ~30 ms for the CPU the
box spends. Medians, 1× dataset:

| Request | Median | Notes |
|---|---|---|
| `GET /feed` recent page 1, signed in | 150–190 ms | full scan + sort of all posts (plan below) |
| `GET /feed` recent page 1, guest | 65–73 ms | |
| `GET /feed` popular page 1 | 211 ms | sequential scan + sort (F-21) |
| `GET /feed` nearby page 1 | 282–299 ms | no spatial index use |
| `GET /feed` nearby page 2+ | **1,154–1,176 ms** | distance cursor recomputes geography distance on every row; 1.1 s of it is a parallel worker starting PostGIS |
| `GET /cats` map bbox (z14 / z12) | 70–94 / 119 ms | LATERAL latest-post probe for every cat in the box |
| `GET /lost-pets/map` | 47 ms | |
| `GET /places` per category (city) | 48 ms | |
| `GET /cats/{id}/posts?limit=1` (marker tap) | 46 ms | |
| `GET /posts/{id}`, `/comments` | 53, 56 ms | |
| `POST /views/seen` (20 items) | **145–200 ms** | ~80 statements per batch (N+1) |
| unread-count, follow-ups due, `users/me` | 38–48 ms | |
| `GET /health` (kept-alive) | 3.5 ms | framework floor |

Weighted by the load model, one active user costs ~670 ms of CPU per minute (~11 ms/s). Of that,
`views/seen` is the single largest item (~40% of a feed user's cost) and map pans are ~90% of a map
user's cost.

**Why the expensive ones are expensive** (`auto_explain` with real parameters, then the
simplified shapes in `loadtest/tools/query_experiments.sql`; EXPLAIN ANALYZE on the idle box):

| Query | Today | Plan problem | Proposed shape | Proposed time |
|---|---|---|---|---|
| `nearby` feed key query | 284 ms page 1 (parallel), 1.57 s page 2; **7.77 s** with a serial plan | `ST_DWithin(CAST(geometry AS geography))` is not index-usable and is estimated at 3 rows (actual 7,583) → serial plan is a 10k × 7.6k nested loop; the parallel plan spends 1.1 s starting PostGIS in a worker | geometry `&&` box prefilter (longitude scaled by 1/cos(lat)) + exact `ST_DWithin` | **69 ms** (1 km radius: 2 ms) |
| `recent` mixed-feed key query | 26 ms SQL (147 ms in the app's parallel plan under auth) | union of complete branches, then one global sort: reads every post and cat | ORDER BY + LIMIT inside each branch, then merge | **1.3 ms** |
| popular | 23 ms | sequential scan + top-N sort (F-21) | `(like_count DESC, created_at DESC, id DESC)` partial index | not measured |
| map `cats` bbox (z14), SQL part | 19.6 ms (2,320 LATERAL probes) | LATERAL latest post for every cat in the box, before the limit | partial index `posts (cat_id, created_at DESC, id DESC) WHERE deleted_at IS NULL AND is_public` | **10.8 ms**; the rest of the 70–120 ms API time is Python building up to 100 cats |
| nearby-alert recipients (lost-pet fan-out) | 0.8 ms | none; uses `idx_notification_preferences_alert_geography` | none | |
| `cats` nearby filter correctness | returns 2,381 of the 2,736 cats inside 5 km | `ST_Expand(point, radius/111320)` in degrees on both axes; a longitude degree is ~84 km here | two-axis expansion | all 2,736 |

Turning parallel query off (as recommended for one core) **before** fixing `nearby` made it worse
(page 1 9.2 s, page 2 6.6 s through the API), so the order of fixes matters (PROPOSED_FIXES FIX-10).

### 3.4 10× dataset

Dataset ×10 (120k users, 100k cats, 300k posts, 2.5M likes, 12M post views, 600k comments, 1M
notifications; database 4.5 GB, `post_views` 2.7 GB). The seed itself ran with temporary extra
resources; every measurement below ran on the restored one-core / 768 MB database container.

Uncontended cost per request (same probe as 3.3, medians):

| Request | 1× | 10× |
|---|---|---|
| `recent` feed page, signed in / guest | 150–190 / 65–73 ms | **698 / 670 ms** |
| `popular` page 1 | 211 ms | **844 ms** |
| `nearby` page 1 / page 2 | 299 / 1,176 ms | **1,734 / 2,069 ms** |
| map `cats` bbox z15 / z14 / z12 | 94 / 94 / 119 ms | **159 / 176 / 211 ms** |
| `views/seen` (20) | 145–200 ms | 240 ms |
| `posts/{id}/comments` | 56 ms | 110 ms |
| post detail, marker tap, unread count, `users/me`, `lost-pets/map`, places | 40–55 ms | 43–57 ms (flat) |

Everything that scans or sorts all posts grows roughly linearly; point lookups do not. Under load
(40 users, the row in 3.1), the box was saturated with p95 14.6 s and 8% user-visible failures.

Query shapes at 10× (EXPLAIN ANALYZE, serial):

| Query | Current | Proposed | Result |
|---|---|---|---|
| `recent` key query | 423 ms | per-branch ORDER BY/LIMIT | **3.7 ms** |
| `popular` ordering | 259 ms | partial index | not measured |
| map `cats` bbox z14 (SQL) | 696 ms | `(cat_id, created_at DESC)` partial index | **150 ms** |
| `nearby` page 1, 5 km | 1,101 ms | box prefilter only | 1,797 ms: **does not scale** (77,142 posts are inside 5 km, all get a distance and a sort) |
| `nearby` page 1, 5 km | 1,101 ms | **KNN**: geography GiST expression index + `ORDER BY location::geography <-> point` (tie-break outside) | **39 ms**; page 10: **2 ms** |
| nearby-alert recipients | 0.8 ms (1×) | unchanged | 73 ms at 10× (one per lost-pet creation; acceptable) |
| `cats` nearby correctness | 22,859 of 26,499 cats inside 5 km returned | two-axis expansion | 14% missing today |

---

## 4. Findings

Severity is about impact at 200–300 users. Effort: S < 1 day, M 1–3 days, L > 3 days.
"Decision" = needs an architecture decision from the owner.

| ID | Area | Severity | Status | Evidence / where | Impact at 300 users | Proposed fix | Effort | Decision |
|---|---|---|---|---|---|---|---|---|
| LT-01 | Infra / DB | **Critical** | Verified | Stress: knee at 60–80 users, collapse at 100. Postgres 63–98% of the single core. Uncontended cost ~11 ms CPU per user-second (3.3) | The box serves ~13–20 req/s of ~70 demanded: p50 9–15 s, ~25–50% of requests fail from the user's point of view (> 15 s client timeout, 5xx, timeouts) | Query fixes LT-03..06 first, then ~3 cores for app + DB (PROPOSED_FIXES "Capacity") | L | **Yes** (hosting / DB placement) |
| LT-02 | Infra / DB | **Critical** | Verified | No `statement_timeout`; pool `pool_timeout` 30 s (`infrastructure/db/session.py:18`). Queries ran 450–615 s after clients left; 579 pool timeouts; box still stuck 10 min after the load stopped; 4 Postgres OOM kills + crash recovery | Overload becomes an outage that does not end when users leave; a crash drops every connection | FIX-1: statement/lock/idle timeouts, 3 s pool timeout, 503 + `Retry-After`; shorter nginx read timeout for non-upload API | S | No (config; DB/nginx changes need approval) |
| LT-03 | Feed | **High** | Verified | `feed/infrastructure/repositories.py:38-100`: `ST_DWithin(CAST(geometry AS geography))` cannot use the geometry GiST index; estimate 3 rows vs 7,583. Page 2+ 1.15–1.18 s when idle (2.1 s at 10×); serial plan 6–9 s | One nearby page costs as much as ~10 recent pages; a statistics change can flip production to the 9 s plan | FIX-2: KNN with a geography GiST expression index (10×: 1,101 → 39 ms; page 10: 2 ms). The box prefilter alone fixes the 1× plan (7,767 → 69 ms) but not 10× | M | No (migration) |
| LT-04 | Map | **High** | Verified | `cats/infrastructure/repositories.py:67-86, 284-293`: LATERAL latest-public-post per cat in the bbox, then sort/limit. 70–120 ms per pan, 2 requests per settled pan | Map users are ~40% of load; at 300 users ~13 cats-bbox req/s is ~1 core alone | FIX-4: partial index (SQL 19.6 → 10.8 ms); later denormalised latest-post columns and cacheable quantised bboxes | S / M | Partly (denormalisation) |
| LT-05 | Feed | **High** | Verified | `views/application/service.py:89-126`: ~4 statements per item, ~80 per batch, 145–200 ms per `POST /views/seen` | ~40% of every feed user's server cost goes to counting views | FIX-3: set-based visibility check, bulk insert, bulk update (estimate 10–20 ms); flush every 30 s | M | No |
| LT-06 | Feed | Medium | Verified | Recent mixed feed: union of full branches, global sort (`feed/infrastructure/repositories.py:102-150`); page cost 150–190 ms signed in, 65–73 ms guest | Grows linearly with posts; second-largest Feed cost | FIX-5: per-branch ORDER BY/LIMIT (26 → 1.3 ms key query); profile the signed-in hydration | M | No |
| LT-07 | Feed | Low | Verified | Popular feed: sequential scan + sort (23 ms SQL at 30k posts; 211 ms API) – F-21 | Small share of traffic | FIX-11 index | S | No |
| LT-08 | Auth / rate limits | **High** | Verified | 40 users behind one IP: **15.5% of requests 429** (guest feed 55%, guest map 36%, signed-in map 6.8%); with expired tokens 21%, refresh 81 of 107 rejected. Per-IP anon bucket covers post detail, `lost-pets/map`, marker taps, views (`core/rate_limit.py:167-226`) | Guests on Uzbek mobile carriers (CGNAT) see broken post pages, missing lost-pet pins and "Could not load" banners; signed-in users fail to refresh after idle | FIX-7: move read-only GETs to public-read, separate telemetry bucket, CGNAT-tolerant per-IP ceilings, refresh keyed by session, token on marker taps | S–M | **Yes** (limit policy) |
| LT-09 | UX | Medium | From code | 429 maps to `ApiFailureKind.unknown` (`core/network/api_error.dart`); map shows "Could not load this section" + Retry over stale pins (`map_screen.dart:887-910`); `Retry-After` ignored; feed load-more shows a page error; view batches dropped silently | Under limits or overload, users get generic errors and retry, which spends more of the bucket | FIX-7 item 5; distinguish "busy, retrying" from "failed" | S | No |
| LT-10 | Uploads / Infra | **Critical** | Verified | 2 concurrent publications of 5 × ~7 MB (24.6 MP) photos OOM-kill the backend (kernel `oom` event, exit 137, Docker restart); one account sending 10 does it too; 1 succeeds. Images decoded twice at full size (`storage/images.py:150-196`), limiter 2 (`api/v1/uploads.py:15`) | Anyone with an account (or a client that skips resizing) can take the whole API down for every user; app-sized photos (1920 px) were fine even 20 at once | FIX-6: header-only validation, JPEG `draft()` downscaled decode, limiter 1, one publication in flight per user, lower pixel cap | M | No |
| LT-11 | Infra | Medium | Verified | nginx resolves `backend` once (`infrastructure/nginx/default.conf` `proxy_pass http://backend:8000`). After the containers restarted with new addresses: 22,378 × 502 until `nginx -s reload` | An OOM restart that reassigns the address turns into a full outage until someone reloads nginx (the runbook already warns for recreation) | FIX-9: Docker DNS `resolver` + variable upstream | S | No (infra approval) |
| LT-12 | Notifications | **High** | Verified | One undecryptable device token aborts the whole delivery pass (`notification_worker_pass_failed`, `cryptography.fernet.InvalidToken`); jobs claimed with it reach `attempts=4` and end `failed / LEASE_EXPIRED` unsent (200 lost in the repro) | After a key rotation or a corrupt row, every push (comments, nearby lost pets, follow-ups) stops silently | FIX-8: per-job error handling | S | No |
| LT-13 | Notifications | Medium | Verified / From code | Worker delivers one claim of 50 per 30 s (~100 pushes/min); seeding 12k users queued ~2,900 inactivity jobs (~30 min to drain). Nearby fan-out runs inside the lost-pet create request (`lost_pets/application/service.py:154`) | A lost pet in a dense area with N alert subscribers waits N/100 minutes for the last push; the request does N inserts | FIX-8 throughput loop; batch FCM sends; move fan-out to the worker | S–M | No |
| LT-14 | Map | Low | Verified | `cats` nearby uses `ST_Expand(point, radius/111_320)` on both axes: 2,381 of 2,736 cats inside 5 km returned (13% missing) | Wrong results, not load | FIX-2 (second diff) | S | No |
| LT-15 | Data | Low | Verified | 5 concurrent `POST /posts` with the same `Idempotency-Key` → 1 post (good); without a key → 5 posts | Only old clients / API callers | Require the key for new builds | S | No |
| LT-16 | Data / DB | Medium | Verified | 200 simultaneous likes on one post: counts exact, but serialised (p95 1.3 s idle). Under load, `UPDATE posts SET view_count` mean 17 ms, max 12 s (row-lock waits with likes) | A viral post (lost pet after a push) gets slow likes and view batches | Count views asynchronously or in bulk (FIX-3); keep likes as they are (correct) | M | No |
| LT-17 | DB | Medium | Verified | Parallel query on one core: a 0.4 ms lost-pets scan took 1.1 s inside a parallel worker (PostGIS start-up); parallel workers add memory during overload | Wasted CPU and memory at exactly the wrong time | FIX-10, only after FIX-2 | S | No (infra approval) |
| LT-18 | Backend | Medium | Verified | Sync handlers keep running after the client disconnects; queued handlers (40 threads vs 15 connections) re-fill the pool after the SQL is cancelled (spike run contaminated by the previous run) | Recovery after a spike is slow | FIX-1 (fail fast), consider a concurrency cap in front of the pool | S | No |
| LT-19 | Map / external | **High** (risk) | From code + estimate | All map screens fetch `tile.openstreetmap.org` directly (`map_screen.dart:84-87`, `add_observation_location_screen.dart:222`, `lost_pet_create_screen.dart:482`); ~175 tiles/s at peak estimated (section 6) | OSM may throttle or block heavy apps without notice: a blank basemap for everyone | Tile provider with an SLA, or a proxy cache / own Tashkent raster on R2 | M | **Yes** |
| LT-20 | Observability | Medium | Verified | Nothing in production would show pool exhaustion, statement time, Postgres OOM kills or container restarts (the health check does not touch the DB, F-18) | An overload or crash loop is invisible until users complain | Export pool and request-duration metrics; alert on container restarts / OOM | M | Partly |
| LT-21 | Frontend | Low | From code (modelled) | F-24 still present: 3× `GET /users/me` per cold start | ~3 extra requests per session start; matters in spikes | Single in-flight `users/me` | S | No |

What held up (all **Verified**): no lost or duplicated writes under concurrency (likes, toggles from
two tabs, idempotent publication, contact-reveal quota), no deadlocks in any run, no duplicates or
skips while paging recent, popular (with likes landing during the scroll) or nearby to the end,
deletes while 30 users view the post return only 200/404, expired token → refresh → retry works,
and a normal signed-in user with their own IP never hit 429 in any run.

---

## 5. Hypotheses H1–H10

| # | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| H1 | Single-process ceiling; slow requests block fast ones | **Confirmed, but the first ceiling is the database CPU, not the threadpool.** | Knee at 60–80 users (~15–17 req/s). The 15-connection pool fills next (579 pool timeouts at 300 users), then the 40 threads queue behind it. Fast endpoints (unread count, ~10 ms idle) had p50 19 s at 300 users. During a 20-upload burst the probe's feed p50 went 190 → 447 ms and likes 57 → 101 ms. More uvicorn workers would not help on one core. |
| H2 | A normal signed-in user hits 429 | **Rejected for a user with their own IP**; confirmed behind shared IPs (H3). | 0 × 429 across the 44,602 requests of the distinct-IP runs (baseline, target, stress, spike) and the 54,870 of the 1 h soak. Bucket use ~10–11/min of 60 for feed and map users. `/lost-pets/map` is in the 60/min user bucket; a user would need about one settled pan per second for a minute to reach it. Marker taps and place details are sent without a token, so they use the per-IP anon bucket even when signed in. On 429 the UI shows the generic "Could not load this section" + Retry (map banner over stale pins; feed page error), with no backoff. |
| H3 | Shared IPs (CGNAT) break Feed/Map for guests | **Confirmed.** | 40 users on one IP: 15.5% of requests 429 (guest feed 55%, guest map 36%, signed-in map 7%); with expired tokens 21% and 81 of 107 refreshes rejected. Arithmetic: the 30/min anon bucket is exhausted by ~5 guests per IP. |
| H4 | Direct OSM tiles violate the tile policy at 300 users | **Likely risk (estimate; OSM never load-tested).** | Policy (fetched 2026-11-13): a clear app User-Agent, a valid Referer on web, honour cache headers (≥ 7 days if unknown), no bulk/prefetch, "heavy use" may be blocked without notice, no SLA; commercial/heavy users are pointed to other providers. Our client: Android sends `User-Agent: flutter_map (mushukistan_frontend)` and flutter_map 8.3.1 caches tiles on device; web uses the browser UA and cache, and nginx's `strict-origin-when-cross-origin` sends `https://mushukistan.uz/` as Referer. So each client is compliant; the risk is the **volume** (section 6). |
| H5 | Popular feed / UNION query is the bottleneck | **Partly, and it gets worse with data.** | Popular is a sequential scan (23 ms SQL at 30k posts) but a small share of traffic. The bigger feed costs are `nearby` (no usable index, 1.2 s per page 2+, fragile plan), the recent UNION (full scan + sort, linear) and the `views/seen` N+1. Under concurrency these queries were 10–100× slower than alone (CPU sharing + parallel-worker overhead). At 10× the recent page costs 700 ms, popular 844 ms and nearby 1.7–2.1 s uncontended, and 40 users saturate the box (3.4). |
| H6 | Concurrent uploads can OOM-kill the backend or Postgres | **Confirmed (both).** | Backend: 2 concurrent max-size publications → kernel OOM kill, exit 137, restart. Postgres: 4 OOM kills with crash recovery during overload (memory per container on the emulated host; production shares one memory pool between all containers, so the threshold differs, the mechanism does not). App-sized photos: 20 concurrent fine, backend peak 479 MB. |
| H7 | Write amplification / hot rows / deadlocks | **No corruption or deadlocks; hot-row latency confirmed.** | 200 simultaneous likes: 200 rows, like_count 200, p95 1.3 s. `view_count` UPDATE: 15,460 calls, mean 17 ms, max 12 s under load (row-lock waits). Up to 6 ungranted locks, 0 deadlocks in all runs. `views/seen` lock ordering held. |
| H8 | Postgres defaults are wrong for this box | **Partly.** | `max_connections` 100 vs ≤ 25 used: fine. `shared_buffers` 128 MB, `work_mem` 4 MB: fine for the size. The harmful defaults are **no `statement_timeout`** (LT-02) and **parallel query on one core** (LT-17). Autovacuum kept up during the 1 h soak (posts: 1,253 dead tuples, 2 autovacuums, 12 autoanalyzes; `post_views` is insert-only, +45,724 rows). |
| H9 | Duplicates or skipped cards during infinite scroll | **Rejected (measured).** | 0 duplicates and 0 skips in recent (new posts arriving), popular (likes landing 30–35 positions below the cursor while paging 15 pages) and nearby (all 3,038 items in 152 pages). From code: a popular-feed skip is still possible if a post's like count jumps across the cursor's count during the scroll; the client de-duplicates by id (`feed_screen.dart:123`), so duplicates never show. |
| H10 | Notification worker under load | **Throughput limit and a poison-pill bug; small API impact.** | Fan-out query 0.8 ms (uses `idx_notification_preferences_alert_geography`). Delivery capped at ~100 pushes/min (one claim of 50 per 30 s); a 2,900-job backlog takes ~30 min. One bad device row stops all deliveries and fails up to 49 innocent jobs (LT-12). The worker added < 1% CPU in all runs. |

Own hypotheses added: H11 overload does not self-recover (confirmed, LT-02/LT-18); H12 a
container restart can leave nginx pointing at a dead address (confirmed, LT-11); H13 the `cats`
nearby filter is geometrically wrong (confirmed, LT-14).

---

## 6. External costs and quotas at 300 active users

All volumes are **estimates** from the load model (section 2) and the mock-sink counters, assuming
the 300-user peak lasts the equivalent of 6 full hours a day. Prices were **not checked**: use
each vendor's current price list with these volumes.

| Service | Volume per day / month at that level | Basis | Quota / cost note |
|---|---|---|---|
| Cloudflare R2, writes | ~1,400 posts/day × ~1.75 photos × 2 objects (canonical + thumbnail) ≈ 4,900 PUT/day ≈ **150k Class A ops/month** | model: 13% posters, one post per 10 min; measured 2 PUTs per photo | inside R2's monthly free Class A allowance as published (1M) |
| R2 storage | measured ~0.54 MB per stored object (canonical + thumb average for 1.4 MB uploads) → **~2.6 GB/day, ~80 GB/month added** | mock sink: 103.5 MB for 192 PUTs | grows linearly; storage is billed per GB-month above the free tier; cheap per GB, but it never shrinks without a retention policy |
| R2 reads / egress | served from `media.mushukistan.uz` through Cloudflare; Class B ops only on cache misses; R2 egress is free | not measured (cache rules are RECORD-only in the runbook) | verify that the cache rule exists, or every thumbnail view in the feed is a Class B op |
| PostHog, backend events | likes + comments + posts + other captures ≈ 140/min at 300 users → ~50k/day → **~1.5M/month** | model rates × captures seen in code (`post_liked`, `comment_created`, …) | above PostHog's free monthly event allowance as published (1M); price not verified |
| PostHog, web `$pageview` | ~37 new sessions/min × ~4 pages ≈ 150/min → ~54k/day → up to **~1.6M/month** if all clients were web | model; web share unknown | combined with backend events ~2–3M events/month |
| PostHog, OTLP log export | healthy state ~13 B of exported logs per API request (baseline); under overload it jumped to ~400 B/request (tracebacks) | mock sink bytes per run | small when healthy; error storms multiply it |
| FCM | comments/replies, nearby lost-pet alerts, follow-ups, inactivity: thousands/day | model + worker counters | FCM sends are free; the limit that matters is our worker's ~100/min (LT-13) |
| OSM tiles (not ours) | map users ≈ 35% of 300 ≈ 105 concurrent; ~7.5 settled pans/min × ~20 new tiles, ~30% device/browser cache hits → **~175 tiles/s at peak, ~630k per peak hour, ~4M/day** | prior audit measured 63 tiles per cold map open; pan tiles estimated from viewport size | the OSM policy sets no number, but this is "heavy use" for a single app; a block means a blank map for everyone (LT-19) |
| Cloudflare (web hosts) | static Flutter bundle, cached | not measured | no concern at this level on the current plan |

Database growth at that level (from the model): ~1,400 posts/day and up to ~2.6M `post_views`
rows/day (150 feed users × 20 cards × 2.4 pages/min, an upper bound because a viewer–post pair
counts once). `post_views` is already the largest table (263 MB of 468 MB at 1×, ~220 bytes per
row with indexes), so at that rate it would add ~0.5 GB/day. That needs a retention or roll-up
decision before growth.

---

## 7. Prioritised plan

**Must fix before growth** (in this order; each is small, and together they are the difference
between "slow" and "down"):

1. LT-02 / FIX-1: statement, lock and idle timeouts; 3 s pool timeout; 503 + `Retry-After`.
   Overload must shed load instead of turning into an outage.
2. LT-10 / FIX-6: uploads cannot exhaust memory (header-only validation, downscaled JPEG decode,
   limiter 1, one publication per user in flight).
3. LT-03 / FIX-2: nearby feed via KNN + geography index (and the LT-14 expansion fix), then
   LT-17 / FIX-10 (no parallel query on one core).
4. LT-05 / FIX-3: set-based `views/seen`.
5. LT-04 / FIX-4: partial index for the map LATERAL.
6. LT-08 / FIX-7: CGNAT-tolerant rate-limit buckets, refresh keyed by session, token on marker taps.
7. LT-12 / FIX-8: worker per-job error handling.
8. LT-11 / FIX-9: nginx re-resolves the backend.
9. **LT-01: capacity decision.** After 1–5, re-run this harness (`bash loadtest/run.sh run stress`)
   to get the new per-user cost, then size the host: by my projection ~3 cores for app + DB at 300
   users (4 vCPU / 8 GB single box, or a separate/managed database).

**Should fix:** LT-06 (recent feed per-branch limit), LT-19 (tile provider or cache; decide before
any promotion), LT-09 (429 / busy UX), LT-13 (worker throughput, fan-out out of the request),
LT-16 (asynchronous view counting), LT-20 (metrics and restart/OOM alerts), LT-07, LT-21.

**Later / with growth:** Redis-backed rate limiter + several uvicorn workers (only useful once the
database is not the bottleneck and there is more than one core), denormalised "latest post" on cats
and cacheable map bboxes, KNN nearby, a read replica.

Validation gate before calling 300 users done: `target` run with p95 Feed < 500 ms and map
< 700 ms, 5xx < 0.5%, no timeouts; the CGNAT run with 0 × 429 for a normal profile; the upload
stress with no restart; a 1 h soak at 200 users without drift.

---

## 8. Not checked, and what I need from you

| Not checked | Why | What would close it |
|---|---|---|
| Phase 2 and 5: browser user flows (guest → feed → map → sign-up → add observation → … → profile) on throttled 3G with packet loss, Android layout, time to first pins/cards, memory over a long feed scroll | This session spent its time on server capacity, which turned out to be the blocking problem. A Flutter web build plus scripted headless-Chrome flows is a separate session. Error/429 behaviour was reviewed from code (LT-09) | Your OK to spend a session on it; it needs a local web build pointed at this stack |
| Production CPU speed versus the workstation core | Would need a benchmark on the production host, which is load | Read-only `lscpu` / `nproc` via `scripts/deploy/remote-inspect.sh`, with your permission. Then I can scale the knee (60–80 users here) to production |
| Production Postgres settings and live memory per container | Read-only inspection needs your permission | Same inspection: `SHOW ALL` (no secrets) and `docker stats --no-stream` |
| Real traffic mix (guest share, web vs Android, feed vs map) | PostHog has too little traffic to derive ratios | Re-derive the model after launch traffic exists; `loadtest/locustfile.py` weights are env-configurable |
| How many subscribers share one public IP on Uzbek carriers | Not measurable from here | Any carrier data you have; the run with 40 users per IP is a plausible, not proven, ratio |
| Production OOM threshold | The emulation caps memory per container; production shares one memory pool without per-container caps | Same inspection plus, if you allow it, a staging copy of the production box |
| Cloudflare/R2 media cache rules, PostHog and R2 prices | Dashboard settings are RECORD-only; prices not looked up | Dashboard read access or a screenshot; current price pages |
| Effect of the proposed fixes as a whole | Fixes are proposals; only the SQL shapes were measured | Your approval to implement FIX-1..6 on a branch, then the same harness re-run |
| Real nginx → backend behaviour through Cloudflare for `api` | `api` is DNS-only today; the emulation hits nginx directly | Nothing needed now; revisit if `api` is proxied |
