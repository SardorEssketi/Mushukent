# Load tests (local, emulated production box)

Reproduces the measurements in `docs/audits/load-300/REPORT.md`. Everything runs on your
workstation in Docker. Nothing here talks to production, R2, PostHog, FCM or OpenStreetMap.

## One command

```bash
bash loadtest/run.sh all     # secrets -> stack -> seed x1 -> baseline, target, spike
```

Needs Docker, bash (Git Bash on Windows) and Python 3.11+ (a venv with Locust is created on
first use). The backend image `mushukistan-backend:${BACKEND_TAG:-8939818}` must exist locally
(build it with `scripts/deploy/build-backend-image.sh`, or set `BACKEND_TAG` to an image you have).

## Pieces

| Path | What it is |
|---|---|
| `compose.yml` | The emulated box: db, backend, notification-worker, nginx pinned to ONE shared CPU core (`cpuset: "0"`), memory caps without swap (sum ~1.8 GB), production image, `APP_ENV=production`, production uvicorn command and nginx config. `mocks` (R2 / PostHog sink) runs outside the box. |
| `loadtest.env` | Non-secret production-like settings (rate limits are the production values). |
| `shim/sitecustomize.py` | Redirects R2 to the mock, stubs FCM, logs connection-pool pressure. Active only with `LOADTEST_SHIM=1`. App code is unchanged. |
| `seed/seed.py` | Set-based seeding of Tashkent-area data (`--scale 1` realistic, `--scale 10`), mints access/expired/refresh tokens into `results/tokens.json`. Refuses non-local or non-"load"/"test" databases. |
| `locustfile.py` | Scenario model: guest/signed-in personas, background timers, cold starts, map pans with debounce-level pacing, uploads, refresh-on-401, per-IP identities via `X-Forwarded-For` (`LT_USERS_PER_IP` for CGNAT). Shapes: `baseline`, `target`, `spike`, `stress`, `soak`, `short`. |
| `tools/monitor.py` | docker stats + Postgres connections/locks/push backlog every 5 s. |
| `tools/summarize.py` | Per-endpoint p50/p95/p99, 429/5xx/timeouts, box and pool stats. |
| `tools/concurrency.py` | Hot-row likes, double submit, idempotency, contact reveal races, delete-while-viewing, token expiry, feed pagination drift. |
| `tools/upload_stress.py` | Concurrent max-size publications with a latency probe (memory / OOM). |
| `tools/guard.sh` | One heavy run at a time: a lock in `results/_runtime/`, a refusal when Locust or `upload_stress.py` already runs, a host free-memory floor (`LT_MIN_FREE_MB`, 1536) and a watchdog that stops a run below `LT_ABORT_FREE_MB` (1200) and writes `MEMORY_STOP`. A stopped run is never restarted automatically. Self-test: `bash tools/test_guard.sh`. |
| `tools/remeasure.sh` | Re-measurement driver. `slope <variant> [users...]` measures per-container CPU (kernel cgroup counters) in clean 300 s steady windows, 0 users = idle; `tools/slope_fit.py` fits floor + slope x users. |

## Typical runs

```bash
bash loadtest/run.sh up && bash loadtest/run.sh seed 1
bash loadtest/run.sh run target
bash loadtest/run.sh run spike LT_EXPIRED_TOKENS=1          # push-driven spike, stale tokens
bash loadtest/run.sh run stress
bash loadtest/run.sh run short LT_USERS=40 LT_USERS_PER_IP=40 LT_TAG=cgnat40
bash loadtest/run.sh run soak LT_SOAK_S=3600
loadtest/.venv/Scripts/python loadtest/tools/upload_stress.py loadtest/results/upload --concurrent 10 --files 5 --size max --monitor
loadtest/.venv/Scripts/python loadtest/tools/concurrency.py loadtest/results/concurrency
loadtest/.venv/Scripts/python loadtest/tools/cost_probe.py loadtest/results/cost-x1 15
docker exec -i mushukistan-load-db-1 psql -U mushukistan -d mushukistan_load < loadtest/tools/query_experiments.sql
bash loadtest/run.sh seed 10 && bash loadtest/run.sh run short LT_USERS=40 LT_TAG=x10
bash loadtest/run.sh destroy
```

The 10× seed inserts 12M `post_views` rows. On the capped one-core database that takes hours, so
give the db container more room **only while seeding** and restore the emulated limits before any
measurement:

```bash
docker update --cpuset-cpus 0-3 --memory 3g --memory-swap 3g mushukistan-load-db-1
bash loadtest/run.sh seed 10        # ~22 min
docker update --cpuset-cpus 0 --memory 768m --memory-swap 768m mushukistan-load-db-1
```

After any backend container restart, run `docker exec mushukistan-load-nginx-1 nginx -s reload`
(nginx resolves the backend address only at start; see REPORT finding LT-11).

Results are written to `loadtest/results/<timestamp>-<scenario>/` (gitignored): `summary.md`,
`requests.csv` (every request), `monitor.csv`, `pool.jsonl`, `pg_top.txt`
(pg_stat_statements), `status_counts.json`, `external_calls.json`.

## Caveats

* The workstation core is faster than a typical shared cloud vCPU, so absolute numbers are
  optimistic. Treat the knee of the curve, not the exact RPS, as the result.
* `pg_stat_statements` and lock-wait logging are enabled for observation; production runs
  Postgres with no overrides.
* OSM tiles are not requested at all. Tile volume is estimated in the report.
