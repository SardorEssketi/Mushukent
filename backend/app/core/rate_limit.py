from __future__ import annotations

import hashlib
import time
from collections import defaultdict, deque
from collections.abc import Callable, MutableMapping
from dataclasses import dataclass
from threading import Lock
from typing import Protocol

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.types import ASGIApp

from app.core.config import Settings


@dataclass(frozen=True, slots=True)
class RateLimitDecision:
    allowed: bool
    retry_after_seconds: int = 0


class RateLimitStore(Protocol):
    def hit(
        self,
        *,
        key: str,
        limit: int,
        window_seconds: int,
        now: float,
    ) -> RateLimitDecision: ...


class InMemoryRateLimitStore:
    def __init__(
        self,
        *,
        hits: MutableMapping[str, deque[float]] | None = None,
    ) -> None:
        self._hits = hits or defaultdict(deque)
        self._lock = Lock()

    def hit(
        self,
        *,
        key: str,
        limit: int,
        window_seconds: int,
        now: float,
    ) -> RateLimitDecision:
        if limit <= 0:
            return RateLimitDecision(allowed=False, retry_after_seconds=window_seconds)

        window_start = now - window_seconds

        with self._lock:
            hits = self._hits[key]
            while hits and hits[0] <= window_start:
                hits.popleft()

            if len(hits) >= limit:
                retry_after = max(1, int(hits[0] + window_seconds - now))
                return RateLimitDecision(
                    allowed=False,
                    retry_after_seconds=retry_after,
                )

            hits.append(now)
            return RateLimitDecision(allowed=True)


class FixedWindowRateLimiter:
    def __init__(
        self,
        *,
        store: RateLimitStore | None = None,
        window_seconds: int = 60,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.store = store or InMemoryRateLimitStore()
        self.window_seconds = window_seconds
        self.clock = clock

    def check(self, *, key: str, limit: int) -> RateLimitDecision:
        return self.store.hit(
            key=key,
            limit=limit,
            window_seconds=self.window_seconds,
            now=self.clock(),
        )


def add_rate_limit_middleware(
    app: FastAPI,
    *,
    settings: Settings,
    limiter: FixedWindowRateLimiter | None = None,
) -> None:
    if not settings.rate_limit_enabled:
        return

    active_limiter = limiter or _build_rate_limiter(settings)

    @app.middleware("http")
    async def rate_limit_middleware(request: Request, call_next: ASGIApp):
        if request.method.upper() == "OPTIONS":
            return await call_next(request)
        key, limit = _rate_limit_key_and_limit(request, settings)
        decision = active_limiter.check(key=key, limit=limit)
        if not decision.allowed:
            return _rate_limit_response(decision.retry_after_seconds)
        return await call_next(request)


def _build_rate_limiter(settings: Settings) -> FixedWindowRateLimiter:
    backend = settings.rate_limit_backend.casefold()
    if backend == "memory":
        return FixedWindowRateLimiter(store=InMemoryRateLimitStore())
    if backend == "redis":
        raise RuntimeError(
            "RATE_LIMIT_BACKEND=redis is reserved for future horizontal scaling. "
            "Add a Redis RateLimitStore implementation before enabling it."
        )
    raise RuntimeError(f"Unsupported RATE_LIMIT_BACKEND value: {settings.rate_limit_backend}")


def _rate_limit_key_and_limit(request: Request, settings: Settings) -> tuple[str, int]:
    path = request.url.path.rstrip("/")
    api_prefix = settings.api_prefix.rstrip("/")
    is_auth_endpoint = path.startswith(f"{api_prefix}/auth")
    is_upload_endpoint = request.method.upper() == "POST" and path == f"{api_prefix}/posts"
    is_public_read_endpoint = request.method.upper() == "GET" and (
        path == f"{api_prefix}/feed"
        or path == f"{api_prefix}/cats"
        or path == f"{api_prefix}/lost-pets"
        or path == f"{api_prefix}/adoption-posts"
        or path == f"{api_prefix}/places"
        or path.startswith(f"{api_prefix}/leaderboards/")
    )

    if is_auth_endpoint:
        return f"auth:ip:{_client_ip(request)}", settings.rate_limit_auth_per_minute

    bearer_identity = _bearer_identity(request)
    actor = bearer_identity if bearer_identity is not None else f"ip:{_client_ip(request)}"

    if is_upload_endpoint:
        return f"upload:{actor}", settings.rate_limit_upload_per_minute

    if is_public_read_endpoint:
        return f"public-read:{actor}", settings.rate_limit_public_read_per_minute

    if bearer_identity is not None:
        return f"user:{bearer_identity}", settings.rate_limit_user_per_minute
    return f"anon:ip:{_client_ip(request)}", settings.rate_limit_anon_per_minute


def _client_ip(request: Request) -> str:
    forwarded_for = request.headers.get("x-forwarded-for")
    if forwarded_for:
        return forwarded_for.split(",", maxsplit=1)[0].strip()
    if request.client is not None:
        return request.client.host
    return "unknown"


def _bearer_identity(request: Request) -> str | None:
    authorization = request.headers.get("authorization")
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.casefold() != "bearer" or not token:
        return None
    digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
    return f"token:{digest}"


def _rate_limit_response(retry_after_seconds: int) -> JSONResponse:
    return JSONResponse(
        status_code=429,
        headers={"Retry-After": str(retry_after_seconds)},
        content={
            "success": False,
            "error": {
                "code": "RATE_LIMIT_EXCEEDED",
                "message": "Too many requests.",
            },
        },
    )
