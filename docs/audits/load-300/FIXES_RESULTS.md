# Load-audit fixes: results (DRAFT, in progress)

Branch `perf/fixes`. Status: capacity method and per-variant slopes measured (sections 2 and 3);
scenario re-runs, per-fix entries, capacity options, decision memos and deploy packages are still to
be written (verdict pending the stress ladder). Nothing here was deployed.

Evidence labels: **Verified** = measured here; **From code** = read, not reproduced;
**Not checked** = not done, with the reason. Hardware details stay in the private production notes;
this file uses only derived factors.

---

## 1. Verdict

Pending: the stress ladder on the production-calibrated box (task 5a) sets the latency knee.
What is already measured (section 3): after the fixes the box has CPU for **~48 concurrent active
users at 70% of the production core**, but the Feed p95 target (< 500 ms) is already missed at
40 users (542–572 ms) while the core is only ~60% busy. Before the fixes the Feed p95 was ~1 s at
10 users.

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
