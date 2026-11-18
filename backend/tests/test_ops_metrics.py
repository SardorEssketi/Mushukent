"""Production observability (LT-20 step 1): per-minute summary and Telegram critical alerts."""

from __future__ import annotations

import asyncio
import threading
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
from fastapi import APIRouter, FastAPI, Request
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy import exc as sa_exc

from app.core.load_shedding import LoadSheddingMiddleware
from app.core.ops_metrics import (
    AlertThresholds,
    OpsAlerter,
    OpsMetrics,
    OpsMetricsMiddleware,
    OpsReporter,
    TelegramOpsNotifier,
    evaluate_alerts,
)
from app.infrastructure.db.session import timed_queue_pool


class Clock:
    def __init__(self) -> None:
        self.now = 1000.0

    def __call__(self) -> float:
        return self.now


def _app(metrics: OpsMetrics, *, cap: int = 10) -> FastAPI:
    # Mounted like production (app/main.py): one router included with the "/api/v1" prefix, so
    # the matched route's path is relative ("/feed"). A test app with full paths hid that once.
    app = FastAPI()
    router = APIRouter()

    @router.get("/feed")
    def feed() -> dict:
        return {"ok": True}

    @router.get("/cats")
    def cats() -> dict:
        return {"ok": True}

    @router.get("/cats/{cat_id}/posts")
    def cat_posts(cat_id: int) -> dict:
        return {"ok": cat_id}

    @router.get("/limited")
    def limited():
        from fastapi.responses import JSONResponse

        return JSONResponse({"error": "rate"}, status_code=429)

    @router.get("/pool-busy")
    def pool_busy(request: Request):
        from fastapi.responses import JSONResponse

        request.state.service_busy_reason = "pool_timeout"
        return JSONResponse({"error": "busy"}, status_code=503)

    @router.get("/boom")
    def boom():
        raise RuntimeError("boom")

    app.include_router(router, prefix="/api/v1")
    app.add_middleware(LoadSheddingMiddleware, max_in_flight=cap, retry_after=5)
    app.add_middleware(
        OpsMetricsMiddleware,
        metrics=metrics,
        client_address=lambda request: request.client.host if request.client else None,
    )
    return app


def test_requests_are_counted_by_route_template_and_status() -> None:
    metrics = OpsMetrics(seed=1)
    client = TestClient(_app(metrics), raise_server_exceptions=False)
    for _ in range(3):
        assert client.get("/api/v1/feed?filter=nearby").status_code == 200
    client.get("/api/v1/feed?filter=../../etc")  # unknown filter: no free-form key
    client.get("/api/v1/cats/987654/posts")
    client.get("/api/v1/cats?bbox=69.2,41.2,69.3,41.3")
    client.get("/api/v1/limited")
    client.get("/api/v1/pool-busy")
    client.get("/api/v1/boom")
    client.get("/api/v1/nope")

    snap = metrics.snapshot_and_reset()
    assert snap["feed_nearby_count"] == 3
    assert snap["feed_other_count"] == 1
    assert snap["feed_nearby_p95_ms"] is not None
    assert snap["other_count"] == 4  # cat posts, limited, pool-busy, boom
    assert snap["unmatched_count"] == 1
    assert snap["status_2xx"] == 6 and snap["status_4xx"] == 1
    assert snap["status_429"] == 1
    assert snap["status_503_pool"] == 1
    assert snap["status_5xx_other"] == 1
    assert snap["requests"] == 10
    # pooled series for the hourly PostHog warnings
    assert snap["feed_count"] == 3  # the four known feeds only; feed_other is not pooled
    assert snap["feed_p95_ms"] is not None
    assert snap["map_cats_count"] == 1
    assert snap["map_count"] == 1 and snap["map_p95_ms"] is not None
    assert snap["status_503_busy"] == 1
    assert not any("987654" in str(item) for item in snap.items())  # templates only
    assert metrics.snapshot_and_reset()["requests"] == 0  # the interval was reset


def test_requests_shed_by_the_in_flight_cap_are_counted_as_cap_503() -> None:
    metrics = OpsMetrics(seed=1)
    release, started = threading.Event(), threading.Semaphore(0)
    app = _app(metrics, cap=1)

    @app.get("/api/v1/slow")
    def slow() -> dict:
        started.release()
        release.wait(5)
        return {}

    client = TestClient(app)
    worker = threading.Thread(target=lambda: client.get("/api/v1/slow"))
    worker.start()
    assert started.acquire(timeout=5)
    assert client.get("/api/v1/feed").status_code == 503
    release.set()
    worker.join(5)

    snap = metrics.snapshot_and_reset()
    assert snap["status_503_cap"] == 1
    assert snap["status_503_busy"] == 1
    assert snap["in_flight_max"] == 2


def test_active_users_are_counted_without_exporting_identities() -> None:
    clock = Clock()
    metrics = OpsMetrics(clock=clock, seed=1)
    user = str(uuid4())
    for actor in (
        metrics.actor_key(user, None, ""),
        metrics.actor_key(user, None, ""),  # same user twice
        metrics.actor_key(None, "203.0.113.5", "app/1"),
        metrics.actor_key(None, "203.0.113.5", "app/2"),  # same address, other device
    ):
        metrics.request_started()
        metrics.request_finished(key="other", status=200, elapsed_ms=1, actor=actor, busy=None)
    snap = metrics.snapshot_and_reset()
    assert snap["active_users_1m"] == 3 and snap["active_users_5m"] == 3
    flat = repr(snap)
    assert user not in flat and "203.0.113.5" not in flat

    clock.now += 120  # older than a minute, younger than five
    snap = metrics.snapshot_and_reset()
    assert snap["active_users_1m"] == 0 and snap["active_users_5m"] == 3
    clock.now += 300
    assert metrics.snapshot_and_reset()["active_users_5m"] == 0


def test_guest_hash_is_salted_per_process() -> None:
    a, b = OpsMetrics(), OpsMetrics()
    assert a.actor_key(None, "203.0.113.5", "x") != b.actor_key(None, "203.0.113.5", "x")
    assert a.actor_key(None, None, "x") is None


def test_latency_samples_are_bounded_per_route() -> None:
    metrics = OpsMetrics(seed=3)
    for i in range(5_000):
        metrics.request_started()
        metrics.request_finished(key="feed_recent", status=200, elapsed_ms=i, actor=None, busy=None)
    snap = metrics.snapshot_and_reset()
    assert snap["feed_recent_count"] == 5_000
    assert len(snap["_samples"]["feed_recent"]) == 2_000
    assert 4_000 < snap["feed_recent_p95_ms"] <= 5_000


def test_pool_waits_and_timeouts_are_observed() -> None:
    seen: list[tuple[float, bool]] = []
    pool_class = timed_queue_pool(lambda ms, timed_out: seen.append((ms, timed_out)))
    engine = create_engine(
        "sqlite://", poolclass=pool_class, pool_size=1, max_overflow=0, pool_timeout=0.05
    )
    held = engine.connect()
    with pytest.raises(sa_exc.TimeoutError):
        engine.connect()
    held.close()
    with engine.connect():
        pass
    assert [timed_out for _, timed_out in seen] == [False, True, False]
    assert seen[1][0] >= 40  # waited for the pool timeout


def test_pool_observer_failure_never_breaks_a_checkout() -> None:
    def broken(ms: float, timed_out: bool) -> None:
        raise ValueError("observer bug")

    engine = create_engine("sqlite://", poolclass=timed_queue_pool(broken), pool_size=1)
    with engine.connect():
        pass  # the checkout succeeded despite the observer raising


def _snap(**overrides) -> dict:
    base = {
        "requests": 400,
        "requests_per_s": 6.7,
        "active_users_5m": 10,
        "status_503_cap": 0,
        "status_503_pool": 0,
        "status_503_db": 0,
        "pool_timeouts": 0,
        "_samples": {"feed_recent": [100.0] * 40, "map_cats": [100.0] * 40},
    }
    base.update(overrides)
    return base


def test_alert_rules_need_a_full_window_for_sustained_conditions() -> None:
    t = AlertThresholds()
    slow = _snap(_samples={"feed_recent": [900.0] * 40, "map_cats": [100.0] * 40})
    assert "feed_p95" not in evaluate_alerts([slow] * 9, t)  # 9 minutes is not sustained
    firing = evaluate_alerts([slow] * 10, t)
    assert "feed_p95" in firing and "map_p95" not in firing
    assert "requests_per_s" in firing  # 6.7/s mean for 10 minutes
    assert "active_users" not in firing
    assert "active_users" in evaluate_alerts([_snap(active_users_5m=28)] * 10, t)


def test_alert_rules_for_shedding_and_pool_timeouts() -> None:
    t = AlertThresholds()
    assert evaluate_alerts([_snap(status_503_cap=5, requests_per_s=1)], t) == {}  # under 10
    firing = evaluate_alerts([_snap(status_503_cap=8, status_503_db=4, requests_per_s=1)], t)
    assert "service_busy_503" in firing  # 12 of 400 = 3%
    assert "pool_timeouts" in evaluate_alerts([_snap(pool_timeouts=6, requests_per_s=1)], t)


class FakeNotifier:
    def __init__(self) -> None:
        self.sent: list[str] = []
        self.enabled = True

    def send(self, text: str) -> bool:
        self.sent.append(text)
        return True


def test_alerter_fires_repeats_and_resolves() -> None:
    clock, notifier = Clock(), FakeNotifier()
    alerter = OpsAlerter(notifier, AlertThresholds(), label="test", clock=clock)
    busy = _snap(status_503_cap=50, requests_per_s=1)
    alerter.observe(busy)
    assert notifier.sent == [notifier.sent[0]] and notifier.sent[0].startswith("CRITICAL test")
    clock.now += 60
    alerter.observe(busy)
    assert len(notifier.sent) == 1  # no repeat within 30 minutes
    clock.now += 30 * 60
    alerter.observe(busy)
    assert notifier.sent[-1].startswith("STILL CRITICAL")
    quiet = _snap(requests_per_s=1)
    for _ in range(15):  # the busy minutes leave the window, then 5 clear minutes in a row
        alerter.observe(quiet)
    assert notifier.sent[-1] == "RESOLVED test: service_busy_503"
    assert len(notifier.sent) == 3  # CRITICAL, STILL CRITICAL, RESOLVED


def test_a_flapping_rule_does_not_spam() -> None:
    clock, notifier = Clock(), FakeNotifier()
    alerter = OpsAlerter(notifier, AlertThresholds(window_minutes=1), label="test", clock=clock)
    busy, quiet = _snap(status_503_cap=50, requests_per_s=1), _snap(requests_per_s=1)
    for minute in range(60):  # one hour flipping every minute across the threshold
        alerter.observe(busy if minute % 2 == 0 else quiet)
        clock.now += 60
    # one incident: CRITICAL once, STILL CRITICAL after 30 min; never RESOLVED while it flaps
    assert [m.split(" test")[0] for m in notifier.sent] == ["CRITICAL", "STILL CRITICAL"]
    for _ in range(5):
        alerter.observe(quiet)
        clock.now += 60
    assert notifier.sent[-1] == "RESOLVED test: service_busy_503"


def test_telegram_notifier_never_raises_and_hides_the_token() -> None:
    class Failing:
        def post(self, url, **kwargs):
            raise RuntimeError(url)

    notifier = TelegramOpsNotifier(bot_token="123:secret", chat_id="42", client=Failing())
    assert notifier.send("x") is False
    assert TelegramOpsNotifier(bot_token="", chat_id="42").enabled is False


def test_ops_messages_are_prefixed_so_they_differ_from_feedback() -> None:
    class Recording:
        def __init__(self) -> None:
            self.payloads: list[dict] = []

        def post(self, url, *, json, timeout):
            self.payloads.append(json)
            return httpx.Response(200, request=httpx.Request("POST", "https://t.invalid"))

    client = Recording()
    notifier = TelegramOpsNotifier(bot_token="123:secret", chat_id="42", client=client)
    assert notifier.send("CRITICAL x: feed_p95") is True
    assert client.payloads[0]["text"] == "🚨 OPS · CRITICAL x: feed_p95"
    assert client.payloads[0]["chat_id"] == "42"


def test_reporter_sends_one_summary_without_internal_fields() -> None:
    captured: list[dict] = []
    analytics = SimpleNamespace(capture=lambda **kwargs: captured.append(kwargs))
    metrics = OpsMetrics(seed=1)
    metrics.request_started()
    metrics.request_finished(key="feed_recent", status=200, elapsed_ms=12, actor="u:x", busy=None)
    notifier = FakeNotifier()
    reporter = OpsReporter(
        metrics,
        interval_seconds=60,
        analytics_client=analytics,
        alerter=OpsAlerter(notifier, AlertThresholds(), label="t"),
        release="r1",
    )
    public = reporter.flush()
    assert captured[0]["event"] == "api_health_minute"
    assert captured[0]["distinct_id"] == "mushukistan-api"
    assert "_samples" not in public and public["release"] == "r1"
    assert public["feed_recent_count"] == 1


def test_reporter_start_announces_and_stop_cancels() -> None:
    captured: list[dict] = []
    analytics = SimpleNamespace(capture=lambda **kwargs: captured.append(kwargs))
    notifier = FakeNotifier()
    reporter = OpsReporter(
        OpsMetrics(),
        interval_seconds=60,
        analytics_client=analytics,
        alerter=OpsAlerter(notifier, AlertThresholds(), label="t"),
        release="r1",
    )

    async def run() -> None:
        reporter.start()
        await asyncio.sleep(0.05)
        await reporter.stop()

    asyncio.run(run())
    assert captured[0]["event"] == "api_started"
    assert notifier.sent == []  # Telegram hears about a start only after a full interval


def test_start_notice_is_sent_once_after_the_first_interval() -> None:
    notifier = FakeNotifier()
    reporter = OpsReporter(
        OpsMetrics(),
        interval_seconds=0.02,
        analytics_client=None,
        alerter=OpsAlerter(notifier, AlertThresholds(), label="t"),
        release="r1",
    )

    async def run() -> None:
        reporter.start()
        await asyncio.sleep(0.15)  # several intervals
        await reporter.stop()

    asyncio.run(run())
    assert notifier.sent == ["INFO t: API started, release r1"]
