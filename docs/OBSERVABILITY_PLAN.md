# Minimal production observability (LT-20): plan

Status: **steps 1 and 2 implemented** on `ops/observability` (owner approvals 2026-11-16 and
2026-11-18), not deployed. Step 2 is infrastructure: **needs owner approval before deploy**
(section 6). Builds on
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

Implemented (approved 2026-11-18); deploy steps and rollback in section 6.

- **Nginx JSON access log** (`infrastructure/nginx/default.conf`): `log_format ops_json` with
  time, host, a fixed route class (`feed`, `map_cats`, `map_lost_pets`, `views_seen`, `users_me`,
  `auth_refresh`, `api_other`, `health`, `media`, `web`), method, status, `$request_time`,
  `$upstream_response_time` and `$upstream_status`; on stdout as before, on all three server
  blocks. This adds **502/504**, which the backend never sees: in the 300-user spike, 504s came
  from nginx's timeout while the backend saw nothing (FIXES_RESULTS 3.6).
  - **Privacy:** no client address, user agent, query string or raw path. Today's default
    `combined` access log has all four, so the access log gets *less* personal data. A test pins
    this.
  - **Not changed:** nginx's error log still prints the request line (with query string) and the
    client address for upstream errors (Verified in the local check below). That is existing
    behaviour; changing it is a separate decision.
  - **Verified locally (2026-11-18):** `nginx:1.27-alpine` with this file passes `nginx -t`. Test
    requests produce one JSON line each, and a token in the query string and the user agent do
    not appear in the access log.
- **Docker log rotation** (`docker-compose.prod.yml`): `json-file`, `max-size 10m`, `max-file 5` for
  nginx, the backend and the worker. Each container gets it when its normal release procedure
  next recreates it. The db service is deliberately left unchanged: changing its logging would
  make a later `up` recreate the database container. The daemon's own log settings on the host
  are **Not checked**; the per-service setting works either way.
- **Host timer** (`infrastructure/ops/`): `host_health.py` (Python 3 standard library; the host
  has `python3`) plus a systemd service and a one-minute timer (`*.example`, installed by the
  owner). Every minute it:
  - counts nginx 502, 504 and other 5xx, and computes API p50/p95 request time, from
    `docker logs --since <last run> --until <now> mushukistan-nginx`. Lines in the old default
    format are still counted, so the timer also works before the nginx change is live;
  - reads every Compose service container of the `mushukistan` project (`docker ps` / `inspect`;
    one-off `compose run` containers such as migrations are skipped): restart count, state,
    health;
  - reads Docker `oom` events for the window (`docker events --since --until`);
  - sends one PostHog event, `host_health_minute`, with `distinct_id` `mushukistan-host` and no
    person profile;
  - evaluates the host's critical rules (section 3) and sends to the **same Telegram bot and chat**
    as the backend: `TELEGRAM_OPS_CHAT_ID`, falling back to `TELEGRAM_FEEDBACK_CHAT_ID`.
  - **Read-only towards the containers:** only `docker logs`, `events`, `ps` and `inspect`. It
    writes one state file (`/var/lib/mushukistan-ops/host-health.json`). Send failures are logged
    by error type only, never with the token.
  - **Tests:** `backend/tests/test_host_health_script.py` (14 tests, run in CI with the backend
    suite): log parsing in both formats, the run window, CRITICAL/STILL CRITICAL/RESOLVED, restart
    vs recreate, OOM, Docker failure, dry run, senders, and the nginx privacy rule.
  - **Verified locally (2026-11-18):** a dry run against a real nginx container counted 7
    requests, 3 API requests and 4 × 502 correctly.

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
| Restart | n/a | backend start-up notice on every start; host timer: restart count up on the same container → CRITICAL with exit code and `OOMKilled` (a recreate by a deploy is an info notice only) |
| Nginx 502/504 (step 2) | any in the hour | ≥ 5 in the last 10 min (`OPS_HOST_GATEWAY_ERRORS_10M`) |
| OOM kill (step 2) | n/a | any Docker `oom` event → CRITICAL |
| Container down (step 2) | n/a | not running, or unhealthy, on 2 consecutive runs (a deploy swap is shorter) |
| Host check itself (step 2) | n/a | Docker did not answer on 2 consecutive runs |

The five PostHog warnings (exact setup in section 7): active users, Feed p95, map p95, busy 503s
(cap, pool and DB timeouts: pool timeouts are 503s, so one series covers both), and nginx 502/504.
Requests per second is left out of the five: it moves with active users, and its critical alert
is in Telegram. Critical thresholds are settings (`OPS_ALERT_*` in the backend, `OPS_HOST_*` in
the host env file), so they can follow a capacity change without a release.

To make each warning one series, the minute event also carries pooled `feed_p95_ms`,
`feed_count`, `map_p95_ms`, `map_count` and `status_503_busy` (commit `bb48544`), and the host event
carries `gateway_errors` (502 + 504).

## 4. Privacy

- No user ids, IPs or user agents leave the process. Active users is a count, and the in-memory
  set is cleared every window.
- The salt for the guest hash is generated at start-up and never stored.
- Route templates, not raw paths, so no ids appear in properties.
- The privacy policy already covers PostHog analytics. Whether operational metrics need a mention
  is for the owner (**Not checked**).

## 5. Implementation (step 1, commits `25b50d4`, `2bdff8d` and `bb48544`)

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
- Deploy: section 6. A normal backend release (procedure B), after package 1. To get Telegram alerts, set
  `TELEGRAM_OPS_CHAT_ID` (or rely on the feedback chat) and `APP_RELEASE` in the production `.env`.
  The owner sets up the PostHog warnings (section 7).

## 6. Deploy steps and rollback (needs owner approval before each production step)

Order: package 1 first (its own release, `FIXES_RESULTS.md` section 8). Then, after
`ops/observability` is merged to `main` with CI green:

| # | What | Procedure | Touches |
|---|---|---|---|
| 1 | Step 1 (backend minute summary + Telegram criticals) | B (backend + worker) | backend and worker containers; they also get log rotation |
| 2 | Nginx JSON log + nginx log rotation | A (`release-web`), from the same `main` commit | nginx container only |
| 3 | Host timer | manual, owner as root (below) | new files under `/usr/local/lib`, `/etc`, `/var/lib`, `/etc/systemd/system`; no container |

Steps 2 and 3 are independent of step 1: the timer also reads the old log format (502/504 and 5xx
counts, without request time). Each step can be rolled back alone.

### 6.1 Step 1: backend release

Use procedure B as usual. Before the swap, the owner adds to the new release's `.env`
(names compared only):
- `APP_RELEASE=<sha7>`;
- optionally `TELEGRAM_OPS_CHAT_ID=<chat>`. Without it, alerts go to `TELEGRAM_FEEDBACK_CHAT_ID`.

After the swap:
- the ops chat receives "API started, release <sha7>";
- PostHog shows `api_started`, then one `api_health_minute` per minute
  (Activity → Explore events, filter by event name);
- `docker inspect -f '{{json .HostConfig.LogConfig}}' mushukistan-backend` shows `max-size 10m`.

**Rollback:** the procedure B rollback (previous release directory). To turn only the metrics off
without a rollback: `OPS_METRICS_ENABLED=false` in `.env`, then recreate the backend (procedure B
steps 7–8).

### 6.2 Step 2: nginx log format (web release)

Use procedure A through `release-web`, built from the `main` commit that contains the change.
The activation's dry run already runs `nginx -t` on the staged configuration. After activation,
check:

```sh
docker logs --since 2m mushukistan-nginx 2>/dev/null | tail -n 2   # JSON lines with "route", no IPs
docker inspect -f '{{json .HostConfig.LogConfig}}' mushukistan-nginx  # json-file, max-size 10m, max-file 5
```

- **Rollback:** the standard web rollback, printed by the activation and saved in
  `PREVIOUS_STATE.txt`. Nginx goes back to the default log format. A host timer that is already
  installed keeps counting 502/504.
- Whether `release-web` accepts a release that also changes `docker-compose.prod.yml` (the logging
  block) is **Not checked**. If it refuses, use the manual procedure A, which uses the release's
  own Compose files.

### 6.3 Step 3: host timer (owner, root, `! ssh -t "$(bash scripts/deploy/ssh-target.sh)"`)

```sh
# 0. The active release directory (from Nginx's Compose labels; never guessed)
REL=$(docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' mushukistan-nginx)
ls "$REL/infrastructure/ops/host_health.py"
sha256sum "$REL/infrastructure/ops/host_health.py"
#    compare locally:  git show origin/main:infrastructure/ops/host_health.py | sha256sum

# 1. Script
install -d -m 755 /usr/local/lib/mushukistan-ops
install -m 755 "$REL/infrastructure/ops/host_health.py" /usr/local/lib/mushukistan-ops/host_health.py

# 2. Secrets: copied from the release .env, never printed
install -d -m 700 /etc/mushukistan-ops
( umask 077; grep -E '^(TELEGRAM_BOT_TOKEN|TELEGRAM_OPS_CHAT_ID|TELEGRAM_FEEDBACK_CHAT_ID|POSTHOG_PROJECT_TOKEN|POSTHOG_HOST)=' \
    "$REL/.env" > /etc/mushukistan-ops/host-health.env )
cut -d= -f1 /etc/mushukistan-ops/host-health.env   # NAMES only: the token, a chat id, both PostHog keys

# 3. Dry run (prints the event and any alerts; sends nothing, writes nothing)
( set -a; . /etc/mushukistan-ops/host-health.env; set +a
  python3 /usr/local/lib/mushukistan-ops/host_health.py --dry-run )
#    expect: "docker_ok": true, "containers" = the number of service containers, requests > 0

# 4. Telegram path (one test message in the ops chat)
( set -a; . /etc/mushukistan-ops/host-health.env; set +a
  python3 /usr/local/lib/mushukistan-ops/host_health.py --test-telegram )

# 5. Units, one manual run, then the timer
install -m 644 "$REL/infrastructure/ops/mushukistan-host-health.service.example" /etc/systemd/system/mushukistan-host-health.service
install -m 644 "$REL/infrastructure/ops/mushukistan-host-health.timer.example" /etc/systemd/system/mushukistan-host-health.timer
systemctl daemon-reload
systemctl start mushukistan-host-health.service
journalctl -u mushukistan-host-health -n 3 --no-pager           # "host_health requests=... alerts=0"
systemctl show mushukistan-host-health.service -p CPUUsageNSec  # CPU of one run
systemctl enable --now mushukistan-host-health.timer
systemctl list-timers mushukistan-host-health.timer --no-pager
```

**Checks after 10 minutes:**
- `journalctl -u mushukistan-host-health --since -10min --no-pager | grep -c host_health` is ~10;
- PostHog has ten `host_health_minute` events;
- `systemctl --failed` lists nothing new.

**Cost on the production host (Estimate; step 5 measures it):** one Python start and four Docker CLI
calls a minute, about 0.2–0.5 s of CPU per run, i.e. under 1% of one core on average. If
`CPUUsageNSec` shows more than 1 s per run, stop the timer and report.

**Rollback (no container is touched):**

```sh
systemctl disable --now mushukistan-host-health.timer
rm -f /etc/systemd/system/mushukistan-host-health.service /etc/systemd/system/mushukistan-host-health.timer
systemctl daemon-reload
rm -rf /usr/local/lib/mushukistan-ops /etc/mushukistan-ops /var/lib/mushukistan-ops
```

**Later:**
- If the bot token or the PostHog token changes in `.env`, repeat step 2 of this list.
- A new release does not affect the timer. It reads containers by Compose project label and
  Nginx by container name.

## 7. PostHog hourly warnings: exact setup (owner, after the events arrive)

Create these after step 1 (and step 3, for warning 5) has sent events for at least an hour.
PostHog only offers a property in the pickers once it has been ingested. The free plan allows
5 alerts, and the shortest check interval on it is **Hourly** (section 3).

**For each insight:**
1. Product analytics → **New insight** → **Trends**.
2. Set the series below. Choose the aggregation in the series' "Total count" menu:
   **Property value** → the statistic → the property.
3. Set the date range to **Last 24 hours** and the interval to **Hour**.
4. **Save** it with the given name.

**Then for each saved insight:**
1. **Monitor** → **Alerts** → **New alert**.
2. Pick the one series and choose **Threshold**: **has value**, **more than** the value below.
3. Set the check frequency to **Hourly**. Leave "Check ongoing period" off, so the last completed
   hour is checked.
4. Notify yourself (in-app and email).

PostHog also offers Slack/Discord/Teams/webhook destinations. Sending a PostHog webhook straight
to Telegram is **Not checked**; Telegram already gets the critical alerts from the backend and the
host.

| # | Insight name | Event | Aggregation | Filter on the series | Alert: has value, more than |
|---|---|---|---|---|---|
| 1 | Ops · active users (5 min), hourly max | `api_health_minute` | Property value → **Maximum** → `active_users_5m` | none | **19** (i.e. ≥ 20; capacity is 30) |
| 2 | Ops · feed p95, hourly mean | `api_health_minute` | Property value → **Average** → `feed_p95_ms` | `feed_count` ≥ 5 (drops quiet minutes, where one slow request is the "p95") | **400** (ms) |
| 3 | Ops · map pins p95, hourly mean | `api_health_minute` | Property value → **Average** → `map_p95_ms` | `map_count` ≥ 5 | **550** (ms) |
| 4 | Ops · busy 503s per hour | `api_health_minute` | Property value → **Sum** → `status_503_busy` | none | **0** (any) |
| 5 | Ops · nginx 502/504 per hour | `host_health_minute` | Property value → **Sum** → `gateway_errors` | none | **0** (any) |

**Notes:**
- **Several workers later:** one event per worker per minute. Insight 1 then shows the busiest
  worker, not the total. Revisit it when the Redis/multi-worker design ships.
- **A sixth useful alert** would be "`api_health_minute` total count, less than 50 per hour" (the
  metrics stopped). It does not fit in 5. The host timer's container-down and restart alerts cover
  the same failure.
- **Thresholds** follow the warn column in section 3. Change them in the alert, not in code.
