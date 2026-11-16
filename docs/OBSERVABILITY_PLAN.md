# Minimal production observability (LT-20): plan

Status: **proposal**, not implemented, nothing deployed. Owner request 2026-11-16. Builds on
package 1 (in-flight cap, pool timeout → 503 `SERVICE_BUSY`). Capacity figures come from
`docs/audits/load-300/FIXES_RESULTS.md` on `perf/fixes`: the current box carries **30 concurrent
active users** within Feed p95 < 500 ms and map p95 < 700 ms, and 30 users make ~7 requests per
second (mean ~0.24 requests per second per user).

Labels: **From code** = read in this repository; **Not checked** = not verified.

## 1. What we already run (From code)

- **PostHog** (the backend's `POSTHOG_PROJECT_TOKEN` / `POSTHOG_HOST`): product events through the
  PostHog Python client (`app/core/analytics.py`). Separately, OTLP log export for one dedicated
  logger (`app/core/posthog_logging.py`), used today for publication diagnostics only.
- **structlog** JSON logs on the backend's stdout, kept by Docker.
- **nginx** in the official image with no `access_log`/`log_format` in our config. The default
  `combined` format goes to stdout. It has status codes but **no request time**.
- **`scripts/deploy/remote-inspect.sh health`**: container health, `RestartCount`, start time
  (manual, read-only).

Nothing aggregates, keeps history or alerts today.

## 2. Proposal: two small steps

### Step 1: one summary event per minute from the backend (no infrastructure change)

A small in-process aggregator, fed by one ASGI middleware at the outer edge of the stack, so that
it also sees 503 sheds and 429s. Once a minute it sends **one** PostHog event, `api_health_minute`,
with:

| Property | How |
|---|---|
| `p50_ms`, `p95_ms`, `count` per key endpoint: feed (recent/nearby/popular/needs_help), map pins `/cats`, `/lost-pets/map`, `views/seen`, `users/me`, `auth/refresh`, uploads | route template (not the raw path), elapsed time per request; fixed list, everything else as `other` |
| `status_503_busy`, `status_503_pool`, `status_429`, `status_5xx_other`, `status_4xx` | counted at response start; cap vs pool told apart by a request-state flag set where each 503 is built (today the reason is only logged) |
| `in_flight_max`, `cap` | read from `LoadSheddingMiddleware` |
| `pool_wait_p95_ms`, `pool_wait_max_ms`, `pool_timeouts` | SQLAlchemy pool `checkout` events, timed from connect to checkout (the load-test shim already measured this way) |
| `active_users_1m`, `active_users_5m` | distinct actors with ≥ 1 request in the window: user id from the verified token, otherwise a salted hash of IP + user agent; only the **count** leaves the process, kept in memory only |
| `requests_per_s` | count / 60 |
| `uptime_s`, `worker_pid`, `release` | a restart shows up as `uptime_s` dropping; `release` = image tag |

- **Cost:** one event per minute per worker, ~44k events a month. PostHog's free event allowance
  is far larger (current figure **Not checked**). CPU: one `perf_counter` and a dict update per
  request, plus a sort of at most a few hundred samples per minute. That is well under 1% of the
  measured 55.9 ms per request. It must still be confirmed with one knee run on the harness
  before release.
- **Sending:** through the existing safe PostHog client, from a background task, never on the
  request path. If PostHog is not configured, the minute summary is written as one structlog line
  instead, so `docker logs` still has it.
- **Restarts and OOM:** an `api_started` event at start-up, with `release`. A restart without a
  deploy is the alert. Docker's `OOMKilled` flag is not visible from inside the container (step 2).

### Step 2: nginx request time and host-level signals (infrastructure, needs owner approval)

- `log_format` with `$request_time`, `$upstream_response_time`, `$upstream_status` and the route
  in JSON, still on stdout. This adds **502/504**, which the backend never sees: in the 300-user
  spike, 504s came from nginx's 30 s timeout while the backend saw nothing (FIXES_RESULTS 3.6).
- Docker log rotation (`max-size`/`max-file`) for nginx and the backend, if not already set on the
  host (**Not checked**).
- A host `systemd` timer, every minute: count nginx 502/504 in the last minute
  (`docker logs --since 1m`), read `RestartCount` and `State.OOMKilled` for each container, and
  send one PostHog event, `host_health_minute`. It is a new script on the production host, a
  production change with its own approval and procedure.

Step 1 covers everything asked except 504/502 and OOM; step 2 covers those.

## 3. Alerts (PostHog insight alerts on `api_health_minute`)

Thresholds are tied to the measured capacity (30 users, Feed p95 < 500 ms):

| Signal | Warn | Critical |
|---|---|---|
| Active users (5 min) | ≥ 20 for 10 min (two-thirds of capacity) | ≥ 28 for 10 min |
| Requests per second | ≥ 4.7 for 10 min (≈ 20 users at the measured rate) | ≥ 6.5 for 10 min |
| Feed p95 (any feed) | > 400 ms for 10 min | > 500 ms for 10 min |
| Map pins p95 | > 550 ms for 10 min | > 700 ms for 10 min |
| 503 `SERVICE_BUSY` (cap or pool) | any in 10 min | > 1% of requests in 10 min |
| Pool timeouts | any | > 5 in 10 min |
| 429 | > 1% of requests in 10 min | > 5% |
| Restart (`api_started` without a deploy) | any | ≥ 2 in 1 h |
| 504/502 (step 2) | any | > 0.5% in 10 min |
| OOM (step 2) | n/a | any |

- A warn on active users or Feed p95 is the trigger in memo 7.1 to prepare the next hosting step
  and the start-up `Retry-After` change.
- **Not checked:** how often PostHog evaluates insight alerts on the current plan, and its
  notification channels. If the interval is too coarse for "10 minutes", step 1's structlog line is
  the fallback for manual checks, and the thresholds become "per hour".

## 4. Privacy

- No user ids, IPs or user agents leave the process. Active users is a count, and the in-memory
  set is cleared every window.
- The salt for the guest hash is generated at start-up and never stored.
- Route templates, not raw paths, so no ids appear in properties.
- The privacy policy already covers PostHog analytics. Whether operational metrics need a mention
  is for the owner (**Not checked**).

## 5. Implementation outline (step 1)

1. `app/core/ops_metrics.py`: aggregator (per-route samples capped at 2,000 per minute,
   reservoir), counters, active-actor sets, `snapshot_and_reset()`. Unit tests with a fake clock.
2. `OpsMetricsMiddleware`, added last (outermost): timing, status, route template after routing,
   actor id from the already decoded token (A+B+C caches it on the request).
3. Pool checkout timing via SQLAlchemy `pool` events on the API engine only.
4. A lifespan task that flushes every 60 s: PostHog capture, or a structlog line.
5. Settings: `OPS_METRICS_ENABLED` (default true), `OPS_METRICS_INTERVAL_SECONDS` (60).
6. Tests: middleware counts 200/429/503; shed requests are timed; no PII in the event; the flush
   survives a failing PostHog client.
7. One knee run on the load-test harness (30 users) to confirm the CPU cost is within noise.
8. Ships as a normal backend release (procedure B); the alerts are set up in PostHog by the owner.
