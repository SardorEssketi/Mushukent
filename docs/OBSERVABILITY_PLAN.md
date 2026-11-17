# Minimal production observability (LT-20): plan

Status: **step 1 implemented** on `ops/observability` (owner approval 2026-11-16), not deployed.
Step 2 stays a plan until the owner approves it. Builds on
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
  is 1M a month (section 3). CPU: no measurable cost on the harness (section 5).
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

## 3. Alerts

**PostHog cannot do 10-minute alerts on our plan (Verified 2026-11-16).** The organisation is on the
free plan (`billing_plan: free`, read through the PostHog API). Free organisations can create at
most **5 alerts**. Per PostHog's alert docs, a 15-minute check needs the Boost add-on and a ~2-minute
"real time" check needs Scale, so hourly is the shortest interval available to us. Event volume is
no issue: ~44k summary events a month against a 1M free allowance (current use is far below 1%).

So alerts are split:
- **Critical: evaluated in the backend, sent to Telegram (implemented).** Every flush, the reporter
  evaluates the last 10 one-minute summaries and sends through the existing feedback bot
  (`TELEGRAM_BOT_TOKEN`; chat `TELEGRAM_OPS_CHAT_ID`, falling back to `TELEGRAM_FEEDBACK_CHAT_ID`).
  It sends "CRITICAL" when a rule starts firing, "STILL CRITICAL" every 30 min while it fires, and
  "RESOLVED" when it clears. A start-up notice ("API started, release …") makes crash and OOM
  restarts visible. Without a bot token or chat id, alerts are off and only the summaries run.
- **Warnings: PostHog, hourly (to set up by the owner, up to 5).** These are trend alerts on
  `api_health_minute`. Hourly is acceptable for "prepare the next step" signals.

Thresholds are tied to the measured capacity (30 users, Feed p95 < 500 ms):

| Signal | Warn (PostHog, hourly) | Critical (Telegram, rolling 10 min) |
|---|---|---|
| Active users (5 min) | max ≥ 20 in the hour | ≥ 28 in every minute of the window |
| Requests per second | ≥ 4.7 hourly mean | ≥ 6.5 mean over the window |
| Feed p95 (all feeds pooled) | > 400 ms (hourly mean of per-minute p95) | > 500 ms over the window's requests (≥ 50) |
| Map pins p95 (cats + lost pets) | > 550 ms | > 700 ms over the window's requests (≥ 50) |
| 503 `SERVICE_BUSY` (cap, pool or DB timeout) | any in the hour | ≥ 10 and > 1% of requests in the window |
| Pool timeouts | any in the hour | > 5 in the window |
| 429 | > 1% of requests | not alerted (no user-visible error for reads; 3.3 of FIXES_RESULTS) |
| Restart | n/a | start-up notice on every start (a start without a deploy is a restart) |
| 504/502, OOM (step 2) | n/a | step 2 |

The five PostHog warnings suggested: active users, requests per second, Feed p95, map p95, and
503 + pool timeouts as one formula. Critical thresholds are settings (`OPS_ALERT_*`), so they can
follow a capacity change without a release.

## 4. Privacy

- No user ids, IPs or user agents leave the process. Active users is a count, and the in-memory
  set is cleared every window.
- The salt for the guest hash is generated at start-up and never stored.
- Route templates, not raw paths, so no ids appear in properties.
- The privacy policy already covers PostHog analytics. Whether operational metrics need a mention
  is for the owner (**Not checked**).

## 5. Implementation (step 1, commits `25b50d4` and `2bdff8d`)

- `backend/app/core/ops_metrics.py`:
  - Aggregator: per-route samples capped at 2,000 per interval (reservoir), status buckets
    (2xx/3xx/4xx/429/503 cap/503 pool/503 DB timeout/other 5xx), in-flight maximum, pool waits
    and timeouts, active users over 1 and 5 min.
  - The outermost middleware, which classifies requests by route template (feed by `filter`,
    uploads by the upload guard's rule).
  - Alert rules, Telegram notifier, and the reporter loop.
- `DatabaseSessionManager(pool_wait_observer=…)`: a `QueuePool` subclass times each checkout. It
  wraps `QueuePool._do_get`, and a test pins that, so an SQLAlchemy upgrade that changes it fails
  in CI.
- The in-flight cap and `_service_busy` mark the 503 reason in the request state.
- Settings (documented in `.env.example`): `OPS_METRICS_ENABLED`, `OPS_METRICS_INTERVAL_SECONDS`,
  `OPS_ALERTS_ENABLED`, `TELEGRAM_OPS_CHAT_ID`, `APP_RELEASE`, `OPS_ALERT_FEED_P95_MS`,
  `OPS_ALERT_MAP_P95_MS`, `OPS_ALERT_ACTIVE_USERS`, `OPS_ALERT_REQUESTS_PER_SECOND`. All have
  defaults; none is required.
- Tests: `backend/tests/test_ops_metrics.py` (13). `test_analytics.py` now expects the one
  `api_started` event. Full backend suite with DB integration tests: 766 passed, 1 skipped. One
  pre-existing timing-dependent test (`test_failure_logging_is_rate_limited`) failed once because
  the Docker VM had booted less than 60 s earlier, and passed on rerun.
- CPU cost on the load-test harness (30 users, one production core, package 1 vs package 1 +
  ops, ABBA order, uploads off; backend CPU per request in production-core ms over the steady
  window):
  - First version (`25b50d4`, one `threading.Lock` shared by the event loop and the pool
    threads): 36.6–41.2 ms, mean 38.7, against a baseline band of 32.4–37.0 (mean 34.6), about
    +4 ms. The same image with `OPS_METRICS_ENABLED=false` ran at baseline, so the cost was the
    runtime path. A profile showed the aggregator's own frames at ~0.1% and the extra time spread
    evenly; contention on the lock was the likely cause.
  - Lock-free version (`2bdff8d`, counters touched on the event loop only, pool waits appended
    to a list swapped at snapshot time, sending in a worker thread), 4 runs each:
    package 1 = 32.8, 32.5, 35.2, 36.7 (mean 34.3); package 1 + ops = 33.5, 29.9, 31.9, 32.8
    (mean 32.0). **No measurable cost**: the difference is inside the run-to-run noise. p95 was
    233–253 ms and errors 0 in every run.
- Deploy: a normal backend release (procedure B), after package 1. To get Telegram alerts, set
  `TELEGRAM_OPS_CHAT_ID` (or rely on the feedback chat) and `APP_RELEASE` in the production `.env`.
  The owner sets up the PostHog warnings.
