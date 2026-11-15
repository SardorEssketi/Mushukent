# Load-audit fixes: results (DRAFT, in progress)

Branch `perf/fixes`. Status: capacity method and per-variant slopes measured (sections 2 and 3);
scenario re-runs, per-fix entries, capacity options, decision memos and deploy packages are still to
be written (verdict pending the stress ladder). Nothing here was deployed.

Evidence labels: **Verified** = measured here; **From code** = read, not reproduced;
**Not checked** = not done, with the reason. Hardware details stay in the private production notes;
this file uses only derived factors.

---

## 1. Verdict

**Measured capacity of the current box (one production core): ~35 concurrent active users after
the fixes, against fewer than 10 before** (**Verified**). After the fixes, 35 users meet the
latency targets (Feed p95 338 ms, map p95 249 ms) and 40 users miss them in both runs (Feed p95
542 and 572 ms). Before the fixes, the Feed p95 was already 984 ms at 10 users. The earlier
"10–15 users before" figure came from artefact-affected runs and is superseded (see the last
section). The limit is latency from queueing on one core, not CPU. By CPU alone the box would
carry ~48 users at 70% (section 3).

Still pending: the rest of task 5 (in-flight cap, uploads, CGNAT, spike, 300 users, 10× data,
soak).

## 2. Capacity method: marginal cost, not average

The emulated box runs db, backend, notification worker and nginx in one cgroup with a CPU quota of
0.28 workstation core, calibrated by benchmark to one production core (**Verified**, benchmark within
±5% of the production median; production runs vary ~20%). CPU is read from the kernel cgroup
counters per container (`loadtest/tools/remeasure.sh slope`), in a clean 300 s steady window per
step after 90 s of warm-up, one run at a time (lock + check for a running Locust). Step 0 is idle
(no Locust). The fit is `box CPU = floor + slope × active users`; steps at ≥ 85% of the core are
reported but left out of the fit (saturated, non-linear).

Capacity (CPU only) = (0.7 × cores − floor) / slope. It is an upper bound: latency targets can fail
earlier, because one core serves requests one at a time and bursts queue (section 3).

The harness goes through the production nginx TLS configuration, as the production API does
(**Verified**), so TLS cost is included. Locust keeps one keep-alive session per user; whether real
mobile clients reconnect (and handshake) more often is **Not checked**.

## 3. Results per variant (1× dataset, production-core units)

Floor = measured idle box (0 users). Slope in ms of a production core per extra active user-second.

| Variant | Idle floor | Fitted slope | R² (steps) | CPU capacity at 70% | Feed / map p95 at 20 users | at 40 users |
|---|---|---|---|---|---|---|
| before (`8939818`, Alembic 0031, parallel query on) | 0.060 core | 34.9 ms | 2 points (0, 10); 20+ saturated | **18** users | 7.5 s / 3.9 s (saturated) | 12.4 s / 9.5 s, 0.24% errors |
| after (committed fixes, `6a5a3db`) | 0.060 core | 13.1 ms | 0.991 (0, 10, 20, 40) | **48** users | 181 / 171 ms | 572 / 409 ms |
| after + A+B+C (`bf7b7ff`) | 0.062 core | 13.05 ms | 0.995 (0, 10, 20, 40) | **48** users | 200 / 193 ms | 542 / 503 ms |

Per request (box CPU above idle ÷ requests/s, at the highest unsaturated step): before **148 ms**
(10 users), after **55.9 ms** (40 users), after + A+B+C **55.9 ms** (40 users). The committed fixes
cut CPU per request by **2.6×**. (**Verified**)

Split of the marginal cost after the fixes (slopes): backend 7.9 ms, Postgres 4.7 ms, nginx 0.5 ms,
worker ~0. Postgres is ~36% of the marginal cost, not ~14% as an earlier artefact-affected profile
suggested.

**A+B+C** (async no-I/O dependencies, one JWT decode per request, rate limiter as plain ASGI):
**no measurable gain** on the box (slope 13.05 vs 13.10 ms, within noise). Backend CPU per request
at 40 users: 32.0 vs 33.3 ms (−4%, within run-to-run noise). The py-spy profile suggested ~20% of
backend Python in thread-pool hand-offs; removing ~4 of ~5 hand-offs per signed-in request did not
show up in CPU. The change is kept (it is behaviour-neutral and tested) but should not be counted as
capacity. (**Verified**)

Raw data: `loadtest/results/cpu-slope/slope.csv` (gitignored), fit: `tools/slope_fit.py`.

### 3.1 Latency knee (task 5a): capacity by latency, not CPU

Image `bf7b7ff` (after + A+B+C), 1× data, 300 s steady windows, one run at a time. Targets:
Feed p95 < 500 ms, map p95 < 700 ms (client side, through nginx/TLS). (**Verified**)

| Active users | Box CPU (production core) | Feed / map p95, plain | Feed / map p95, traced | Mean server time per request (traced) |
|---|---|---|---|---|
| 2 | 0.16 | n/a | 154 / 150 ms | 54 ms (uncontended) |
| 20 | 0.33–0.40 | 200 / 193 ms | 344 / 306 ms | 91 ms |
| 25 | 0.42 | n/a | 211 / 258 ms | 77 ms |
| 30 | 0.44 | **344 / 260 ms** | 459 / 394 ms | 108 ms |
| 35 | 0.49 | **338 / 249 ms** | 582 / 521 ms | 137 ms |
| 40 | 0.60–0.67 | 542 / 503 and 572 / 409 ms (two runs) | 2,019 / 1,729 ms | 338 ms |

**Capacity by latency: 35 active users**, the highest step that meets both targets without the
tracer. For reference, the CPU-based figure is ~48 users at 70% (section 3). No errors and no 503
sheds at any step.

The per-request tracer (load-test shim only, `LOADTEST_TRACE=1`) costs ~0.05–0.06 production
core, which moves the traced knee down by about one step. The knee is therefore taken from the
plain runs; the traced runs are used only to see where the time goes.

**Queueing well before 70% CPU: confirmed.**
- Mean server time per request doubles between 2 users (54 ms, the core to itself) and 30 users
  (108 ms, ~45–50% CPU). That is what a single-server queue predicts: residence time ≈
  service time / (1 − utilisation).
- The median barely moves (Feed p50 83 → 91 ms) while the tail grows (Feed server p95 129 →
  420 ms): bursts queue behind each other on the one core.
- At 40 users the queue tips over. Mean server time is 6× the uncontended value, which is worse
  than the simple model, because waits for a thread-pool thread (21% of server time) and for a
  database connection (pool wait p95 178 ms) appear on top.

Where the time goes (traced; the slow tail of the slowest endpoints is in
`tools/knee_breakdown.py` output):
- Database time (query wall time, including Postgres waiting for the core) is ~45% of server time.
- The worker thread waiting for the core is ~40%. On the emulated box this also contains the
  slower core itself: a request alone on the box shows the same share (40% at 2 users). Queueing
  is therefore read as the growth in milliseconds over the 2-user baseline, not as the share.
- Thread-pool hand-off is 7% → 21% (2 → 40 users), pool wait 0% → 7%, and event loop / async
  middleware ~11–14%.
- The in-flight cap has no queue: requests above the cap get 503 at once. No cap wait exists to
  measure.
- At 20 users the slowest endpoint tails are `/cats` map pins (tail mean 479 ms: 298 ms DB,
  125 ms waiting for the core) and `/views/seen`. At 35–40 users, post detail and comments join
  them.

## 8. Deploy package 1: "no outage" + query fixes + A+B+C

**Measured capacity of the current box: ~35 concurrent active users after the fixes, against
fewer than 10 before** (section 3.1). Most of the gain comes from the query fixes (FIX-2..5, 11);
the "no outage" fixes (FIX-1, 6, 8) make overload fail fast instead of turning into an outage.
Nothing here has been deployed. Every production step below needs the owner's approval for that
step (gates G2–G6 in `docs/DEPLOYMENT.md`), and the backend procedure is B in that runbook.

### 8.1 Contents

The package is a local branch, `perf/deploy-package-1` (not pushed), cut from `main` (`9904ed5`).
It holds the commits below, cherry-picked in branch order, and they apply cleanly. Its backend
tree is **byte-identical** to `perf/fixes` (`backend/` diff empty), which is what was load-tested
(image `abc-bf7b7ff`) and what passed the backend suite (754 passed, 1 skipped, in the CI tests
image with the DB integration tests on). (**Verified**) No backend change between the live
backend (`8939818`) and `main`.

| Fix | perf/fixes | package | What | Migration |
|---|---|---|---|---|
| FIX-1 | `465427f` | `c1e41c8` | statement 15 s, lock 3 s and idle-in-transaction timeouts for API sessions; 3 s pool timeout; 503 + `Retry-After` on pool exhaustion | none |
| FIX-1 (cap) | `5c4de4b` | `e5917b5` | in-flight cap: requests over `MAX_IN_FLIGHT_REQUESTS` get 503 `SERVICE_BUSY` at once | none |
| FIX-6 | `0456ecb` | `624d9c1` | uploads cannot exhaust memory (header-only validation, downscaled JPEG decode, limiter, one publication per user in flight) | none |
| FIX-8 | `3fae54a` | `ccf01d6` | notification worker: a bad job fails alone; backlog drained in one pass | none |
| FIX-2 | `2b40b35` | `3f2fcb3` | nearby feed nearest-first through geography GiST indexes | `20261114_0032` |
| FIX-5 | `38a3f16` | `e84ea9d` | recent mixed feed: each branch limited before the merge | none |
| FIX-3 | `57cd0f2` | `766a097` | `views/seen`: a fixed number of statements per batch | none |
| FIX-4 | `e596e98` | `cb66dbf` | partial index: newest public post per cat (map pins) | `20261114_0033` |
| FIX-11 | `7455510` | `a6e3bac` | popular feed order index | `20261114_0034` |
| FIX-5 (hydration) | `174ec4f` | `fc1bcbe` | visible comment count through an index-only scan | `20261114_0035` |
| FIX-7 | `eaa3c6f` | `a089dd2` | CGNAT-tolerant rate-limit buckets (see 8.2) | none |
| A+B+C | `bf7b7ff` | `9d69d4a` | async no-I/O dependencies, one JWT decode per request, rate limiter as plain ASGI | none |

All four migrations only add indexes, built `CONCURRENTLY IF NOT EXISTS` outside a transaction
(no write lock), and the code before this package ignores them. (**From code**)

Index names: `idx_posts_location_geography_knn`, `idx_lost_pets_location_geography_knn` (0032),
`idx_posts_cat_public_latest` (0033), `idx_posts_popular` (0034), `idx_comments_post_visible`
(0035).

**The in-flight cap value to ship is pending 5b** (cap 16 vs 48 at the knee and at 300 users). The
code default is 48. It is set with `MAX_IN_FLIGHT_REQUESTS` in the production `.env`, so the value
can be changed later without a new image.

### 8.2 Why one package, and the one deviation from the requested list

**One package, not split** (recommendation):
- The schema part is additive and is applied while the old backend still serves. So the risky
  moment is a single backend + worker swap with a known rollback, the previous image. Splitting
  would mean two swaps, two Nginx reloads and two backups for the same rollback mechanics.
- The query fixes are where the capacity comes from. The "no outage" fixes are what keeps a
  traffic spike from becoming an outage. Shipping either half alone leaves the other risk open.
- The combination is exactly what was measured. A split ships an untested combination.

**FIX-7 is added** (not in the requested list).
- A+B+C rewrites the rate limiter on top of FIX-7's bucket code. Cherry-picking A+B+C without
  FIX-7 conflicts in `backend/app/core/rate_limit.py` (**Verified**).
- Including FIX-7 keeps the tested tree.
- FIX-7 changes behaviour. Read-only public GETs move to the public-read bucket, view telemetry
  gets its own bucket, and refresh is limited per refresh session with a per-IP backstop. Login
  and registration limits are unchanged. Its gate is the CGNAT run in 5c: 0 × 429 for a normal
  profile behind a shared IP.
- **If 5c fails, or you do not want FIX-7 now:** drop both FIX-7 and A+B+C from the package.
  A+B+C has no measured capacity gain (section 3), so nothing measured is lost. Rebasing A+B+C
  without FIX-7 would produce a new, untested tree and is not recommended.

**Not in this package:**
- The client changes (`6a5a3db` busy-retry UI and shared start-up requests; `6921c99` view
  batches every 30 s) are a web release (procedure A) plus an Android build.
- The old clients keep working: under overload they show the generic error instead of "busy,
  retrying". Recommended right after package 1.

### 8.3 Order, pre-checks and rollback per step

Assumptions (re-check at step 1): production runs backend image `8939818` at Alembic
`20261110_0031`, and its `.env` sets none of the new settings.

| # | Step (gate) | Pre-checks | Rollback |
|---|---|---|---|
| 0 | Merge: PR of `perf/deploy-package-1` into `main`, CI green, pushed (owner) | CI green on the merge commit; the release is built only from `origin/main` | not merged = nothing changed |
| 1 | Read-only inspection (G1): `remote-inspect.sh`, plus `health` | `alembic current` = `20261110_0031`; running image = overlay image; free disk for the indexes; no INVALID index: `select indexrelid::regclass from pg_index where not indisvalid` returns nothing; `.env` key **names** contain none of `DB_POOL_TIMEOUT_SECONDS`, `DB_STATEMENT_TIMEOUT_MS`, `DB_LOCK_TIMEOUT_MS`, `DB_IDLE_IN_TRANSACTION_TIMEOUT_MS`, `SERVICE_BUSY_RETRY_AFTER_SECONDS`, `MAX_IN_FLIGHT_REQUESTS`, `RATE_LIMIT_TELEMETRY_PER_MINUTE`, `RATE_LIMIT_REFRESH_PER_MINUTE`, `RATE_LIMIT_REFRESH_IP_PER_MINUTE` (or their values are reviewed) | none needed |
| 2 | Build locally, `build-backend-image.sh` from the merge commit (G0); stage the release directory and `docker load` (G2) | exactly one Alembic head (`20261114_0035`); image checksum; overlay: only the two image tags changed; `config --quiet` passes | delete the staged directory; the image tag is unused |
| 3 | Backup (G3): `backup-db.sh --execute`, copied off the server | `pg_restore --list` passes | none needed |
| 4 | Set the in-flight cap in the new release's `.env` if 5b recommends a value other than 48 (owner edits; key names compared only) | value from 5b | revert the line |
| 5 | **Indexes first** (G5), while the old backend serves: `$DC run --rm --no-deps -T backend alembic upgrade head` (new image) | low-traffic window; step 1 checks done | a build that fails or is cancelled leaves an INVALID index: `DROP INDEX CONCURRENTLY <name>`, then re-run. A finished index is kept (old code ignores it; no `alembic downgrade`, per runbook) |
| 6 | Check the indexes | `alembic current` = `20261114_0035`; all five indexes exist; the INVALID query returns nothing; the API stays healthy during the build | as step 5 |
| 7 | Swap (G4): stop the worker, wait until no push job is `sending`, recreate the backend, wait for healthy, recreate the worker, **immediately** `nginx -t && nginx -s reload` | backup < 12 h old; step 6 passed | runbook "Backend failed, schema additive": Compose from the previous release directory (previous image), worker stop → backend → healthy → worker → Nginx reload. Keep the indexes |
| 8 | Post-deploy checks (below) | | as step 7 |

**Post-deploy checks:**
- **Health and logs:** `/api/v1/health` 200; backend `healthy` with no restart loop; error count
  in the logs 0 over 10 min; db and Nginx container IDs unchanged.
- **Feeds and map, as guest and signed in:** recent, nearby (now nearest-first), popular, map
  pins (cats, lost pets, places), post detail with comments.
- **Views:** a `views/seen` batch counts once.
- **Uploads:** one photo publication succeeds; backend memory in `docker stats` back near idle
  afterwards.
- **Worker:** a test push is delivered, or the worker logs show the job processed.
- **Rate limits:** no 429 in the first hour of normal use.
- **CPU:** `remote-inspect.sh health` idle CPU close to before (backend ~2–3% of the core).
- **Record:** VERIFIED / FAILED / NOT VERIFIED per flow in the release record.

**Stop conditions → rollback (step 7 rollback):**
- 5xx or 503 `SERVICE_BUSY` under normal (not overload) traffic;
- a feed or map endpoint failing;
- the worker not draining;
- backend memory not returning to idle after an upload.

### 8.4 Separate: infrastructure items needing owner approval before deploy

These are committed on the branches but are **not** in package 1. Each changes the production
Nginx or Compose configuration and needs its own approval and procedure.

| Item | Commit | Change | Notes |
|---|---|---|---|
| Nginx API read timeout (FIX-1, LT-02) | `526628c` | cut non-upload API requests after 30 s | web/Nginx release unit (procedure A); not required for package 1: the API's own 15 s statement timeout and 3 s pool timeout already bound requests |
| Nginx resolver (FIX-9, LT-11) | `522fb40` | re-resolve the backend address at request time | removes the manual `nginx -s reload` after a backend swap; until then, step 7's reload is mandatory |
| Parallel query off (FIX-10, LT-17) | `903497f` | `docker-compose.prod.yml`: no parallel workers for the single-core database | **Every "after" measurement ran with parallel query off.** Package 1 without FIX-10 is therefore not the measured combination; it will be measured at the knee with parallel query on (queued with 5b). Applying it through Compose recreates the database container. `ALTER SYSTEM` + reload would avoid a restart, but it is also a production configuration change. Either way it needs approval |

## Superseded measurements

The load-test harness ran the backend healthcheck **every 10 s with the load-test shim on
`PYTHONPATH`**, so each check imported application modules: **1.28 s of workstation CPU per check
instead of 0.24 s** (**Verified**). Fixed in the harness (`0fac549`); the harness healthchecks now
match production's deployed containers (command, interval, timeout, retries, start timing;
**Verified** by read-only inspection, 2026-11-14). With it, the idle backend dropped from ~30% to
~4% of the production core (**Verified**). The harness's idle box (~6% of the core) is within two
percentage points of production's measured idle, slightly higher, so the floor is conservative
(**Verified**).

The following are **superseded** and must not be used for capacity decisions. They are kept in
place, unedited, for the record.

| Source | Statement | Why superseded | Replacement |
|---|---|---|---|
| REPORT.md §1, §3 | Single core saturates at 60–80 users; targets missed at 20 users | Box was a full workstation core (≈3–4 production cores), minus ~13% artefact | Section 3 above; stress ladder (pending) |
| REPORT.md §1 | "~11 ms of CPU per user-second", "one core 100% busy at ~90 users" | Bottom-up estimate from idle single-request timings; never measured | Slope: 13.1 ms (after), 34.9 ms (before) of a production core |
| REPORT.md §3.4 | 10× dataset saturates at 40 users | Same box and artefact as above | 10× run at the new knee (pending) |
| REPORT.md §3 (upload OOM) | Two max-size uploads OOM-kill the backend | Functional finding stands (FIX-6), but each shim healthcheck also loaded the app in the backend's memory; the margin is re-measured in the upload stress (pending) | Upload stress (pending) |
| Prod-sized runs 2026-11-13/14 (before-stress, baseline-after, stress-after, cap16, recovery runs) | Before: knee 10–15 users, Feed p95 > 1.4 s at 5 users; recovery 198 s → 31.6 s; 1,660 × 504 at 300 users with cap 48 | The artefact took ~30–45% of the emulated production core in every run | Re-runs (pending, task 5) |
| CPU-per-user measurements 2026-11-14 | 73.3 → 51.4 ms per user-second; ~13.6 users per core | Averages at 10 users that include the idle floor, with the artefact (~0.3 core) in the floor | Section 3 (floor 0.06 core, slope 13.1 ms) |
| Profile reading 2026-11-14 | "Postgres only ~14% of box CPU, the rest per-request Python" | Share of a box CPU inflated by the artefact | Slopes: Postgres ~36% of marginal cost |
| CPU runs 13:34:35 and 13:34:49 (2026-11-14) | Full-core CPU check | The two runs overlapped (driver edited while running); fixed in `008c72a` | Not needed (section 3) |

Not affected: correctness and concurrency tests, the query plans (EXPLAIN), and the unit and
integration test suites. Single-request query timings (`cost_probe`) ran with the artefact in the
background; their before/after ratios are plausible but were not re-measured (**Not checked**).
