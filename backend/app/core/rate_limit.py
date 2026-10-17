from __future__ import annotations

import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from ipaddress import IPv6Address, ip_address, ip_network
from threading import Lock
from typing import Protocol

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.types import ASGIApp

from app.core.config import Settings
from app.features.auth.infrastructure.tokens import JoseAccessTokenService

# Bearer tokens longer than this are never decoded; they are treated as anonymous.
MAX_BEARER_TOKEN_LENGTH = 4096


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
    """Sliding-window hit log kept in process memory.

    Memory is bounded two ways: idle keys are swept every ``sweep_interval`` seconds (a key
    disappears once all its hits are older than its window), and ``max_keys`` caps the number of
    live keys even under a flood of distinct identities by evicting the least recently active
    ones. Each key stores at most ``limit`` timestamps because rejected requests are not
    recorded. Everything runs under one lock, so sweeping cannot interleave with a hit.

    Counters are per process. With a single worker process (the deployed configuration) the
    limits are exact; with N workers each process enforces its own counters.
    """

    def __init__(self, *, max_keys: int = 50_000, sweep_interval: float = 30.0) -> None:
        self._hits: dict[str, tuple[int, deque[float]]] = {}
        self._lock = Lock()
        self._max_keys = max_keys
        self._sweep_interval = sweep_interval
        self._last_sweep: float | None = None

    def __len__(self) -> int:
        with self._lock:
            return len(self._hits)

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
            self._maybe_sweep(now)
            entry = self._hits.get(key)
            if entry is None:
                hits: deque[float] = deque()
                self._hits[key] = (window_seconds, hits)
            else:
                hits = entry[1]
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

    def _maybe_sweep(self, now: float) -> None:
        if self._last_sweep is None:
            self._last_sweep = now
        due = now - self._last_sweep >= self._sweep_interval
        if not due and len(self._hits) <= self._max_keys:
            return
        self._last_sweep = now
        for key in list(self._hits):
            window_seconds, hits = self._hits[key]
            window_start = now - window_seconds
            while hits and hits[0] <= window_start:
                hits.popleft()
            if not hits:
                del self._hits[key]
        if len(self._hits) > self._max_keys:
            # Still over the cap with only live keys: drop the least recently active 10%.
            surplus = len(self._hits) - int(self._max_keys * 0.9)
            oldest = sorted(self._hits, key=lambda k: self._hits[k][1][-1])[:surplus]
            for key in oldest:
                del self._hits[key]


class FixedWindowRateLimiter:
    def __init__(
        self,
        *,
        store: RateLimitStore | None = None,
        window_seconds: int = 60,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.store = store if store is not None else InMemoryRateLimitStore()
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
    token_service = JoseAccessTokenService(settings)

    @app.middleware("http")
    async def rate_limit_middleware(request: Request, call_next: ASGIApp):
        if request.method.upper() == "OPTIONS":
            return await call_next(request)
        key, limit = _rate_limit_key_and_limit(request, settings, token_service)
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


def _rate_limit_key_and_limit(
    request: Request,
    settings: Settings,
    token_service: JoseAccessTokenService | None = None,
) -> tuple[str, int]:
    path = request.url.path.rstrip("/")
    api_prefix = settings.api_prefix.rstrip("/")
    is_auth_endpoint = path.startswith(f"{api_prefix}/auth")
    is_account_deletion_endpoint = path in {
        f"{api_prefix}/users/account-deletion-requests",
        f"{api_prefix}/users/account-deletion-confirmations",
    }
    method = request.method.upper()
    upload_paths = {
        f"{api_prefix}/posts",
        f"{api_prefix}/lost-pets",
        f"{api_prefix}/adoption-posts",
        f"{api_prefix}/cats",
        f"{api_prefix}/users/me/avatar",
    }
    is_upload_endpoint = path in upload_paths and method in {"POST", "PATCH"}
    if method == "PATCH" and path.startswith(f"{api_prefix}/posts/"):
        is_upload_endpoint = True
    is_public_read_endpoint = request.method.upper() == "GET" and (
        path == f"{api_prefix}/feed"
        or path == f"{api_prefix}/cats"
        or path == f"{api_prefix}/lost-pets"
        or path == f"{api_prefix}/adoption-posts"
        or path == f"{api_prefix}/places"
        or path.startswith(f"{api_prefix}/leaderboards/")
    )

    if is_auth_endpoint or is_account_deletion_endpoint:
        return f"auth:ip:{_client_ip(request, settings)}", settings.rate_limit_auth_per_minute

    # Identity: a *verified* user id, otherwise the trusted client address. An unverifiable
    # Bearer token (garbage, expired, wrong signature) never creates its own bucket.
    user_id = _verified_user_id(request, token_service or JoseAccessTokenService(settings))
    bearer_identity = f"user:{user_id}" if user_id is not None else None
    actor = (
        bearer_identity if bearer_identity is not None else f"ip:{_client_ip(request, settings)}"
    )

    if is_upload_endpoint:
        return f"upload:{actor}", settings.rate_limit_upload_per_minute

    if is_public_read_endpoint:
        return f"public-read:{actor}", settings.rate_limit_public_read_per_minute

    if bearer_identity is not None:
        return bearer_identity, settings.rate_limit_user_per_minute
    return f"anon:ip:{_client_ip(request, settings)}", settings.rate_limit_anon_per_minute


def _client_ip(request: Request, settings: Settings) -> str:
    """Trusted client address used as the rate-limit identity of unauthenticated callers.

    ``X-Forwarded-For`` is honoured only when the immediate peer is a trusted proxy (nginx in the
    Docker network), and then the *rightmost* address that is not itself a trusted proxy is used.
    nginx appends the real peer to the right of whatever the client sent, so anything a client
    puts on the left is ignored. IPv6 callers are keyed by their /64, because one subscriber
    typically controls a whole /64 and could otherwise rotate addresses for free.
    """
    immediate_client = request.client.host if request.client is not None else None
    if immediate_client is None:
        return "unknown"
    try:
        immediate_address = ip_address(immediate_client)
    except ValueError:
        return immediate_client

    is_trusted_proxy = any(immediate_address in network for network in settings.trusted_proxy_cidrs)
    forwarded_for = request.headers.get("x-forwarded-for")
    if is_trusted_proxy and forwarded_for:
        chain = [part.strip() for part in forwarded_for.split(",") if part.strip()]
        for candidate in reversed(chain):
            try:
                candidate_address = ip_address(candidate)
            except ValueError:
                continue
            if not any(candidate_address in network for network in settings.trusted_proxy_cidrs):
                return _normalize_address(candidate_address)
    return _normalize_address(immediate_address)


def _normalize_address(address) -> str:
    if isinstance(address, IPv6Address):
        if address.ipv4_mapped is not None:
            return str(address.ipv4_mapped)
        return f"{ip_network(f'{address}/64', strict=False).network_address}/64"
    return str(address)


def _verified_user_id(request: Request, token_service: JoseAccessTokenService):
    """User id from a Bearer token whose signature, expiry, issuer and audience verify.

    Anything else (missing, malformed, oversized, expired, forged) returns ``None`` and the
    caller is rate-limited as an anonymous client by address. Routes still reject the bad token
    themselves; this only decides which bucket the request is counted in.
    """
    authorization = request.headers.get("authorization")
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    token = token.strip()
    if scheme.casefold() != "bearer" or not token or len(token) > MAX_BEARER_TOKEN_LENGTH:
        return None
    try:
        return token_service.decode_access_token(token).user_id
    except Exception:
        return None


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
