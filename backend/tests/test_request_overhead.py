"""Per-request framework overhead (load audit step 2 profile).

py-spy at the baseline mix: ~41% of the backend's Python CPU was thread-pool hand-offs, because
FastAPI runs every *sync* dependency in its own thread-pool round trip, and a signed-in request
decoded the same JWT three times (rate limiter, PostHog context, auth dependency).
"""

from __future__ import annotations

import inspect

from fastapi.testclient import TestClient

from app.core import dependencies
from app.core.config import get_settings
from app.features.auth.infrastructure.tokens import JoseAccessTokenService

# Providers that only build objects from the container or check a flag: no I/O, so they belong on
# the event loop. The user lookup (DB), the DB session, the auth service and the Google verifier
# stay synchronous.
NON_BLOCKING = [
    "get_container",
    "get_password_hasher",
    "get_access_token_service",
    "get_authorization_service",
    "get_users_service",
    "get_cats_service",
    "get_posts_service",
    "get_feed_service",
    "get_likes_service",
    "get_views_service",
    "get_comments_service",
    "get_reports_service",
    "get_feedback_service",
    "get_moderation_service",
    "get_leaderboard_service",
    "get_places_service",
    "get_lost_pets_service",
    "get_adoption_posts_service",
    "get_notification_service",
    "get_object_storage",
    "get_media_storage_service",
    "get_current_principal",
    "get_current_active_user",
    "require_moderator",
]
BLOCKING = ["get_current_user", "get_optional_current_user", "get_db_session"]


def test_non_blocking_providers_run_on_the_event_loop() -> None:
    sync = [
        name
        for name in NON_BLOCKING
        if not inspect.iscoroutinefunction(getattr(dependencies, name))
    ]
    assert sync == []


def test_bearer_token_parsing_runs_on_the_event_loop() -> None:
    from app.core.security import get_bearer_token

    assert inspect.iscoroutinefunction(get_bearer_token)


def test_database_dependencies_stay_in_the_thread_pool() -> None:
    assert all(not inspect.iscoroutinefunction(getattr(dependencies, name)) for name in BLOCKING)


def test_a_signed_in_request_decodes_its_token_once(monkeypatch) -> None:
    monkeypatch.setenv("RATE_LIMIT_ENABLED", "true")
    # PostHog configured, so its context middleware is active too (dummy, unreachable host).
    monkeypatch.setenv("POSTHOG_PROJECT_TOKEN", "phc_test_dummy")
    monkeypatch.setenv("POSTHOG_HOST", "http://127.0.0.1:9")
    get_settings.cache_clear()
    try:
        from app.core.auth import AuthenticatedPrincipal, Role
        from app.main import create_app

        settings = get_settings()
        token = JoseAccessTokenService(settings).issue_access_token(
            AuthenticatedPrincipal(user_id=__import__("uuid").uuid4(), role=Role.USER)
        )
        calls = []
        original = JoseAccessTokenService.decode_access_token

        def counting(self, raw):
            calls.append(raw)
            return original(self, raw)

        monkeypatch.setattr(JoseAccessTokenService, "decode_access_token", counting)
        app = create_app()
        with TestClient(app, raise_server_exceptions=False) as client:
            # A signed-in endpoint: rate limiter, PostHog context and the auth dependency all
            # need the principal. (No database here, so the request itself may fail.)
            client.get(
                "/api/v1/notifications/unread-count",
                headers={"Authorization": f"Bearer {token}"},
            )
        assert len(calls) == 1
    finally:
        get_settings.cache_clear()


def test_the_cache_never_mixes_verifiers_or_tokens() -> None:
    """A guard that verifies with other settings must not poison the auth dependency's result."""
    from dataclasses import dataclass

    from fastapi import HTTPException

    from app.core.request_auth import decode_access_token_once

    @dataclass
    class Settings:
        jwt_secret_key: str
        jwt_algorithm: str = "HS256"
        jwt_audience: str = "a"
        jwt_issuer: str = "i"
        jwt_clock_skew_seconds: int = 0

    class Verifier:
        def __init__(self, secret: str) -> None:
            self.settings = Settings(secret)
            self.calls = 0

        def decode_access_token(self, token: str):
            self.calls += 1
            if self.settings.jwt_secret_key != "right":
                raise HTTPException(401)
            return f"principal:{token}"

    scope: dict = {}
    wrong, right = Verifier("wrong"), Verifier("right")
    try:
        decode_access_token_once(scope, wrong, "t1")
    except HTTPException:
        pass
    assert decode_access_token_once(scope, right, "t1") == "principal:t1"
    assert decode_access_token_once(scope, right, "t1") == "principal:t1"
    assert right.calls == 1
    assert decode_access_token_once(scope, right, "t2") == "principal:t2"
    assert right.calls == 2
