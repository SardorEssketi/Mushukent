"""One multipart upload in flight per user (load audit LT-10, FIX-6).

Publications and avatars carry up to five images. Two or more at once from the same account were
enough to exhaust the API's memory, and the per-user upload rate limit (10/min) allows ten in
parallel. This middleware answers a second concurrent multipart upload from the same verified user
with ``409 PUBLICATION_IN_PROGRESS`` **before the body is read**, so the rejected request never
costs memory. Text-only (JSON) edits are not uploads and pass through.

The code is the one the app already treats as "still processing, check again"
(``publication_retry.dart``), so existing builds show a waiting state instead of a failure. The
operation was never reserved, so a later retry with the same Idempotency-Key creates it normally.

State is per process, which matches the single-worker deployment (see ``rate_limit.py``).
"""

from __future__ import annotations

import threading
from collections.abc import Callable
from typing import Any

from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Receive, Scope, Send

from app.core.request_auth import decode_access_token_once

UPLOAD_BASES = ("/api/v1/posts", "/api/v1/lost-pets", "/api/v1/adoption-posts", "/api/v1/cats")
AVATAR_PATH = "/api/v1/users/me/avatar"


def is_upload_request(scope: Scope) -> bool:
    if scope.get("type") != "http" or scope.get("method") not in {"POST", "PATCH"}:
        return False
    content_type = dict(scope.get("headers") or []).get(b"content-type", b"")
    if not content_type.lower().startswith(b"multipart/form-data"):
        return False
    path = scope.get("path", "").rstrip("/")
    if path == AVATAR_PATH:
        return True
    for base in UPLOAD_BASES:
        if path == base or (path.startswith(base + "/") and "/" not in path[len(base) + 1 :]):
            return True
    return False


class UploadSingleFlightMiddleware:
    def __init__(self, app: ASGIApp, *, identify: Callable[[Scope], Any | None]) -> None:
        self.app = app
        self.identify = identify
        self._in_flight: set[Any] = set()
        self._lock = threading.Lock()

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if not is_upload_request(scope):
            await self.app(scope, receive, send)
            return
        user = self.identify(scope)
        if user is None:  # unauthenticated: the route rejects it without reading images
            await self.app(scope, receive, send)
            return
        with self._lock:
            busy = user in self._in_flight
            if not busy:
                self._in_flight.add(user)
        if busy:
            response = JSONResponse(
                status_code=409,
                content={
                    "success": False,
                    "error": {
                        "code": "PUBLICATION_IN_PROGRESS",
                        "message": "Another upload from this account is still processing. "
                        "Try again when it has finished.",
                    },
                },
            )
            await response(scope, receive, send)
            return
        try:
            await self.app(scope, receive, send)
        finally:
            with self._lock:
                self._in_flight.discard(user)


def verified_user_identifier(token_service) -> Callable[[Scope], Any | None]:
    """User id from a verified Bearer token, else None (same rule as the rate limiter)."""

    def identify(scope: Scope) -> Any | None:
        authorization = dict(scope.get("headers") or []).get(b"authorization", b"")
        scheme, _, token = authorization.decode("latin-1").partition(" ")
        token = token.strip()
        if scheme.casefold() != "bearer" or not token or len(token) > 4096:
            return None
        try:
            return decode_access_token_once(scope, token_service, token).user_id
        except Exception:
            return None

    return identify
