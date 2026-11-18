from __future__ import annotations

import hashlib
import json
import re
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from ipaddress import IPv6Address, ip_address, ip_network
from threading import Lock
from typing import Protocol

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.requests import ClientDisconnect
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from app.core.config import Settings
from app.core.request_auth import decode_access_token_once
from app.features.auth.infrastructure.tokens import JoseAccessTokenService

# Bearer tokens longer than this are never decoded; they are treated as anonymous.
MAX_BEARER_TOKEN_LENGTH = 4096

# Load audit FIX-7: read-only public GETs that guests and map/feed users call constantly. They
# share the generous public-read bucket instead of the 30/min anonymous one, which a few users
# behind one carrier-NAT address exhausted in minutes (LT-08).
_PUBLIC_READ_DETAIL = re.compile(
    r"^/(posts|cats|lost-pets|adoption-posts|places)/[^/]+$"
    r"|^/(posts|lost-pets|adoption-posts)/[^/]+/comments$"
    r"|^/cats/[^/]+/posts$"
    r"|^/lost-pets/map$"
)
# View counting is telemetry: own bucket, so it never competes with real reads.
_TELEMETRY = re.compile(r"^/views/seen$|^/(posts|lost-pets|adoption-posts)/[^/]+/views$")


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
    # Same place in the middleware stack as the former ``@app.middleware("http")`` registration.
    app.add_middleware(
        RateLimitMiddleware,
        settings=settings,
        limiter=limiter or _build_rate_limiter(settings),
        token_service=JoseAccessTokenService(settings),
    )


class RateLimitMiddleware:
    """Per-bucket rate limiting as plain ASGI middleware.

    Replaces a Starlette ``BaseHTTPMiddleware`` (load audit step 2, fix C), which ran every request
    through an extra task, memory streams and a re-wrapped response. Responses are unchanged:
    allowed requests pass through untouched, limited ones get the same 429 JSON and Retry-After.
    Only POST /auth/refresh has its body read here (to key the refresh session); that body is
    replayed to the route exactly as received.
    """

    def __init__(
        self,
        app: ASGIApp,
        *,
        settings: Settings,
        limiter: FixedWindowRateLimiter,
        token_service: JoseAccessTokenService,
    ) -> None:
        self.app = app
        self.settings = settings
        self.limiter = limiter
        self.token_service = token_service
        self._refresh_path = f"{settings.api_prefix.rstrip('/')}/auth/refresh"

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http" or scope["method"].upper() == "OPTIONS":
            await self.app(scope, receive, send)
            return
        request = Request(scope)
        if scope["method"].upper() == "POST" and request.url.path.rstrip("/") == self._refresh_path:
            try:
                body, receive = await _buffered(receive)
            except ClientDisconnect:
                return  # the client left before sending its body; nothing to answer
            refresh_keys = _refresh_session_keys(request, self.settings, body)
            if refresh_keys is not None:
                # Backstop per address first, then the session's own budget.
                for key, limit in refresh_keys:
                    decision = self.limiter.check(key=key, limit=limit)
                    if not decision.allowed:
                        await _rate_limit_response(decision.retry_after_seconds)(
                            scope, receive, send
                        )
                        return
                await self.app(scope, receive, send)
                return
        key, limit = _rate_limit_key_and_limit(request, self.settings, self.token_service)
        decision = self.limiter.check(key=key, limit=limit)
        if not decision.allowed:
            await _rate_limit_response(decision.retry_after_seconds)(scope, receive, send)
            return
        await self.app(scope, receive, send)


async def _buffered(receive: Receive) -> tuple[bytes, Receive]:
    """Read the whole request body; return it and a receive() that replays it, then continues."""
    chunks: list[bytes] = []
    while True:
        message = await receive()
        if message["type"] == "http.disconnect":
            raise ClientDisconnect()
        chunks.append(message.get("body", b""))
        if not message.get("more_body", False):
            break
    body = b"".join(chunks)
    replayed = False

    async def replay() -> Message:
        nonlocal replayed
        if not replayed:
            replayed = True
            return {"type": "http.request", "body": body, "more_body": False}
        return await receive()

    return body, replay


def _refresh_session_keys(
    request: Request, settings: Settings, body: bytes
) -> list[tuple[str, int]] | None:
    """Buckets for POST /auth/refresh: per refresh session plus a per-IP backstop.

    Returns None when this is not a refresh with a usable token, so the request falls back to
    the per-IP auth bucket. Behind carrier NAT many users refresh from one address after an
    idle period; a per-IP limit of 10/min failed most of them (load audit LT-08). The body is
    replayed to the route by the middleware.
    """
    try:
        payload = json.loads(body or b"{}")
    except (ValueError, UnicodeDecodeError):
        return None
    token = payload.get("refresh_token") if isinstance(payload, dict) else None
    if not isinstance(token, str) or not token.strip() or len(token) > MAX_BEARER_TOKEN_LENGTH:
        return None
    session = hashlib.sha256(token.encode("utf-8")).hexdigest()
    return [
        (
            f"refresh-ip:ip:{_client_ip(request, settings)}",
            settings.rate_limit_refresh_ip_per_minute,
        ),
        (f"refresh:session:{session}", settings.rate_limit_refresh_per_minute),
    ]


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
    relative = path[len(api_prefix) :] if path.startswith(api_prefix) else path
    is_public_read_endpoint = request.method.upper() == "GET" and (
        path == f"{api_prefix}/feed"
        or path == f"{api_prefix}/cats"
        or path == f"{api_prefix}/lost-pets"
        or path == f"{api_prefix}/adoption-posts"
        or path == f"{api_prefix}/places"
        or path.startswith(f"{api_prefix}/leaderboards/")
        or bool(_PUBLIC_READ_DETAIL.match(relative))
    )
    is_telemetry_endpoint = method == "POST" and bool(_TELEMETRY.match(relative))

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

    if is_telemetry_endpoint:
        default = (
            settings.rate_limit_user_per_minute
            if bearer_identity is not None
            else settings.rate_limit_anon_per_minute
        )
        return f"telemetry:{actor}", settings.rate_limit_telemetry_per_minute or default

    if bearer_identity is not None:
        return bearer_identity, settings.rate_limit_user_per_minute
    return f"anon:ip:{_client_ip(request, settings)}", settings.rate_limit_anon_per_minute


def client_address(request: Request, settings: Settings) -> str:
    """Public alias of the trusted client address (used by the ops metrics' active-user count)."""
    return _client_ip(request, settings)


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
        return decode_access_token_once(request.scope, token_service, token).user_id
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
