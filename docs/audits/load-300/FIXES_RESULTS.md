# Load-audit fixes: results (DRAFT, in progress)

Branch `perf/fixes`. Status: capacity method and per-variant slopes measured (sections 2 and 3);
scenario re-runs, per-fix entries, capacity options, decision memos and deploy packages are still to
be written (verdict pending the stress ladder). Nothing here was deployed.

Evidence labels: **Verified** = measured here; **From code** = read, not reproduced;
**Not checked** = not done, with the reason. Hardware details stay in the private production notes;
this file uses only derived factors.

---

## 1. Verdict

**Measured capacity of the current box (one production core): 30 concurrent active users after
the fixes, against fewer than 10 before** (**Verified**). Targets: Feed p95 < 500 ms, map p95
< 700 ms.
- 30 users met the targets in 3 of 3 runs (Feed p95 263–420 ms).
- 35 users met them in 2 of 4 runs; 40 users in 1 of 5. 35 is the edge, not a planning figure.
- Before the fixes, the Feed p95 was already 984 ms at 10 users.

The first version of this verdict said ~35, from a single run at 35 users. Repeats with fresh test
tokens moved it to 30 (section 3.1). The earlier
"10–15 users before" figure came from artefact-affected runs and is superseded (see the last
section). The limit is latency from queueing on one core, not CPU. By CPU alone the box would
carry ~48 users at 70% (section 3).

Repeats at the knee show ±150 ms of run-to-run spread on the Feed p95. At 300 users an
in-flight cap of 16 sheds the excess in ~1 ms with 503 + `Retry-After`. It cuts the server p95
for served requests from 2.9 to 1.8 s and halves recovery (11–13 s vs 21–23 s). **But it also
sheds ~55% of requests during the first ~20 s of a 35–40-session start-up burst**, which cap 48
absorbs (slowly) without a 503. Of caps 16/24/32/48 and a 2 s wait queue, **cap 32** is the
best setup with zero refusals in the burst (section 3.2).

Still pending: uploads, CGNAT, spike, target 300, 10× data, soak (5c–5g).

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

**Capacity by latency: 35 active users in the first ladder** (superseded by the repeats below: **30**), the highest step that met both targets without the
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

**Run-to-run spread at the knee (5b repeats and fresh-token repeats).** Every plain run at 30–40
users, targets Feed < 500 / map < 700 ms (**Verified**). Runs marked "fresh" used valid test
tokens; the others started each signed-in session with one 401 + refresh (section 3.3).

| Users | Run | Feed / map p95 | Meets targets |
|---|---|---|---|
| 30 | cap 48, parallel query off | 344 / 260 ms | yes |
| 30 | cap 48, parallel query off, fresh (two runs) | 420 / 280, 263 / 273 ms | yes, yes |
| 35 | cap 48, parallel query off | 338 / 249 ms | yes |
| 35 | cap 16, parallel query off | 548 / 458 ms | **no** (Feed) |
| 35 | cap 48, parallel query **on** | 389 / 358 ms | yes |
| 35 | cap 48, parallel query off, fresh | 588 / 313 ms | **no** (Feed) |
| 40 | cap 48 (three runs) | 542 / 503, 572 / 409, 631 / 450 ms | no |
| 40 | cap 16 | 377 / 404 ms | yes |
| 40 | cap 48, parallel query off, fresh | 528 / 420 ms | no |

Data drift over the test days is small: ~9% more posts and ~10% more view rows than seeded. It
does not explain the spread.

No run at 35 or 40 users shed a single request **in the steady window** (0 × 503), so the cap
value cannot explain these differences: the spread is run-to-run noise, about ±150 ms on the Feed
p95 at this load. (Cap 16 does shed during the start-up burst before that window; section 3.2.)
Reading: **30 users meets the targets in 3 of 3 runs, 35 users in 2 of 4, 40 users in 1 of 5.**
Capacity for planning: **30 active users**. 35 is the edge.

### 3.2 In-flight cap 16 vs 48 (task 5b)

Image `bf7b7ff`, 1× data, parallel query off unless stated otherwise.

**Correction (5c, 2026-11-16): below the knee, cap 16 does cost something, during start-up
bursts.** The first version of this section said cap 16 shed 0 requests at 35 and 40 users. That
count covered only the steady window, after the 90 s warm-up. Over the whole run (**Verified**):

| Run | 503 sheds | When |
|---|---|---|
| cap 16, 35 users | 256 (14.7% of the first 180 s) | all within t = 10–30 s |
| cap 16, 40 users | 292 (14.7% of the first 180 s); 277 of 494 requests (56%) in t = 10–30 s | all within t = 10–30 s |
| cap 16, 40 users behind one IP (5c) | 121 | all within t = 10–30 s |
| cap 48, 40 users | 0 (first-180 s p95 4.2 s instead) | n/a |

The harness starts users at 10 per second. So 35–40 sessions open the app within ~4 s, and each
cold start fires three `users/me`, unread count, two follow-up checks, then the first feed or map
page. That burst puts more than 16 requests in flight. Cap 48 queues it (p95 4.2 s for ~20 s);
cap 16 refuses about half of it. For the current app, a 503 on `users/me` at start-up is a
retryable session-restore failure (an error with retry, no sign-out; section 8.5).

Whether real start-ups cluster like this (a push notification to everyone, a morning peak) is
**Not checked**. The cap value is therefore **open** (see the note at the end of this section).

**At 300 users (60 s ramp, 120 s hold, then the recovery probe):**

**Caveat: Locust (one process) was CPU-bound in all four 300-user runs** ("CPU usage above 90%"
from the first seconds). Its timings include its own queueing: it saw sheds take 13.6 s, while the
server answered them in 1.1 ms. The runs were therefore repeated with the per-request tracer and an
independent probe (`LT_SIDE_PROBE=1`: one health and one feed request per second outside Locust),
and the comparison below uses **server-side** times (`tools/overload_split.py`). The box itself
was at its CPU quota in all four runs. (**Verified**)

| At 300 users | cap 16 | cap 48 |
|---|---|---|
| Server time, 200s, p50 / p95 | **0.94 / 1.84 s** | 1.29 / 2.88 s |
| Server time, 503 sheds, p50 / p95 | 1.1 / 90 ms | none shed |
| Sheds (503 `SERVICE_BUSY` + `Retry-After`) | 21–27% of requests | 0 |
| 504s, timeouts, connection errors | 0 | 0 |
| Requests answered 200 (traced run) | 2,443 | 2,578 (+5%) |
| Pool wait p95 / thread-pool wait p95 (200s) | 362 / 710 ms | 618 / 1,034 ms |
| Event-loop lag, median of per-second p95 | 179 ms | 232 ms |
| Recovery to normal after the load stops (two runs each) | **10.7 s, 13.2 s** | 20.5 s, 22.9 s |
| Locust-side p95 (inflated by the generator) | 16.7–18.0 s | 22.3–23.2 s |

Reading (**Verified**):
- Cap 16 turns overload into fast 503s. Server latency for the requests it serves drops by about
  a third (p95 1.8 vs 2.9 s), and recovery takes half as long (11–13 s vs 21–23 s).
- The cost at 300 users is ~5% fewer requests answered 200. Below the knee there is no cost.
- Neither cap produced a 504 or a timeout. With cap 48 the server-side latency was still growing
  at the end of the hold; with cap 16 it was flat.
- **Not checked:** the independent probe's own tail (health p95 7–9 s, both caps) while the
  server-side shed time was ~1 ms. Requests waited somewhere outside the app's timed section
  (nginx/TLS on the throttled core, the accept queue, or the workstation). The 300-user client
  latency, as a real phone would see it, is therefore not measured. The relative comparison of
  the caps holds.

**Cap 24 and 32, and a short wait queue (follow-up, 2026-11-16).**

Same image, 1× data, parallel query off, fresh tokens. One run per cell. Queue variants use
image `cq-86f4a6e`, a prototype on the local branch `perf/cap-queue`, not in any package:
requests over the cap wait first-in, first-out up to 2 s for a slot (at most 64 waiting), then
503. (**Verified**)

| Setup | 40-user start-up burst: 503s | 300 users: server p95 of 200s | 300 users: shed share, server time of a shed | Recovery |
|---|---|---|---|---|
| cap 16 | 292 | **1.84 s** | 21–27%, 1 ms | 10.7 s, 13.2 s |
| cap 24 | 66 | 2.59 s | 8%, 0.6 ms | 13.9 s |
| **cap 32** | **0** | 2.92 s | 1%, 0.7 ms | **18.3 s** |
| cap 48 | 0 | 2.88 s | 0 | 20.5 s, 22.9 s |
| cap 16 + 2 s queue | 20 | 3.83 s (includes the wait) | 38%, **2.1 s** | 6.3 s |
| cap 24 + 2 s queue | 1 | 4.37 s (includes the wait) | 14%, **2.2 s** | 13.2 s |

Reading:
- Only cap 32 and cap 48 refused nothing in the burst. Cap 24 + queue came close (1 refusal).
- **The wait queue absorbs bursts but hurts sustained overload.** At 300 users the queue is
  always full, so every request over the cap waits the full 2 s and then a third of them are
  shed anyway. Served requests get ~1.5 s slower (p95 3.8–4.4 s vs 1.8–2.9 s), and a shed costs
  the client 2 s instead of 1 ms. Its only gain is faster recovery with cap 16 (6 s). A queue
  that helps both cases would need a much shorter wait or a smaller queue, and is not worth
  shipping on this evidence.
- **Among the setups with zero burst refusals, cap 32 is the best measured.** At 300 users it
  has the same p95 as cap 48 (2.9 s, within noise) and recovers in 18 s vs 21–23 s. Its
  overload benefit over 48 is small: it sheds only ~1% at 300 users. Its real advantage over
  48 is a hard upper bound on queued work.
- Single runs per cell; differences under ~10% are within noise.

**Recommendation: `MAX_IN_FLIGHT_REQUESTS=32`, no queue. Accepted by the owner (2026-11-16).**
- Zero refusals in a 40-session start-up burst, and overload behaviour no worse than 48.
- Cap 16's better overload numbers cost refusals at the knee, which the brief rules out.
- The queue prototype (`perf/cap-queue`, `86f4a6e`, ~45 lines of middleware logic with 4 tests;
  the backend suite passes, 758 passed) stays unmerged. The branch is kept for reference, with
  the results above. Settings: `IN_FLIGHT_QUEUE_SECONDS` (0 = off), `IN_FLIGHT_QUEUE_MAX`.

### 3.3 CGNAT, uploads (task 5c)

Package-1 configuration: image `bf7b7ff`, cap 16, parallel query **on** (no FIX-10), 1× data.

**40 users behind one IP (the FIX-7 gate).** Steady-window 429 share, by persona
(**Verified**):

| Run | guest feed | guest map | user feed | user map | user poster | all requests, whole run |
|---|---|---|---|---|---|---|
| before FIX-7 (2026-11-13) | 54.9% | 36.2% | 0% | 6.8% | 0% | 15.5% |
| before FIX-7, expired tokens | 56.7% | 42.6% | 8.9% | 10.4% | 16.1% | 21.4% |
| package 1 | 0.8% | 2.0% | 0% | 0.1% | 0% | 0.54% |
| package 1, expired tokens (refresh storm) | 3.0% | 2.4% | 0% | 0.1% | 0% | 0.80% |

- **Gate result: not met as written** ("0 × 429 for a normal profile behind a shared IP").
  - Signed-in users are at 0–0.1%.
  - Guests still see 1–3% 429s. They share one per-IP public-read bucket of 180/min, together
    with the token-less marker taps and places calls of signed-in users on that IP.
  - FIX-7 cuts the 429 share ~30× (15.5% → 0.54%), and the refresh storm no longer spills into
    signed-in reads.
- 429s on `users/me` (2 in the expired-token run) come from the per-user bucket during the
  start-up burst.

**Follow-up: `RATE_LIMIT_PUBLIC_READ_PER_MINUTE=360`** (cap 32, parallel query on, fresh tokens;
**Verified**):

| Run | guest feed | guest map | signed-in (all) | 429s by endpoint |
|---|---|---|---|---|
| 40 users / 1 IP | 3.5% | **0%** | **0%** | 12 × `POST /views/seen` |
| same, expired tokens | 4.5% | **0%** | **0%** | 16 × `views/seen`, 3 × `POST /posts/{id}/views` |

- **Every 429 left is view telemetry, none is a read.** Guest reads are at 0%. The telemetry
  bucket for guests defaults to the anonymous limit, 30/min per IP
  (`RATE_LIMIT_TELEMETRY_PER_MINUTE` unset), and all guests behind the IP share it.
- **No visible error (From code):** a failed `views/seen` batch is dropped silently; the cards
  can be reported again later. The cost is lost view counts for guests behind a shared IP.
- **Gate (guests ≤ 0.5% 429): not met as worded** (3.5–4.5% of guest-feed requests). Met if the
  gate is read as "no user-visible 429".
- **Owner decision (2026-11-16):** the gate is read as "no user-visible 429", which is **met**.
  `RATE_LIMIT_PUBLIC_READ_PER_MINUTE=360` goes into package 1 (step 4, approval-flagged).
- **Known limitation, accepted for package 1:** guest view counts are undercounted behind large
  shared IPs (invisible to users). Candidate fix if real traffic shows it matters:
  `RATE_LIMIT_TELEMETRY_PER_MINUTE=120` (an `.env` value, no new image; it raises only the
  view-telemetry bucket, but per user as well as per IP). Not applied, not measured.
- 503 sheds: all in the first 30 s (start-up burst, cap 16; section 3.2). After that, 0 × 5xx.

**Uploads: 10 concurrent publications × 5 max-size photos** (package 1: 7.99 MP, ~7.8 MB each, the
largest the new 8 MP cap accepts; the audit run used 24.6 MP, the largest accepted before FIX-6)
(**Verified**):

| | before FIX-6 (audit) | package 1 |
|---|---|---|
| Result | 2 at once: backend OOM-killed (exit 137) | 10 / 10 published (201), 33–109 s each |
| Backend memory peak | over its limit | 773 MiB |
| Box memory peak (docker stats) | n/a | 1,093 MiB, 78% of the box's memory limit, no OOM event |
| Feed / like probe during the burst, p95 | n/a | 751 / 610 ms (before: 213 / 114 ms) |

The earlier "after" upload run (2026-11-14, `upload-cap8-10-after`) ended in connection errors
and is not evidence. The first 5c attempt got 401s from expired tokens (below).

**Harness caveat: expired access tokens from 2026-11-15 00:21.** The test tokens were minted on
2026-11-14 with a 12 h lifetime. Runs after they expired started every signed-in session with one
401 + refresh, the client's normal recovery. Affected runs: the 5a repeats, 5b, the compatibility check and 5c CGNAT. The cost is one
extra refresh per signed-in session (mean session 8 min). That is small next to the session's
other requests, but it is not zero, and it makes the "expired tokens" runs nearly identical to the
normal ones. Tokens were re-minted (`seed --tokens-only`) before the valid upload run. Since
then, test tokens live 7 days, and `run.sh` refuses to start when they expire within 3 h
(`tools/token_check.py`). `LT_EXPIRED_TOKENS=1` still sends genuinely expired tokens.

### 3.5 10× data at 30 users (task 5f)

Package-1 configuration (image `bf7b7ff`, cap 32, public read 360), the seeded 10× dataset
(10× posts, users and comments; 12M view rows; database 4.6 GB, of which `post_views` 2.7 GB),
30 users, 300 s steady window. One run each. (**Verified**)

| Parallel query | Box CPU | Feed / map p95 | Errors | req/s |
|---|---|---|---|---|
| on (production setting) | saturated (0.997 core; db 0.57, backend 0.32) | 6.0 / 5.8 s | 0% | 6.9 |
| off (FIX-10) | saturated (0.997 core) | 6.4 / **15.8 s** | **7.3%** | 5.6 |

- **At 10× data the box does not hold 30 users.** The database's working set no longer fits in the
  box's memory: the 10× database is several times the memory the whole box has.
- The map pins query is the limit. Per `pg_stat_statements` in the parallel-on run, the two `/cats`
  bbox variants averaged **1.9–2.3 s per call**, reading 55k–92k blocks from disk and spilling
  167k–208k temp blocks. The `post_views` batch insert averaged 0.8 s (its unique index no longer
  fits in memory).
- Parallel query off is worse here, not better (the plans were not captured, so why is **Not
  checked**). **FIX-10 is therefore not recommended** in its current form (8.4).
- The capacity at 10× data was not located below 30 users (**Not checked**); the levers are the
  map-pin denormalisation and bbox caching (7.6), `post_views` retention (7.5), and more memory
  (section 6).

Index build times for the package-1 migrations at 10× data, `CREATE INDEX CONCURRENTLY` on the
box's one-core budget with the API stopped: knn posts 7.2 s, knn lost pets 0.6 s, cat latest post
2.3 s, popular 2.5 s, visible comments 3.3 s; no invalid index left (**Verified**). At production
data sizes (smaller than 1×) step 5 of 8.3 takes seconds.


### 3.4 Before / after per scenario and per key endpoint

**Per endpoint** (client side through nginx/TLS, 200s only, 300 s steady window; before = image
`8939818` at Alembic 0031, after = package-1 tree `bf7b7ff`; same harness, one production core,
1× data, parallel query on before and off after; **Verified**). Endpoints with fewer than 20
samples in the window are left out (the first feed pages).

| Endpoint | 10 users, before → after: p50 / p95 ms | 20 users, before → after: p50 / p95 ms |
|---|---|---|
| `GET /cats` (map pins) | 124 / 568 → 90 / 289 | 925 / 4,904 → 89 / 242 |
| `GET /lost-pets/map` | 30 / 238 → 28 / 99 | 569 / 3,029 → 29 / 108 |
| `POST /views/seen` | 428 / 1,692 → 44 / 219 | 4,296 / 14,670 → 48 / 165 |
| `GET /feed` recent, later pages | 516 / 1,123 → 59 / 159 | 1,290 / 6,336 → 62 / 180 |
| `GET /posts/{id}` | 39 / 341 → 28 / 85 | 781 / 3,674 → 31 / 104 |
| `GET /posts/{id}/comments` | 59 / 248 → 42 / 92 | 688 / 3,290 → 50 / 129 |
| `GET /cats/{id}/posts` (marker tap) | 34 / 365 → 28 / 203 | 689 / 4,091 → 30 / 110 |
| `GET /notifications/unread-count` | 32 / 147 → 24 / 170 | 602 / 2,869 → 30 / 114 |
| `GET /users/me` | n/a | 523 / 2,688 → 30 / 241 |
| `GET /feed` nearby, later pages | n/a | n/a → 96 / 262 |

At 20 users the old tree was saturated (every endpoint queued behind the slow ones); the new tree
at 20 users is faster on every endpoint than the old one at 10.

**Per scenario.** Pass criteria from the brief: Feed p95 < 500 ms, map p95 < 700 ms, 5xx < 0.5%,
no timeouts, 0 × 429 for a user with their own IP, no OOM or restart in upload stress, no drift in
the soak, self-recovery ≤ 60 s. "Before" figures come from the same harness where one exists; the
original audit's figures carry the healthcheck artefact (last section) and are marked.

| Scenario | Before | After (package 1) | Pass? |
|---|---|---|---|
| Knee (5a) | Feed p95 984 ms at 10 users; saturated at 20 | 30 users meet the targets in 3/3 runs, 35 in 2/4 (3.1) | yes, at 30 |
| CPU per request | 148 ms of a production core | 55.9 ms, 2.6× less (3) | n/a |
| 300 users, overload (5b; replaces 5e) | audit: 48.7% of requests failed for users, 1,660 × 504 (artefact-affected) | cap 32: server p95 of 200s 2.9 s; 1% shed in ~1 ms with 503 + `Retry-After`; 0 × 504 or timeouts; recovery 18 s (3.2) | shedding and recovery yes; latency no (10× the capacity) |
| Spike with expired tokens (5d) | audit: the refresh storm spilled into reads | PENDING_5D | PENDING_5D |
| CGNAT, 40 users / 1 IP (5c) | 15.5% 429 (guests 36–57%) | reads 0%; guest view telemetry 3.5–4.5%, invisible (3.3) | yes (owner's reading of the gate) |
| Uploads, 10 × 5 max-size photos (5c) | 2 at once OOM-killed the backend | 10/10 published, box memory peak 78%, no OOM (3.3) | yes |
| 10× data at 30 users (5f) | audit: saturated at 40 users (artefact-affected) | box saturated: Feed / map p95 6.0 / 5.8 s, 0 errors (parallel query on); 6.4 / 15.8 s, 7.3% errors with it off (3.5) | **no**: capacity at 10× data is below 30 users |
| Soak, 1 h at 30 users (5g) | not run before | PENDING_5G | PENDING_5G |

**5e (target 300, short) was replaced** by the traced 300-user runs of 5b and the cap follow-up
(owner decision, 2026-11-16). Those runs already show the overload shedding and recovery that 5e
was meant to confirm. With one Locust process, a full 300-user target run measures the load
generator more than the server (3.2).

## 4. Per-fix entries

Gains under load were measured for the package as a whole (sections 3 and 3.4); fixes were not
load-tested one at a time. The per-fix gain below is the query- or endpoint-level measurement
behind the fix, plus where it shows in the endpoint table. Backend suite on the package tree:
754 passed, 1 skipped, DB integration tests on (**Verified**).

| Fix | What changed | Tests | Measured gain | Deviation from PROPOSED_FIXES, and why |
|---|---|---|---|---|
| FIX-1 `465427f` | 3 s pool timeout; statement 15 s, lock 3 s, idle-in-transaction 15 s on API connections; pool exhaustion and cancellations → 503 `SERVICE_BUSY` + `Retry-After` | `test_fail_fast.py` | Overload no longer becomes an outage: 0 × 504 or timeouts at 300 users, recovery 18 s with cap 32 (the audit box was still unusable after 10 min) (**Verified**) | Statement timeout 15 s, not 8 s: staged at the app's own request timeout, so it never cuts a request the client still waits for. Migrations, scripts and the worker keep engines without limits |
| FIX-1 cap `5c4de4b` | in-flight cap: 503 `SERVICE_BUSY` at once above `MAX_IN_FLIGHT_REQUESTS` (code default 48; package 1 sets 32); health never shed | `test_load_shedding.py` | Shed in ~1 ms; cap 32: zero refusals in a 40-session burst (3.2) (**Verified**) | Not in the proposal: added because sync handlers keep running after the client gives up |
| FIX-2 `2b40b35` | nearby feed nearest-first: KNN on geography GiST indexes, (limit+1)-th distance bound per branch; cats nearby box scaled by latitude | `test_feed_nearby_knn.py` | 10× data, page 1: 1,101 → 39 ms; page 10: 2 ms (query level, audit). The 6–9 s plan one statistics change away is gone (**Verified**) | Bound-then-collect instead of a plain `LIMIT`, so ties at one spot are never cut; the spheroid radius filter is kept (same items). The 1× stop-gap box prefilter was not shipped |
| FIX-3 `57cd0f2` | `views/seen`: one visibility read per kind, one insert, one ordered increment per kind | `test_post_views_batch.py` | ~80 statements per batch → a fixed handful; endpoint p95 1,692 → 219 ms at 10 users (3.4) (**Verified**) | As proposed. The 30 s client interval is a separate client commit (`6921c99`) |
| FIX-4 `e596e98` | partial index on the newest public post per cat (map pins) | backend suite | SQL part at z14: 19.6 → 10.8 ms (audit); `/cats` p95 568 → 289 ms at 10 users (3.4) | Index name differs. The denormalised "latest public post" column was not done (it needs a decision) |
| FIX-5 `38a3f16` | recent mixed feed: cursor and `limit + 1` per branch before the merge | `test_feed_recent_parity.py` (page-by-page parity with the old global sort, ties across kinds) | key query 26 → 1.3 ms (audit); later pages p95 1,123 → 159 ms at 10 users (3.4) | As proposed; the old nearby code this path no longer used was removed |
| FIX-5 hydration `174ec4f` | index-only count of the comments a viewer can see, per card | backend suite | answers the proposal's "a signed-in page costs ~80 ms more" follow-up: popular cards no longer read hundreds of comment rows each (plan; not load-tested alone) | Follow-up of FIX-5, not in the proposal's patch |
| FIX-6 `0456ecb` | header-only validation; one reduced-scale JPEG decode; one processing slot; one publication per user in flight (409 `PUBLICATION_IN_PROGRESS`); pixel cap 25 → 8 MP | `test_upload_memory.py`, `test_uploads.py` | 10 concurrent max-size publications: before, OOM at 2; after, 10/10 with box memory peak 78% (3.3) (**Verified**) | Pixel cap 8 MP, not ~16 MP: twice what any client sends (every app build resizes to 1920 px first, **From code**) |
| FIX-7 `eaa3c6f` | read-only public GETs → public-read bucket; own view-telemetry bucket; refresh per refresh session with a per-IP backstop | `test_rate_limit_buckets.py` | CGNAT 40 users / 1 IP: 15.5% → 0.54% 429s at 180/min; reads 0% at 360/min (3.3) (**Verified**) | Non-policy parts only: per-IP ceilings unchanged in code (360 comes from the `.env`); no install-id keying. The client part (token on marker taps and places, busy/`Retry-After` UX) shares commit `6a5a3db` with LT-21 (one `users/me` at start-up), because both change the same start-up and map request code |
| FIX-8 `3fae54a` | worker: a bad job fails alone (data errors terminal, transport errors retried); keeps claiming while batches come back full | `test_notification_worker_resilience.py` | removes the ~100 pushes/min ceiling (From code; backlog drain not load-tested) | As proposed |
| FIX-9 `522fb40` | nginx re-resolves the backend through Docker DNS (10 s) | manual: backend recreated, the 502s stopped without a reload (**Verified**) | removes the 22,378 × 502 failure mode | As proposed. Infrastructure, needs owner approval (package 2) |
| FIX-10 `903497f` | `max_parallel_workers_per_gather=0` in the prod Compose file | n/a | 1×: none measurable (+3%, within noise; 8.4); 10×: **worse** with it off (map p95 15.8 vs 5.8 s, 7.3% vs 0% errors; 3.5) | Optional (owner decision); package 2 |
| FIX-11 `7455510` | popular feed order index | backend suite | the popular page reads its rows from the index instead of scan + sort (plan) | Predicate `deleted_at IS NULL` only (the proposal also had `is_public`): a slightly larger index that also serves non-public rows |
| LT-02 nginx `526628c` | 30 s read timeout for non-upload API requests | n/a | not load-tested alone; the 15 s statement and 3 s pool timeouts already bound requests | Infrastructure, package 2 |
| A+B+C `bf7b7ff` | async no-I/O dependencies; one JWT decode per request; rate limiter as plain ASGI | `test_request_overhead.py` (3 → 1 decodes), `test_rate_limit_asgi.py`, `test_auth.py` | **none measurable** (slope 13.05 vs 13.10 ms) (3) | Kept: behaviour-neutral and tested, and FIX-7 sits on its limiter rewrite |
| Client `6a5a3db`, `6921c99` | busy countdown with `Retry-After` on feed and map; token on marker taps and places; shared `users/me`; seen batches every 30 s | `busy_and_single_flight_test.dart`; Flutter suite 849 passed | old-client compatibility verified (8.5); the new client's own effect was not load-tested separately | Web + Android release, package 2 |
| Queue prototype (not shipped) | `perf/cap-queue` `86f4a6e`: up to 2 s FIFO wait before shedding | 4 tests; backend suite 758 passed | hurts sustained overload (3.2) | Not merged (owner decision) |

D (orjson responses) was skipped by the owner.

## 5. Behaviour changes a user could notice

All **From code** unless marked. None changes data or permissions.

- **Overload.** Instead of a long spinner and then a timeout, an overloaded API answers 503 within
  milliseconds. The current app shows its generic error with a retry button. The new app shows
  "busy, retrying in N s" on the feed and map and retries by itself (`Retry-After`, back-off up
  to 60 s). At start-up, either app shows "session unavailable" and reconnects after 3–48 s,
  without signing the user out (8.5). With cap 32, no start-up 503 occurred in a 40-session burst
  (**Verified**).
- **Slow requests end at 15 s** with a 503 instead of running on; the app already gives up at 15 s.
- **Nearby feed** is ordered nearest-first by sphere distance (about 0.3% different from the old
  spheroid distance), so items at almost the same distance can swap places. The set of items is
  the same.
- **Cats "nearby" filter** now finds the ~13% of cats east or west of the user that the old box
  missed.
- **Uploads.** A second publication from the same account while one is still uploading gets 409
  `PUBLICATION_IN_PROGRESS`; the app sends one at a time, so app users do not see it. Images over
  8 MP are refused; every app build resizes to 1920 px first, so only direct API callers are
  affected.
- **Rate limits.** Far fewer 429s for people behind a shared mobile IP. Guest view counts can be
  undercounted behind large shared IPs (invisible; 3.3). Login and registration limits are
  unchanged.
- **Push notifications** arrive sooner after a backlog, and one broken device token no longer
  holds up everyone else's.
- **View counts** (new client) are sent every 30 s instead of 10 s, so a count can lag by up to
  30 s.
- **Package 2 infrastructure:** with the nginx resolver, the API keeps working after a backend
  recreate without a manual reload; with the 30 s timeout, non-upload API requests are cut at
  nginx after 30 s (none legitimately take that long).

## 6. Capacity options

PENDING_6

## 7. Decision memos

PENDING_7

## 8. Deploy package 1: "no outage" + query fixes + A+B+C

**Measured capacity of the current box: 30 concurrent active users after the fixes (35 is the edge), against
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

**In-flight cap: 32** (section 3.2), set in the production `.env` at step 4. The code default
stays 48. The value can be changed later without a new image.

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
- **5c result:** at the code default (180/min) guests still saw 1–3% 429s; with
  `RATE_LIMIT_PUBLIC_READ_PER_MINUTE=360` guest and signed-in reads are at 0%, and the only 429s
  left are guest view telemetry, which no user sees (section 3.3). The owner reads the gate as
  "no user-visible 429": **met, with 360 in the `.env`** (step 4).
  - Dropping FIX-7 would bring back the 15.5% whole-run 429 share.
- **If 5c fails, or you do not want FIX-7 now:** drop both FIX-7 and A+B+C from the package.
  A+B+C has no measured capacity gain (section 3), so nothing measured is lost. Rebasing A+B+C
  without FIX-7 would produce a new, untested tree and is not recommended.

**Not in this package:**
- The client changes (`6a5a3db` busy-retry UI and shared start-up requests; `6921c99` view
  batches every 30 s) are a web release (procedure A) plus an Android build.
- The old clients keep working with the new backend (section 8.5). Rollout order and gates are in
  section 8.6.

### 8.3 Order, pre-checks and rollback per step

Assumptions (re-check at step 1): production runs backend image `8939818` at Alembic
`20261110_0031`, and its `.env` sets none of the new settings.

| # | Step (gate) | Pre-checks | Rollback |
|---|---|---|---|
| 0 | Merge: PR of `perf/deploy-package-1` into `main`, CI green, pushed (owner) | CI green on the merge commit; the release is built only from `origin/main` | not merged = nothing changed |
| 1 | Read-only inspection (G1): `remote-inspect.sh`, plus `health` | `alembic current` = `20261110_0031`; running image = overlay image; free disk for the indexes; no INVALID index: `select indexrelid::regclass from pg_index where not indisvalid` returns nothing; `.env` key **names** contain none of `DB_POOL_TIMEOUT_SECONDS`, `DB_STATEMENT_TIMEOUT_MS`, `DB_LOCK_TIMEOUT_MS`, `DB_IDLE_IN_TRANSACTION_TIMEOUT_MS`, `SERVICE_BUSY_RETRY_AFTER_SECONDS`, `MAX_IN_FLIGHT_REQUESTS`, `RATE_LIMIT_PUBLIC_READ_PER_MINUTE`, `RATE_LIMIT_TELEMETRY_PER_MINUTE`, `RATE_LIMIT_REFRESH_PER_MINUTE`, `RATE_LIMIT_REFRESH_IP_PER_MINUTE` (or their values are reviewed) | none needed |
| 2 | Build locally, `build-backend-image.sh` from the merge commit (G0); stage the release directory and `docker load` (G2) | exactly one Alembic head (`20261114_0035`); image checksum; overlay: only the two image tags changed; `config --quiet` passes | delete the staged directory; the image tag is unused |
| 3 | Backup (G3): `backup-db.sh --execute`, copied off the server | `pg_restore --list` passes | none needed |
| 4 | `.env` changes for the new release (owner edits; key names compared only): `MAX_IN_FLIGHT_REQUESTS=32`; `RATE_LIMIT_PUBLIC_READ_PER_MINUTE=360` (both approval-flagged config items) | both keys absent before (step 1) | remove the lines (back to the code defaults, 48 and 180) |
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
| Parallel query off (FIX-10, LT-17) | `903497f` | `docker-compose.prod.yml`: no parallel workers for the single-core database | **Optional for package 1.** Package 1 without FIX-10 (parallel query on, the production setting) was measured at the knee: 35 users, Feed / map p95 389 / 358 ms, 0 errors, box CPU 0.510 vs 0.494 core with it off (+3%, within noise). It meets the targets (**Verified**, 1× data). **At 10× data, turning it off made things worse** (map p95 15.8 vs 5.8 s, 7.3% vs 0% errors; section 3.5), so FIX-10 is not recommended as it stands. Applying it through Compose recreates the database container. `ALTER SYSTEM` + reload would avoid a restart, but it is also a production configuration change. Either way it needs approval |

### 8.5 Backward compatibility: un-updated clients on the new backend

**Live check (Verified).** The harness models the client as it is on `main` today, the build
users have. It makes three `GET /users/me` at start-up, sends `POST /views/seen` every 10 s,
sends map marker taps and places without a token, and polls unread count and follow-ups once a
minute. The check ran 20 users for 5 min on the package backend (`bf7b7ff`), one IP per user,
cap 48:
- 1,887 requests: **0 × 429, 0 × 5xx, 0 × 503**.
- Token-less marker taps and places: all 200. `views/seen`: all 200.
- 13 × 401 on `users/me` (expired access tokens), each followed by a successful refresh and
  retry.
- 9 × 409 on like (post already liked) and 1 × 422 on save (`CANNOT_SAVE_OWN_POST`, the harness
  picked the user's own post). Both are existing behaviour; neither route changes in the package.
- Feed and map p95 ~150–260 ms after the first 40 s (the cold start of 20 sessions at once is
  slower: p95 2.7 s in the first 20 s).

Behind one shared IP (CGNAT) the gate is the 5c run.

**Behaviour on 503 `SERVICE_BUSY` (From code).**
- The old client maps any 5xx to a retryable server error, shows its generic error with a retry
  button, and keeps the session. A 503 during session restore, or on `POST /auth/refresh`, does
  not delete the token or sign the user out. Only 401/403/404 do that, and the package does not
  change those.
- What changes for old clients: under overload, a user sees "request failed, retry" sooner,
  instead of a long spinner. A user can tap retry at once; each refused request costs the server
  ~1 ms (section 3.2).

**Start-up 503 (`users/me` during session restore), old and new client alike (From code).** The
auth code is the same on `main` and `perf/fixes`.
- A 503 makes session restore a retryable failure. The app shows its "session unavailable"
  screen, keeps the session, and reconnects automatically after 3, 6, 12, 24 and 48 s. There is
  also a retry button, and the app re-checks when resumed.
- It does not read `Retry-After` there. The new client's `Retry-After` handling (`6a5a3db`,
  busy countdown with 2–60 s backoff, no manual retry while busy) covers the feed and map
  screens only.
- With cap 32 no start-up 503 occurred in the 40-session burst, so this path is a fallback.
- Backlog (owner, 2026-11-16; not implemented): the start-up session check should honour
  `Retry-After` on 503/429 (section 9).

### 8.6 Rollout order and gates: backend → web → Android

| # | Step | Depends on | Gate | Can ship independently? |
|---|---|---|---|---|
| 1 | Backend package 1 (section 8.3) | merge to `main`, CI green | G0–G6, post-deploy checks | yes; old clients work with it (8.5) |
| 2 | Web build with `6a5a3db` + `6921c99` (procedure A) | nothing on the server; recommended after 1 so "busy, retrying" has a 503 `SERVICE_BUSY` to react to | web release gates; smoke on the live site | yes (below) |
| 3 | Android release (same two commits, new build number) | nothing on the server | Play internal track, then production | yes (below) |

The new client also works with the old backend (From code):
- It sends `views/seen` batches of at most 20 items, the limit the backend already enforces; only
  the interval changes (30 s instead of 10 s).
- Concurrent `users/me` requests are shared on the client.
- "Busy" handling triggers on 429 (which the old backend already sends, with `Retry-After`) or on
  503 with code `SERVICE_BUSY`; otherwise the old error handling applies.

So the three steps can ship in any order. The recommended order is backend → web → Android, for
two reasons:
- The backend carries the capacity gain.
- The client change only shows its benefit once the backend sheds with `SERVICE_BUSY`.

Android users update slowly, so the old-client behaviour in 8.5 is what most users will see for
weeks.

## 9. Deploy package 2: everything else (plan only)

Package 1 already carries every migration (0032–0035, all `CONCURRENTLY` index builds, applied
before the backend swap; 8.3). **Package 2 has no migration.** It is four units, each with its own
approval. None is needed for package 1 to work. **2a and 2c are one release unit:** the web build and
the nginx config ship together (procedure A), so whatever nginx config is on `main` goes out with
the next web release. To ship the client without the nginx changes, keep `522fb40` and `526628c` off
`main` until they are approved.

| # | Unit | Commits | Procedure and approval | Pre-checks | Rollback | Post-deploy checks |
|---|---|---|---|---|---|---|
| 2a | Web build with the client changes | `6a5a3db`, `6921c99` | web release, procedure A (`release-web`: prepare, owner `approve`, deploy) | package 1 live (so `SERVICE_BUSY` exists); Flutter suite and analyze green on the merge commit | `release-web rollback` to the previous web release (owner-signed approval) | sign-in, feed, map with marker tap and places, a like, a publication; views counted once; on a forced 429 the busy countdown shows |
| 2b | Android release | same two commits, new build number | Play internal track, then production (owner) | as 2a; device QA on a slow network (section 10) | halt the staged rollout; the old build keeps working (8.5) | as 2a on a device; crash-free rate in the Play console |
| 2c | nginx: re-resolve the backend (FIX-9) and the 30 s API read timeout (LT-02) | `522fb40`, `526628c` | `infrastructure/` change, **needs owner approval before deploy**; ships with a web release (same unit as 2a) | `nginx -t` in the staged release; upload routes keep 180 s | previous `default.conf` from the previous release directory, `nginx -t && nginx -s reload` | `/api/v1/health` 200; a photo publication succeeds (180 s route); recreate the backend once in a quiet window and confirm the API answers **without** an nginx reload |
| 2d | Parallel query off (FIX-10): **not recommended** (3.5) | `903497f` | prod Compose change, **needs owner approval before deploy**; recreates the db container (seconds of downtime) or `ALTER SYSTEM` + reload (no restart, still a config change) | backup < 12 h old (G3); package 1 live (FIX-2 must be in first: with parallel query off, the old nearby plan goes from ~1 s to 6–9 s) | set it back to 2 (Compose) or `ALTER SYSTEM RESET` + reload | `show max_parallel_workers_per_gather` = 0; nearby feed and map p95 in the logs no worse over a day |

Recommended order: 2a → 2b (the client benefit only shows once package 1 sheds with
`SERVICE_BUSY`), 2c together with 2a once approved (otherwise 2a without it), 2d **not recommended**: at 10× data, parallel query off made the map
p95 15.8 s instead of 5.8 s, with 7.3% errors (3.5).

Not in either package (decisions first, section 7): the Redis rate-limit store with several
workers, a tile provider or cache, the telemetry rate limit, `post_views` roll-up, dropping response
models on hot paths, the start-up `Retry-After` change (backlog, 8.5).

## 10. Not checked

- **Real devices and networks:** browser and Android flows on slow or lossy mobile networks, and how
  often real clients reconnect and redo the TLS handshake (Locust keeps one keep-alive session per
  user).
- **Real start-up clustering:** whether real start-ups bunch up like the harness's 10 sessions per
  second (a push to everyone, a morning peak). It decides how much the cap value matters (3.2).
- **The 300-user tail as a phone sees it:** at 300 users the side probe saw 7–17 s while the server
  shed in ~1 ms; the wait outside the app (nginx/TLS on the throttled core, the accept queue, or the
  workstation) was not located (3.2).
- **The new client under load:** the harness models the current client (8.5). The new client's
  30 s view batches and shared `users/me` lower the load a little; not measured.
- **Per-fix gains under load:** fixes were load-tested together (section 4).
- **Notification backlog drain** (FIX-8) under load, and push delivery at volume (FCM is mocked).
- **Tile load:** basemap tiles come from a third-party tile server and were not part of the load
  (section 7).
- **Production row counts and data shape** vs the seed: capacity is measured on the seeded 1× and
  10× sets; production is far smaller today.
- **Option (b) CPU classes** are an estimate from public benchmarks (section 6), not measured.
- **Options (d) and (e)** are not measured (section 6).
- **Single-request query timings (`cost_probe`)** ran with the harness artefact in the background
  and were not re-measured (last section).
- **Old-client 503 path on a device:** the "session unavailable" and retry behaviour is read from the
  code, not exercised on a device.

## Superseded measurements

**300-user runs measured with one Locust process (all dates).** Locust was CPU-bound from the
start ("CPU usage above 90%"), so its latencies at 300 users include generator queueing: up to
~10 s at the median (section 3.2). The original audit's 300-user latency figures carry the same
artefact. The pass/fail verdict at 300 users stands, because the box was at its CPU quota and
server-side latency was 1–3 s. The absolute client-side seconds do not stand.

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
