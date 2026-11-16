"""Cap the number of in-flight API requests (load audit LT-02/LT-18, FIX-1 follow-up).

Route handlers are synchronous and run in a thread pool; when a client gives up (the app times
out after 15 s, nginx after 30 s), its handler still runs to the end. Without a cap, a spike leaves
thousands of accepted requests queued behind ~15 database connections, and the API stays
unusable for minutes after the users are gone (measured: 167 s with the database already idle).

With the cap, requests beyond ``max_in_flight`` are answered immediately with
``503 SERVICE_BUSY`` and ``Retry-After``, which the app turns into a short "busy, retrying"
state. The queue can no longer outgrow what the pool drains in seconds. The health check is
never shed, so the container is not restarted for being busy.

Per process, which matches the single-worker deployment.
"""

from __future__ import annotations

import threading

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

EXEMPT_PATHS = frozenset({"/api/v1/health"})


class LoadSheddingMiddleware:
    def __init__(self, app: ASGIApp, *, max_in_flight: int, retry_after: int) -> None:
        self.app = app
        self.max_in_flight = max_in_flight
        self.retry_after = retry_after
        self._in_flight = 0
        self._lock = threading.Lock()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope.get("path") in EXEMPT_PATHS:
            await self.app(scope, receive, send)
            return
        with self._lock:
            admitted = self._in_flight < self.max_in_flight
            if admitted:
                self._in_flight += 1
        if not admitted:
            scope.setdefault("state", {})["service_busy_reason"] = "in_flight_cap"  # ops metrics
            response = JSONResponse(
                status_code=503,
                headers={"Retry-After": str(self.retry_after)},
                content={
                    "success": False,
                    "error": {
                        "code": "SERVICE_BUSY",
                        "message": "The service is busy. Please try again shortly.",
                    },
                },
            )
            await response(scope, receive, send)
            return
        try:
            await self.app(scope, receive, send)
        finally:
            with self._lock:
                self._in_flight -= 1
