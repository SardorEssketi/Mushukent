"""Bounded in-flight requests (load audit LT-02/LT-18, FIX-1 follow-up).

Sync handlers cannot be cancelled when a client gives up, so an unbounded backlog keeps the
API busy for minutes after a spike. Beyond the cap, requests are answered at once with
503 SERVICE_BUSY + Retry-After; the health check is never shed.
"""

from __future__ import annotations

import threading

from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core.load_shedding import LoadSheddingMiddleware


def _app(release: threading.Event, started: threading.Semaphore, max_in_flight: int) -> TestClient:
    app = FastAPI()

    @app.get("/api/v1/slow")
    def slow() -> dict[str, str]:
        started.release()
        release.wait(5)
        return {"ok": "yes"}

    @app.get("/api/v1/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    app.add_middleware(LoadSheddingMiddleware, max_in_flight=max_in_flight, retry_after=7)
    return TestClient(app)


def test_requests_beyond_the_cap_are_shed_immediately_and_recover() -> None:
    release, started = threading.Event(), threading.Semaphore(0)
    client = _app(release, started, max_in_flight=2)
    results: list[int] = []
    workers = [
        threading.Thread(target=lambda: results.append(client.get("/api/v1/slow").status_code))
        for _ in range(2)
    ]
    for worker in workers:
        worker.start()
    for _ in range(2):
        assert started.acquire(timeout=5)

    shed = client.get("/api/v1/slow")
    assert shed.status_code == 503
    assert shed.json()["error"]["code"] == "SERVICE_BUSY"
    assert shed.headers["Retry-After"] == "7"
    assert client.get("/api/v1/health").status_code == 200  # never shed

    release.set()
    for worker in workers:
        worker.join(5)
    assert results == [200, 200]
    assert client.get("/api/v1/slow").status_code == 200  # capacity is released


def test_the_counter_is_released_when_a_handler_fails() -> None:
    app = FastAPI()

    @app.get("/api/v1/boom")
    def boom() -> None:
        raise RuntimeError("failure")

    app.add_middleware(LoadSheddingMiddleware, max_in_flight=1, retry_after=5)
    client = TestClient(app, raise_server_exceptions=False)
    for _ in range(3):
        assert client.get("/api/v1/boom").status_code == 500  # never 503
