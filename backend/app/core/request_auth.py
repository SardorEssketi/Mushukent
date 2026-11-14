"""Decode a request's access token once and share the result (load audit step 2, fix B).

A signed-in request used to verify the same JWT up to four times: PostHog context, upload guard,
rate limiter and the auth dependency. Each caller still applies its own rules for *which* token it
accepts (header parsing, length cap, how errors are treated); only the verification itself is done
once per request and remembered in the request state (``scope["state"]``, i.e. ``request.state``).

The cache is keyed by the raw token and the verifier's configuration (secret, algorithm, audience,
issuer, leeway), so a caller that extracts a different string, or verifies with other settings,
never gets a result that belongs to another token or verifier. A failed verification is cached
as the raised error and re-raised, so every caller sees exactly what a fresh decode would have
raised.
"""

from __future__ import annotations

from collections.abc import MutableMapping
from typing import Any, Protocol

from app.core.auth import AuthenticatedPrincipal

_STATE_KEY = "access_token_decode"


class _Decoder(Protocol):
    def decode_access_token(self, token: str) -> AuthenticatedPrincipal: ...


def _verifier_key(token_service: _Decoder) -> tuple:
    settings = getattr(token_service, "settings", None)
    if settings is None:
        return (id(token_service),)
    return (
        settings.jwt_secret_key,
        settings.jwt_algorithm,
        settings.jwt_audience,
        settings.jwt_issuer,
        settings.jwt_clock_skew_seconds,
    )


def decode_access_token_once(
    scope: MutableMapping[str, Any], token_service: _Decoder, token: str
) -> AuthenticatedPrincipal:
    state = scope.get("state")
    if state is None:
        state = scope["state"] = {}
    key = (token, _verifier_key(token_service))
    cached = state.get(_STATE_KEY)
    if cached is not None and cached[0] == key:
        outcome = cached[1]
    else:
        try:
            outcome = token_service.decode_access_token(token)
        except Exception as exc:  # cached and re-raised below, unchanged
            outcome = exc
        state[_STATE_KEY] = (key, outcome)
    if isinstance(outcome, Exception):
        raise outcome
    return outcome
