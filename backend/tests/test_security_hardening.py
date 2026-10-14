"""Security regression tests: rate-limit identity, limiter memory and fail-closed APP_ENV.

Covers audit findings F-02 (random Bearer tokens bypass limits), F-03 (unbounded limiter
memory, per-process counters) and F-12 (APP_ENV defaulted to development and leaked
email-verification tokens). None of these tests touch a real database or network.
"""

from __future__ import annotations

import secrets
import sys
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from jose import jwt
from pydantic import ValidationError
from starlette.requests import Request

from app.core.auth import AuthenticatedPrincipal, Role
from app.core.config import Settings, get_settings
from app.core.dependencies import get_auth_service
from app.core.rate_limit import (
    FixedWindowRateLimiter,
    InMemoryRateLimitStore,
    _client_ip,
    _rate_limit_key_and_limit,
)
from app.features.auth.application.service import AuthService
from app.features.auth.infrastructure.email import EmailVerificationSender
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.main import app, create_app

sys.path.insert(0, str(Path(__file__).parent))
from test_auth import (  # noqa: E402
    InMemoryAuthUserRepository,
    InMemorySessionManager,
    StubGoogleVerifier,
)

SECRET = "a-test-signing-secret-that-is-long-enough-123"


# ----------------------------------------------------------------------------- helpers


@pytest.fixture()
def limits(monkeypatch: pytest.MonkeyPatch):
    """Tiny limits so tests need only a few requests; restores settings afterwards."""

    def configure(**values: str) -> Settings:
        defaults = {
            "RATE_LIMIT_ENABLED": "true",
            "RATE_LIMIT_ANON_PER_MINUTE": "3",
            "RATE_LIMIT_USER_PER_MINUTE": "3",
            "RATE_LIMIT_PUBLIC_READ_PER_MINUTE": "3",
            "RATE_LIMIT_UPLOAD_PER_MINUTE": "3",
            "RATE_LIMIT_AUTH_PER_MINUTE": "3",
            "JWT_SECRET_KEY": SECRET,
            "JWT_ISSUER": "mushukistan-api",
            "JWT_AUDIENCE": "mushukistan-mobile",
        }
        for name, value in {**defaults, **values}.items():
            monkeypatch.setenv(name, value)
        get_settings.cache_clear()
        return get_settings()

    yield configure
    get_settings.cache_clear()


def access_token(settings: Settings, user_id=None) -> str:
    return JoseAccessTokenService(settings).issue_access_token(
        AuthenticatedPrincipal(user_id=user_id or uuid4(), role=Role.USER)
    )


def make_request(
    path: str = "/api/v1/health",
    *,
    method: str = "GET",
    headers: list[tuple[bytes, bytes]] | None = None,
    client: tuple[str, int] = ("203.0.113.10", 5000),
) -> Request:
    return Request(
        {
            "type": "http",
            "method": method,
            "path": path,
            "headers": headers or [],
            "client": client,
            "server": ("testserver", 80),
            "scheme": "http",
            "query_string": b"",
        }
    )


def bearer(token: str) -> list[tuple[bytes, bytes]]:
    return [(b"authorization", f"Bearer {token}".encode())]


# -------------------------------------------------------- F-02: identity of the caller


def test_random_bearer_tokens_cannot_mint_fresh_rate_limit_identities(limits) -> None:
    """The audit exploit: 200 requests, each with a different random token, were never limited."""
    limits()
    with TestClient(create_app()) as client:
        statuses = [
            client.get(
                "/api/v1/health", headers={"Authorization": f"Bearer {secrets.token_hex(16)}"}
            ).status_code
            for _ in range(200)
        ]
    assert statuses.count(200) == 3  # exactly the anonymous allowance for this address
    assert statuses.count(429) == 197


def test_unverifiable_tokens_share_the_anonymous_ip_bucket(limits) -> None:
    settings = limits()
    anonymous_key, anonymous_limit = _rate_limit_key_and_limit(make_request(), settings)
    assert anonymous_key == "anon:ip:203.0.113.10"
    expired = jwt.encode(
        {
            "sub": str(uuid4()),
            "role": "user",
            "iss": settings.jwt_issuer,
            "aud": settings.jwt_audience,
            "exp": int((datetime.now(UTC) - timedelta(hours=1)).timestamp()),
            "token_type": "access",
        },
        SECRET,
        algorithm="HS256",
    )
    wrong_audience = jwt.encode(
        {
            "sub": str(uuid4()),
            "role": "user",
            "iss": settings.jwt_issuer,
            "aud": "someone-else",
            "exp": int((datetime.now(UTC) + timedelta(hours=1)).timestamp()),
            "token_type": "access",
        },
        SECRET,
        algorithm="HS256",
    )
    wrong_type = jwt.encode(
        {
            "sub": str(uuid4()),
            "role": "user",
            "iss": settings.jwt_issuer,
            "aud": settings.jwt_audience,
            "exp": int((datetime.now(UTC) + timedelta(hours=1)).timestamp()),
            "token_type": "refresh",
        },
        SECRET,
        algorithm="HS256",
    )
    forged = jwt.encode(
        {
            "sub": str(uuid4()),
            "role": "user",
            "iss": settings.jwt_issuer,
            "aud": settings.jwt_audience,
            "exp": int((datetime.now(UTC) + timedelta(hours=1)).timestamp()),
            "token_type": "access",
        },
        "an-attackers-own-secret-an-attackers-own-secret",
        algorithm="HS256",
    )
    for label, token in {
        "random": secrets.token_hex(20),
        "empty-ish": "x",
        "expired": expired,
        "wrong audience": wrong_audience,
        "refresh type": wrong_type,
        "forged signature": forged,
        "truncated": access_token(settings)[:-5],
        "oversized": "a" * 100_000,
        "unicode": "tökén-✓",
    }.items():
        key, limit = _rate_limit_key_and_limit(make_request(headers=bearer(token)), settings)
        assert (key, limit) == (anonymous_key, anonymous_limit), label
    # Non-Bearer schemes and a missing token are anonymous too.
    for header in (b"Basic abc", b"Bearer", b"Bearer ", b"bearer"):
        request = make_request(headers=[(b"authorization", header)])
        assert _rate_limit_key_and_limit(request, settings)[0] == anonymous_key


def test_verified_users_are_counted_per_user_not_per_token(limits) -> None:
    settings = limits()
    user_id = uuid4()
    first = access_token(settings, user_id)
    second = JoseAccessTokenService(settings).issue_access_token(
        AuthenticatedPrincipal(user_id=user_id, role=Role.USER)
    )
    other = access_token(settings, uuid4())
    key_one = _rate_limit_key_and_limit(make_request(headers=bearer(first)), settings)[0]
    key_two = _rate_limit_key_and_limit(make_request(headers=bearer(second)), settings)[0]
    key_other = _rate_limit_key_and_limit(make_request(headers=bearer(other)), settings)[0]
    assert key_one == key_two == f"user:{user_id}"
    assert key_other != key_one


def test_verified_user_limit_is_shared_across_that_users_tokens(limits) -> None:
    settings = limits()
    user_id = uuid4()
    with TestClient(create_app()) as client:
        statuses = [
            client.get(
                "/api/v1/health",
                headers={"Authorization": f"Bearer {access_token(settings, user_id)}"},
            ).status_code
            for _ in range(8)
        ]
    assert statuses.count(200) == 3 and statuses.count(429) == 5


def test_anonymous_exhaustion_does_not_lock_out_a_verified_user_on_the_same_ip(limits) -> None:
    """NAT / shared networks: a signed-in user is not throttled by anonymous neighbours."""
    settings = limits(RATE_LIMIT_ANON_PER_MINUTE="1")
    with TestClient(create_app()) as client:
        assert client.get("/api/v1/health").status_code == 200
        assert client.get("/api/v1/health").status_code == 429
        signed_in = {"Authorization": f"Bearer {access_token(settings)}"}
        assert client.get("/api/v1/health", headers=signed_in).status_code == 200


def test_different_addresses_do_not_share_the_anonymous_limit(limits) -> None:
    settings = limits()
    keys = {
        _rate_limit_key_and_limit(make_request(client=(ip, 1)), settings)[0]
        for ip in ("203.0.113.1", "203.0.113.2", "198.51.100.7")
    }
    assert len(keys) == 3


def test_upload_and_auth_routes_ignore_unverified_tokens_too(limits) -> None:
    settings = limits()
    garbage = bearer(secrets.token_hex(8))
    upload_key, _ = _rate_limit_key_and_limit(
        make_request("/api/v1/posts", method="POST", headers=garbage), settings
    )
    assert upload_key == "upload:ip:203.0.113.10"
    public_key, _ = _rate_limit_key_and_limit(
        make_request("/api/v1/cats", headers=garbage), settings
    )
    assert public_key == "public-read:ip:203.0.113.10"
    auth_key, _ = _rate_limit_key_and_limit(
        make_request("/api/v1/auth/login", method="POST", headers=garbage), settings
    )
    assert auth_key == "auth:ip:203.0.113.10"


def test_legitimate_authentication_flow_is_unchanged(limits) -> None:
    """Login/refresh stay limited per IP, and a valid token still reaches protected routes."""
    settings = limits(RATE_LIMIT_AUTH_PER_MINUTE="2")
    with TestClient(create_app()) as client:
        codes = [client.post("/api/v1/auth/login", json={}).status_code for _ in range(4)]
    assert codes[:2] == [422, 422] and codes[2:] == [429, 429]
    # A signed-in user keeps their own bucket on ordinary routes.
    key, limit = _rate_limit_key_and_limit(
        make_request("/api/v1/users/me", headers=bearer(access_token(settings))), settings
    )
    assert key.startswith("user:") and limit == settings.rate_limit_user_per_minute


# ------------------------------------------------------ F-02: forwarded-for handling


def test_forwarded_for_from_an_untrusted_peer_is_ignored(monkeypatch) -> None:
    monkeypatch.setenv("TRUSTED_PROXY_CIDRS", "172.16.0.0/12")
    settings = Settings(_env_file=None, APP_ENV="development")
    request = make_request(
        headers=[(b"x-forwarded-for", b"198.51.100.99")], client=("203.0.113.10", 1)
    )
    assert _client_ip(request, settings) == "203.0.113.10"


def test_spoofed_left_hand_forwarded_addresses_cannot_change_identity(monkeypatch) -> None:
    """nginx appends the real peer on the right; whatever a client prepends is ignored."""
    monkeypatch.setenv("TRUSTED_PROXY_CIDRS", "172.16.0.0/12")
    settings = Settings(_env_file=None, APP_ENV="development")
    keys = set()
    for spoofed in ("1.1.1.1", "8.8.8.8, 9.9.9.9", "not-an-ip", "10.0.0.1, 172.18.0.5"):
        request = make_request(
            headers=[(b"x-forwarded-for", f"{spoofed}, 203.0.113.50".encode())],
            client=("172.18.0.3", 1),
        )
        keys.add(_client_ip(request, settings))
    assert keys == {"203.0.113.50"}


def test_all_trusted_chain_falls_back_to_the_peer_not_client_supplied_text(monkeypatch) -> None:
    monkeypatch.setenv("TRUSTED_PROXY_CIDRS", "172.16.0.0/12,10.0.0.0/8")
    settings = Settings(_env_file=None, APP_ENV="development")
    request = make_request(
        headers=[(b"x-forwarded-for", b"attacker-chosen-text, 10.1.1.1")],
        client=("172.18.0.3", 1),
    )
    assert _client_ip(request, settings) == "172.18.0.3"


def test_ipv6_clients_are_keyed_by_their_64_and_mapped_ipv4_by_ipv4(monkeypatch) -> None:
    monkeypatch.setenv("TRUSTED_PROXY_CIDRS", "172.16.0.0/12")
    settings = Settings(_env_file=None, APP_ENV="development")
    same_subscriber = {
        _client_ip(make_request(client=(addr, 1)), settings)
        for addr in ("2001:db8:abcd:12::1", "2001:db8:abcd:12:ffff:ffff:ffff:ffff")
    }
    assert same_subscriber == {"2001:db8:abcd:12::/64"}
    other = _client_ip(make_request(client=("2001:db8:abcd:13::1", 1)), settings)
    assert other == "2001:db8:abcd:13::/64"
    assert _client_ip(make_request(client=("::ffff:203.0.113.9", 1)), settings) == "203.0.113.9"
    forwarded = make_request(
        headers=[(b"x-forwarded-for", b"2001:db8:1:2:3:4:5:6")], client=("172.18.0.3", 1)
    )
    assert _client_ip(forwarded, settings) == "2001:db8:1:2::/64"


# --------------------------------------------------------- F-03: limiter memory bounds


def test_expired_keys_are_removed_and_active_limits_stay_effective() -> None:
    now = [1000.0]
    store = InMemoryRateLimitStore(sweep_interval=30.0)
    limiter = FixedWindowRateLimiter(store=store, window_seconds=60, clock=lambda: now[0])
    for index in range(2_000):
        assert limiter.check(key=f"anon:ip:{index}", limit=5).allowed
    assert len(store) == 2_000
    # An active, still-limited key must survive sweeps.
    for _ in range(5):
        assert limiter.check(key="active", limit=5).allowed
    assert not limiter.check(key="active", limit=5).allowed

    now[0] += 45  # past the sweep interval, but the 2,000 idle keys are still inside the window
    assert not limiter.check(key="active", limit=5).allowed
    now[0] += 40  # 85 s in: idle keys are older than the 60 s window and a sweep is due
    limiter.check(key="trigger", limit=5)
    assert len(store) <= 2  # only "active" (hits 65 s old are gone too) and "trigger" remain
    assert limiter.check(key="active", limit=5).allowed  # its window also expired -> fresh
    assert len(store) == 2


def test_limits_reset_exactly_when_the_window_slides() -> None:
    now = [0.0]
    limiter = FixedWindowRateLimiter(
        store=InMemoryRateLimitStore(), window_seconds=60, clock=lambda: now[0]
    )
    assert limiter.check(key="k", limit=2).allowed
    now[0] = 10
    assert limiter.check(key="k", limit=2).allowed
    now[0] = 30
    blocked = limiter.check(key="k", limit=2)
    assert not blocked.allowed and blocked.retry_after_seconds == 30
    now[0] = 61  # first hit (t=0) has left the window
    assert limiter.check(key="k", limit=2).allowed
    assert not limiter.check(key="k", limit=2).allowed


def test_key_count_is_capped_under_a_flood_of_distinct_identities() -> None:
    now = [0.0]
    store = InMemoryRateLimitStore(max_keys=100, sweep_interval=1_000_000.0)
    limiter = FixedWindowRateLimiter(store=store, window_seconds=60, clock=lambda: now[0])
    for index in range(10_000):
        now[0] += 0.001
        limiter.check(key=f"anon:ip:{index}", limit=5)
        assert len(store) <= 101
    assert len(store) <= 100


def test_recently_active_keys_survive_cap_eviction_and_stay_limited() -> None:
    now = [0.0]
    store = InMemoryRateLimitStore(max_keys=50, sweep_interval=1_000_000.0)
    limiter = FixedWindowRateLimiter(store=store, window_seconds=60, clock=lambda: now[0])
    for index in range(200):
        now[0] += 0.01
        limiter.check(key=f"noise:{index}", limit=5)
        # The hot key is touched constantly, so it is never the least recently active.
        limiter.check(key="hot", limit=3)
    assert not limiter.check(key="hot", limit=3).allowed


def test_memory_stays_bounded_under_sustained_traffic_with_varying_identities() -> None:
    """100 requests/second from always-new addresses for 10 minutes of simulated time."""
    now = [0.0]
    store = InMemoryRateLimitStore(sweep_interval=30.0)
    limiter = FixedWindowRateLimiter(store=store, window_seconds=60, clock=lambda: now[0])
    peak = 0
    for second in range(600):
        for request in range(100):
            now[0] = second + request / 100
            limiter.check(key=f"anon:ip:{second}:{request}", limit=30)
        peak = max(peak, len(store))
    # Live keys never exceed ~ (window + sweep interval) * rate, instead of 60,000 total.
    assert peak <= (60 + 30) * 100 + 100
    assert len(store) <= peak


def test_zero_limit_blocks_without_storing_anything() -> None:
    store = InMemoryRateLimitStore()
    decision = store.hit(key="k", limit=0, window_seconds=60, now=0.0)
    assert not decision.allowed and len(store) == 0


# ------------------------------------------------------------------------ concurrency


def test_parallel_requests_on_one_key_never_exceed_the_limit() -> None:
    store = InMemoryRateLimitStore(sweep_interval=0.0)  # sweep on every call
    limiter = FixedWindowRateLimiter(store=store, window_seconds=60)

    def attempt(_: int) -> bool:
        return limiter.check(key="shared", limit=50).allowed

    with ThreadPoolExecutor(max_workers=32) as pool:
        results = list(pool.map(attempt, range(400)))
    assert sum(results) == 50


def test_parallel_distinct_keys_with_continuous_sweeping_are_consistent() -> None:
    store = InMemoryRateLimitStore(max_keys=500, sweep_interval=0.0)
    limiter = FixedWindowRateLimiter(store=store, window_seconds=60)

    def attempt(index: int) -> bool:
        return limiter.check(key=f"anon:ip:{index % 2000}", limit=1_000).allowed

    with ThreadPoolExecutor(max_workers=24) as pool:
        results = list(pool.map(attempt, range(8_000)))
    assert all(results)  # nobody is limited by the cap/sweep races
    assert len(store) <= 500


def test_parallel_http_requests_for_one_verified_user_respect_the_limit(limits) -> None:
    settings = limits(RATE_LIMIT_USER_PER_MINUTE="10")
    token = access_token(settings)

    with TestClient(create_app()) as client:

        def call(_: int) -> int:
            return client.get(
                "/api/v1/health", headers={"Authorization": f"Bearer {token}"}
            ).status_code

        with ThreadPoolExecutor(max_workers=16) as pool:
            statuses = list(pool.map(call, range(60)))
    assert statuses.count(200) == 10 and statuses.count(429) == 50


# ----------------------------------------------------------- F-12: fail-closed APP_ENV


def production_values(**overrides) -> dict[str, object]:
    values: dict[str, object] = {
        "APP_ENV": "production",
        "RATE_LIMIT_ENABLED": "true",  # tests/conftest.py disables it process-wide
        "JWT_SECRET_KEY": secrets.token_urlsafe(48),
        "POSTGRES_PASSWORD": "a-strong-database-password",
        "CORS_ALLOWED_ORIGINS": "https://mushukistan.uz",
        "PUBLIC_APP_BASE_URL": "https://mushukistan.uz",
        "RESEND_API_KEY": "re_test",
        "GOOGLE_OAUTH_CLIENT_ID": "google-client-id",
        "R2_ACCOUNT_ID": "account",
        "R2_ACCESS_KEY_ID": "key",
        "R2_SECRET_ACCESS_KEY": "secret",
        "R2_PUBLIC_BASE_URL": "https://media.mushukistan.uz",
    }
    values.update(overrides)
    return values


def test_missing_app_env_is_treated_as_production_and_fails_without_secrets(monkeypatch) -> None:
    monkeypatch.delenv("APP_ENV", raising=False)
    monkeypatch.delenv("JWT_SECRET_KEY", raising=False)
    with pytest.raises(ValidationError) as error:
        Settings(_env_file=None)
    assert "JWT_SECRET_KEY" in str(error.value)


def test_missing_app_env_never_enables_development_behaviour(monkeypatch) -> None:
    monkeypatch.delenv("APP_ENV", raising=False)
    values = production_values()
    values.pop("APP_ENV")
    settings = Settings(_env_file=None, **values)
    assert settings.app_env == "production"
    assert settings.is_production_like and not settings.allows_dev_diagnostics


@pytest.mark.parametrize(
    "value", ["prod", "dev", "devel", "local", "Production-1", "", "   ", "none", "0", "true"]
)
def test_invalid_app_env_values_fail_startup(value: str) -> None:
    with pytest.raises(ValidationError) as error:
        Settings(_env_file=None, APP_ENV=value)
    assert "APP_ENV" in str(error.value)


@pytest.mark.parametrize(
    ("value", "normalized"),
    [
        ("development", "development"),
        ("test", "test"),
        (" Development ", "development"),
        ("TEST", "test"),
    ],
)
def test_explicit_development_and_test_configuration_still_works(value, normalized) -> None:
    settings = Settings(_env_file=None, APP_ENV=value)
    assert settings.app_env == normalized
    assert settings.allows_dev_diagnostics and not settings.is_production_like


@pytest.mark.parametrize("value", ["production", "staging", " PRODUCTION "])
def test_production_like_environments_never_allow_dev_diagnostics(value) -> None:
    settings = Settings(_env_file=None, **production_values(APP_ENV=value))
    assert settings.is_production_like and not settings.allows_dev_diagnostics


@pytest.mark.parametrize(
    ("override", "fragment"),
    [
        ({"APP_DEBUG": "true"}, "APP_DEBUG"),
        ({"RATE_LIMIT_ENABLED": "false"}, "RATE_LIMIT_ENABLED"),
        ({"JWT_ALGORITHM": "none"}, "JWT_ALGORITHM"),
        ({"JWT_SECRET_KEY": "short"}, "JWT_SECRET_KEY"),
        ({"JWT_SECRET_KEY": "change-me"}, "JWT_SECRET_KEY"),
        ({"PUBLIC_APP_BASE_URL": ""}, "PUBLIC_APP_BASE_URL"),
        ({"RESEND_API_KEY": ""}, "RESEND_API_KEY"),
        ({"CORS_ALLOWED_ORIGINS": ""}, "CORS_ALLOWED_ORIGINS"),
    ],
)
def test_production_startup_fails_safely_on_insecure_settings(override, fragment) -> None:
    with pytest.raises(ValidationError) as error:
        Settings(_env_file=None, **production_values(**override))
    assert fragment in str(error.value)


def test_valid_production_configuration_starts() -> None:
    settings = Settings(_env_file=None, **production_values())
    assert settings.app_env == "production" and not settings.app_debug


# -------------------------------- F-12: verification tokens in registration responses


def build_auth_service(settings: Settings, monkeypatch) -> AuthService:
    monkeypatch.setattr(EmailVerificationSender, "send_verification_email", lambda *a, **k: None)
    return AuthService(
        settings=settings,
        db_session_manager=InMemorySessionManager(),  # type: ignore[arg-type]
        password_hasher=PasslibPasswordHasher(),
        access_token_service=JoseAccessTokenService(settings),
        google_token_verifier=StubGoogleVerifier(),  # type: ignore[arg-type]
        repository_factory=lambda _: InMemoryAuthUserRepository(),
    )


def register_over_http(service: AuthService) -> dict:
    app.dependency_overrides[get_auth_service] = lambda: service
    try:
        with TestClient(app, raise_server_exceptions=False) as client:
            response = client.post(
                "/api/v1/auth/register",
                json={
                    "email": f"{uuid4().hex}@example.com",
                    "password": "StrongPass123",
                    "name": "Registrant",
                    "accept_terms": True,
                    "accept_privacy": True,
                },
            )
            assert response.status_code in (200, 201), response.text
            resend = client.post(
                "/api/v1/auth/resend-verification",
                json={"email": response.json()["data"]["email"]},
            )
            return {"register": response.json()["data"], "resend": resend.json()}
    finally:
        app.dependency_overrides.clear()


@pytest.mark.parametrize("environment", ["development", "test"])
def test_explicit_development_returns_a_verification_token(environment, monkeypatch) -> None:
    settings = Settings(_env_file=None, APP_ENV=environment, JWT_SECRET_KEY=SECRET)
    body = register_over_http(build_auth_service(settings, monkeypatch))
    assert body["register"]["dev_verification_token"]


@pytest.mark.parametrize("environment", ["production", "staging"])
def test_production_never_returns_a_verification_token(environment, monkeypatch) -> None:
    settings = Settings(_env_file=None, **production_values(APP_ENV=environment))
    body = register_over_http(build_auth_service(settings, monkeypatch))
    assert body["register"]["verification_required"] is True
    assert "dev_verification_token" not in body["register"]
    assert "dev_verification_token" not in str(body["resend"])


def test_production_service_level_registration_has_no_token(monkeypatch) -> None:
    settings = Settings(_env_file=None, **production_values())
    service = build_auth_service(settings, monkeypatch)
    result = service.register(
        "someone@example.com", "StrongPass123", "Someone", accept_terms=True, accept_privacy=True
    )
    assert result.verification_required is True and result.dev_verification_token is None


def test_production_attempts_email_delivery_instead_of_skipping_it() -> None:
    """Development skips delivery; a production-like sender must enforce its configuration."""
    development = Settings(_env_file=None, APP_ENV="development")
    assert (
        EmailVerificationSender(development).send_verification_email(
            email="a@example.com", token="t"
        )
        is None
    )
    unconfigured = Settings.model_construct(  # bypass validation to reach the sender's own guard
        app_env="production", resend_api_key="", resend_from_email="", public_app_base_url=""
    )
    with pytest.raises(HTTPException) as error:
        EmailVerificationSender(unconfigured).send_verification_email(
            email="a@example.com", token="t"
        )
    assert error.value.detail["error"]["code"] == "EMAIL_NOT_CONFIGURED"
