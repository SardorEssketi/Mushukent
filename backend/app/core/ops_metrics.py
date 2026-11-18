"""Minimal production observability (load audit LT-20, step 1).

One small in-process aggregator, fed by an ASGI middleware at the outer edge of the stack, so it
also sees requests the in-flight cap sheds and the rate limiter refuses. Once per interval (60 s)
the reporter turns it into **one** summary: a PostHog event ``api_health_minute`` when analytics is
configured, and always one structlog line. Critical conditions over a rolling window (10 min) are
sent to Telegram through the existing bot, because PostHog's free plan checks alerts hourly at best.

Privacy: no user id, IP address or user agent leaves the process. Active users are counted from an
in-memory set of opaque keys (a verified user id, otherwise a salted hash of address and user agent
with a salt that is generated at start-up and never stored) that is pruned every interval.

Cost per request: two ``perf_counter`` calls, a lock and a dict/list update. Latency samples are
capped per route and interval (reservoir), so a flush sorts at most a few thousand numbers.
"""

from __future__ import annotations

import asyncio
import hashlib
import math
import os
import random
import secrets
import time
from collections import deque
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from typing import Any

import httpx
from starlette.requests import Request
from starlette.types import ASGIApp, Message, Receive, Scope, Send
from structlog import get_logger

from app.core.upload_guard import is_upload_request

logger = get_logger(__name__)

SERVICE_BUSY_STATE_KEY = "service_busy_reason"
BUSY_CAP = "in_flight_cap"
BUSY_POOL = "pool_timeout"
_ACCESS_TOKEN_STATE_KEY = "access_token_decode"  # app.core.request_auth cache
_MAX_SAMPLES_PER_ROUTE = 2_000
_ACTIVE_WINDOWS = {"active_users_1m": 60.0, "active_users_5m": 300.0}
_FEED_FILTERS = frozenset({"recent", "nearby", "popular", "needs_help"})
_KEY_ROUTES = {
    ("GET", "/api/v1/cats"): "map_cats",
    ("GET", "/api/v1/lost-pets/map"): "map_lost_pets",
    ("POST", "/api/v1/views/seen"): "views_seen",
    ("GET", "/api/v1/users/me"): "users_me",
    ("POST", "/api/v1/auth/refresh"): "auth_refresh",
}
FEED_KEYS = tuple(f"feed_{name}" for name in sorted(_FEED_FILTERS))
MAP_KEYS = ("map_cats", "map_lost_pets")


# `app.include_router(api_v1_router, prefix="/api/v1")` (app/main.py): with the FastAPI version in
# use, the matched route's `path` is relative to that prefix ("/feed", "/cats/{cat_id}/posts"), so
# the outer middleware would never see "/api/v1/feed". Templates are normalised to the full path.
API_PREFIX = "/api/v1"


def _full_template(template: str | None) -> str | None:
    if template is None or template == API_PREFIX or template.startswith(API_PREFIX + "/"):
        return template
    return API_PREFIX + template


def route_key(scope: Scope) -> str:
    """A fixed, low-cardinality name for the request: never a raw path, so no ids leak."""
    method = scope.get("method", "")
    template = _full_template(getattr(scope.get("route"), "path", None))
    if method == "POST" and is_upload_request(scope):
        return "upload"
    if template == "/api/v1/feed" and method == "GET":
        query = Request(scope).query_params.get("filter", "recent")
        return f"feed_{query}" if query in _FEED_FILTERS else "feed_other"
    if template is None:
        return "unmatched"
    return _KEY_ROUTES.get((method, template), "other")


def percentile(values: list[float], q: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, max(0, math.ceil(q * len(ordered)) - 1))]


@dataclass
class _RouteStats:
    count: int = 0
    samples: list[float] = field(default_factory=list)

    def add(self, elapsed_ms: float, rng: random.Random) -> None:
        self.count += 1
        if len(self.samples) < _MAX_SAMPLES_PER_ROUTE:
            self.samples.append(elapsed_ms)
            return
        slot = rng.randrange(self.count)  # reservoir sampling keeps a uniform sample
        if slot < _MAX_SAMPLES_PER_ROUTE:
            self.samples[slot] = elapsed_ms


class OpsMetrics:
    """Counters for one interval. ``snapshot_and_reset`` closes the interval.

    Lock-free by design. A lock shared by the event loop and the 40 database worker threads cost
    ~4 ms of CPU per request on the one-core box (measured, plan section 5): a worker preempted
    while holding it stalls the event loop. So:

    * request counters are touched only on the event loop (the middleware and the reporter run
      there), which is one thread;
    * pool waits arrive from worker threads as a plain ``list.append``, atomic under the GIL, and
      the snapshot swaps the list for a new one instead of locking.
    """

    def __init__(self, *, clock: Callable[[], float] = time.monotonic, seed: int | None = None):
        self._clock = clock
        self._rng = random.Random(seed)
        self._salt = secrets.token_bytes(16)
        self._started = clock()
        self._last_seen: dict[str, float] = {}
        self._in_flight = 0
        self._reset(clock())

    def _reset(self, now: float) -> None:
        self._interval_start = now
        self._routes: dict[str, _RouteStats] = {}
        self._status: dict[str, int] = dict.fromkeys(
            (
                "status_2xx",
                "status_3xx",
                "status_4xx",
                "status_429",
                "status_503_cap",
                "status_503_pool",
                "status_503_db",
                "status_5xx_other",
            ),
            0,
        )
        self._requests = 0
        self._in_flight_max = self._in_flight
        # Swapped, never cleared: a worker thread may still append to the old list.
        self._pool_waits: list[tuple[float, bool]] = []

    # -- recording ------------------------------------------------------------------------------

    def request_started(self) -> None:  # event loop only
        self._in_flight += 1
        if self._in_flight > self._in_flight_max:
            self._in_flight_max = self._in_flight

    def request_finished(
        self, *, key: str, status: int, elapsed_ms: float, actor: str | None, busy: str | None
    ) -> None:  # event loop only
        self._in_flight -= 1
        self._requests += 1
        stats = self._routes.get(key)
        if stats is None:
            stats = self._routes[key] = _RouteStats()
        stats.add(elapsed_ms, self._rng)
        self._status[_status_bucket(status, busy)] += 1
        if actor is not None:
            self._last_seen[actor] = self._clock()

    def record_pool_wait(self, wait_ms: float, timed_out: bool) -> None:  # any thread
        waits = self._pool_waits  # one read, then one atomic append: no lock
        if len(waits) < _MAX_SAMPLES_PER_ROUTE or timed_out:
            waits.append((wait_ms, timed_out))

    def actor_key(self, user_id: str | None, address: str | None, user_agent: str) -> str | None:
        if user_id:
            return f"u:{user_id}"
        if not address:
            return None
        digest = hashlib.blake2b(
            f"{address}|{user_agent}".encode(), key=self._salt, digest_size=12
        ).hexdigest()
        return f"g:{digest}"

    # -- reporting ------------------------------------------------------------------------------

    def snapshot_and_reset(self) -> dict[str, Any]:  # event loop only
        now = self._clock()
        routes, status = self._routes, self._status
        requests, in_flight_max = self._requests, self._in_flight_max
        recorded = self._pool_waits
        duration = max(now - self._interval_start, 1e-9)
        horizon = now - max(_ACTIVE_WINDOWS.values())
        self._last_seen = {k: t for k, t in self._last_seen.items() if t >= horizon}
        active = {
            name: sum(1 for t in self._last_seen.values() if t >= now - window)
            for name, window in _ACTIVE_WINDOWS.items()
        }
        self._reset(now)
        pool_waits = [ms for ms, _ in recorded]
        pool_timeouts = sum(1 for _, timed_out in recorded if timed_out)

        snapshot: dict[str, Any] = {
            "interval_s": round(duration, 1),
            "requests": requests,
            "requests_per_s": round(requests / duration, 3),
            "in_flight_max": in_flight_max,
            "pool_wait_p95_ms": _round(percentile(pool_waits, 0.95)),
            "pool_wait_max_ms": _round(max(pool_waits) if pool_waits else None),
            "pool_timeouts": pool_timeouts,
            "uptime_s": round(now - self._started),
            **status,
            **active,
        }
        samples: dict[str, list[float]] = {}
        for key, stats in sorted(routes.items()):
            snapshot[f"{key}_count"] = stats.count
            snapshot[f"{key}_p50_ms"] = _round(percentile(stats.samples, 0.50))
            snapshot[f"{key}_p95_ms"] = _round(percentile(stats.samples, 0.95))
            if key in FEED_KEYS or key in MAP_KEYS:
                samples[key] = stats.samples
        # Pooled figures, so each hourly PostHog warning is one series rather than a formula.
        for name, keys in (("feed", FEED_KEYS), ("map", MAP_KEYS)):
            pooled = [v for k in keys for v in samples.get(k, [])]
            snapshot[f"{name}_count"] = sum(routes[k].count for k in keys if k in routes)
            snapshot[f"{name}_p95_ms"] = _round(percentile(pooled, 0.95))
        snapshot["status_503_busy"] = (
            status["status_503_cap"] + status["status_503_pool"] + status["status_503_db"]
        )
        snapshot["_samples"] = samples  # for the alert window only; never sent
        return snapshot


def _status_bucket(status: int, busy: str | None) -> str:
    if status == 503 and busy == BUSY_CAP:
        return "status_503_cap"
    if status == 503 and busy == BUSY_POOL:
        return "status_503_pool"
    if status == 503 and busy is not None:  # statement or lock timeout turned into SERVICE_BUSY
        return "status_503_db"
    if status == 429:
        return "status_429"
    if status >= 500:
        return "status_5xx_other"
    return f"status_{status // 100}xx" if 200 <= status < 500 else "status_5xx_other"


def _round(value: float | None) -> float | None:
    return None if value is None else round(value, 1)


class OpsMetricsMiddleware:
    """Outermost middleware: times every HTTP request up to the end of its response body."""

    def __init__(
        self,
        app: ASGIApp,
        *,
        metrics: OpsMetrics,
        client_address: Callable[[Request], str | None],
    ) -> None:
        self.app = app
        self.metrics = metrics
        self.client_address = client_address

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        status = 500  # an exception before the response starts ends as a 500
        start = time.perf_counter()
        self.metrics.request_started()

        async def send_wrapper(message: Message) -> None:
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
            await send(message)

        try:
            await self.app(scope, receive, send_wrapper)
        finally:
            elapsed_ms = (time.perf_counter() - start) * 1000
            state = scope.get("state") or {}
            try:
                key = route_key(scope)
                actor = self._actor(scope, state)
            except Exception as exc:  # noqa: BLE001 - metrics must never break a request
                logger.warning("ops_metrics_classify_failed", error_type=type(exc).__name__)
                key, actor = "unclassified", None
            self.metrics.request_finished(
                key=key,
                status=status,
                elapsed_ms=elapsed_ms,
                actor=actor,
                busy=state.get(SERVICE_BUSY_STATE_KEY),
            )

    def _actor(self, scope: Scope, state: dict) -> str | None:
        cached = state.get(_ACCESS_TOKEN_STATE_KEY)
        principal = cached[1] if cached is not None else None
        user_id = getattr(principal, "user_id", None)
        if user_id is not None:
            return self.metrics.actor_key(str(user_id), None, "")
        request = Request(scope)
        return self.metrics.actor_key(
            None, self.client_address(request), request.headers.get("user-agent", "")
        )


# -- alerts ---------------------------------------------------------------------------------------


@dataclass(frozen=True)
class AlertThresholds:
    feed_p95_ms: float = 500
    map_p95_ms: float = 700
    active_users: int = 28
    requests_per_s: float = 6.5
    busy_share: float = 0.01
    busy_min_count: int = 10
    pool_timeouts: int = 5
    min_samples: int = 50
    window_minutes: int = 10
    repeat_minutes: int = 30


def evaluate_alerts(window: list[dict[str, Any]], t: AlertThresholds) -> dict[str, str]:
    """Critical conditions over the window; returns {rule: human-readable value}."""
    firing: dict[str, str] = {}
    if not window:
        return firing
    full = len(window) >= t.window_minutes

    def pooled(keys: Iterable[str]) -> list[float]:
        return [v for snap in window for k in keys for v in snap["_samples"].get(k, [])]

    if full:
        for rule, keys, limit in (
            ("feed_p95", FEED_KEYS, t.feed_p95_ms),
            ("map_p95", MAP_KEYS, t.map_p95_ms),
        ):
            values = pooled(keys)
            p95 = percentile(values, 0.95)
            if p95 is not None and len(values) >= t.min_samples and p95 > limit:
                firing[rule] = f"{p95:.0f} ms over {len(values)} requests (limit {limit:.0f})"
        least_active = min(snap["active_users_5m"] for snap in window)
        if least_active >= t.active_users:
            firing["active_users"] = (
                f"≥ {least_active} for {len(window)} min (limit {t.active_users})"
            )
        rps = sum(snap["requests_per_s"] for snap in window) / len(window)
        if rps >= t.requests_per_s:
            firing["requests_per_s"] = f"{rps:.1f}/s mean (limit {t.requests_per_s})"
    requests = sum(snap["requests"] for snap in window)
    busy = sum(
        snap["status_503_cap"] + snap["status_503_pool"] + snap["status_503_db"] for snap in window
    )
    if requests and busy >= t.busy_min_count and busy / requests > t.busy_share:
        firing["service_busy_503"] = f"{busy} of {requests} requests ({busy / requests:.1%})"
    timeouts = sum(snap["pool_timeouts"] for snap in window)
    if timeouts > t.pool_timeouts:
        firing["pool_timeouts"] = f"{timeouts} (limit {t.pool_timeouts})"
    return firing


class TelegramOpsNotifier:
    """Sends plain-text operational alerts through the existing feedback bot. Never raises."""

    def __init__(
        self,
        *,
        bot_token: str,
        chat_id: str,
        timeout_seconds: float = 5.0,
        client: httpx.Client | None = None,
    ) -> None:
        self._bot_token, self._chat_id = bot_token, chat_id
        self._timeout, self._client = timeout_seconds, client

    @property
    def enabled(self) -> bool:
        return bool(self._bot_token and self._chat_id)

    def send(self, text: str) -> bool:
        if not self.enabled:
            return False
        url = f"https://api.telegram.org/bot{self._bot_token}/sendMessage"
        payload = {"chat_id": self._chat_id, "text": text[:4000], "disable_web_page_preview": True}
        try:
            post = self._client.post if self._client is not None else httpx.post
            post(url, json=payload, timeout=self._timeout).raise_for_status()
        except Exception as exc:  # noqa: BLE001 - the token is in the URL: log the type only
            logger.warning("ops_alert_telegram_failed", error_type=type(exc).__name__)
            return False
        return True


class OpsAlerter:
    """Keeps the rolling window, fires on a new condition, repeats while firing, and resolves."""

    def __init__(
        self,
        notifier: TelegramOpsNotifier,
        thresholds: AlertThresholds,
        *,
        label: str,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.notifier, self.thresholds, self.label, self._clock = notifier, thresholds, label, clock
        self._window: deque[dict[str, Any]] = deque(maxlen=thresholds.window_minutes)
        self._last_sent: dict[str, float] = {}

    def observe(self, snapshot: dict[str, Any]) -> list[str]:
        self._window.append(snapshot)
        firing = evaluate_alerts(list(self._window), self.thresholds)
        now, messages = self._clock(), []
        for rule, value in firing.items():
            last = self._last_sent.get(rule)
            if last is None or now - last >= self.thresholds.repeat_minutes * 60:
                prefix = "CRITICAL" if last is None else "STILL CRITICAL"
                messages.append(f"{prefix} {self.label}: {rule} = {value}")
                self._last_sent[rule] = now
        for rule in [r for r in self._last_sent if r not in firing]:
            messages.append(f"RESOLVED {self.label}: {rule}")
            del self._last_sent[rule]
        for message in messages:
            self.notifier.send(message)
        return messages


class OpsReporter:
    """Background loop: snapshot every interval, send the summary, feed the alerter."""

    def __init__(
        self,
        metrics: OpsMetrics,
        *,
        interval_seconds: float,
        analytics_client: Any | None,
        alerter: OpsAlerter | None,
        release: str,
    ) -> None:
        self.metrics, self.interval = metrics, interval_seconds
        self.analytics_client, self.alerter, self.release = analytics_client, alerter, release
        self._task: asyncio.Task | None = None

    def flush(self) -> dict[str, Any]:
        """Snapshot and send in one call (tests). The loop uses the two halves separately."""
        return self._send(self.metrics.snapshot_and_reset())

    def _send(self, snapshot: dict[str, Any]) -> dict[str, Any]:
        public = {k: v for k, v in snapshot.items() if not k.startswith("_")}
        public.update(release=self.release, worker_pid=os.getpid())
        logger.info("api_health_minute", **public)
        if self.analytics_client is not None:
            self.analytics_client.capture(
                distinct_id="mushukistan-api", event="api_health_minute", properties=public
            )
        if self.alerter is not None:
            self.alerter.observe(snapshot)
        return public

    async def _run(self) -> None:
        while True:
            await asyncio.sleep(self.interval)
            try:
                # Snapshot on the loop (the counters are loop-only); Telegram is a blocking HTTP
                # call, so the sending runs in a thread.
                snapshot = self.metrics.snapshot_and_reset()
                await asyncio.to_thread(self._send, snapshot)
            except Exception as exc:  # noqa: BLE001 - reporting must never stop the API
                logger.warning("ops_metrics_flush_failed", error_type=type(exc).__name__)

    def start(self) -> None:
        if self.analytics_client is not None:
            self.analytics_client.capture(
                distinct_id="mushukistan-api",
                event="api_started",
                properties={"release": self.release, "worker_pid": os.getpid()},
            )
        logger.info("api_started", release=self.release, worker_pid=os.getpid())
        loop = asyncio.get_running_loop()
        if self.alerter is not None:
            # A start without a deploy is a restart (crash or OOM): say so where alerts go.
            text = f"INFO {self.alerter.label}: API started, release {self.release}"
            loop.run_in_executor(None, self.alerter.notifier.send, text)
        self._task = loop.create_task(self._run())

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
            self._task = None
