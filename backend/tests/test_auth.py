from __future__ import annotations

from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
from dataclasses import replace
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from jose import jwt
from sqlalchemy import select

from app.api.v1.routes import auth as auth_routes
from app.core.auth import AuthenticatedPrincipal, GoogleIdTokenClaims, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.core.dependencies import get_auth_service, require_moderator
from app.core.security import api_error
from app.features.auth.application.schemas import CURRENT_PRIVACY_VERSION, CURRENT_TERMS_VERSION
from app.features.auth.application.service import AuthService
from app.features.auth.domain.models import AuthUser
from app.features.auth.infrastructure import tokens as token_module
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.repositories import SqlAlchemyAuthUserRepository
from app.features.auth.infrastructure.tokens import (
    GoogleOAuthIdTokenVerifier,
    JoseAccessTokenService,
    JoseAccountDeletionTokenService,
)
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.main import app


def _test_settings(monkeypatch: pytest.MonkeyPatch) -> Settings:
    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key")
    monkeypatch.setenv("JWT_ISSUER", "mushukistan-api")
    monkeypatch.setenv("JWT_AUDIENCE", "mushukistan-mobile")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "google-client-id")
    monkeypatch.setenv(
        "DATABASE_URL", "postgresql+psycopg://mushukistan:change_me@localhost:5432/mushukistan"
    )
    return Settings()


class StubGoogleVerifier:
    def verify(self, id_token: str) -> GoogleIdTokenClaims:
        if id_token not in {
            "google-id-token",
            "google-id-token-2",
            "google-upper-token",
            "google-external-token",
            "google-workspace-token",
            "google-unverified-token",
            "google-changed-email-token",
            "google-other-email-same-sub-token",
        }:
            raise api_error(401, "INVALID_GOOGLE_TOKEN", "Invalid Google token.")
        email = {
            "google-upper-token": "GOOGLE-USER@GMAIL.COM",
            "google-external-token": "google-user@example.com",
            "google-workspace-token": "workspace-user@workspace.example",
            "google-changed-email-token": "different-address@gmail.com",
            "google-other-email-same-sub-token": "other-user@gmail.com",
        }.get(id_token, "google-user@gmail.com")
        return GoogleIdTokenClaims(
            email=email,
            iss="accounts.google.com",
            aud="google-client-id",
            exp=datetime.now(UTC) + timedelta(minutes=5),
            sub={
                "google-id-token-2": "other-google-subject",
                "google-external-token": "external-google-subject",
                "google-changed-email-token": "external-google-subject",
                "google-workspace-token": "workspace-google-subject",
            }.get(id_token, "google-subject"),
            name="Google User",
            email_verified=id_token != "google-unverified-token",
            hosted_domain="workspace.example" if id_token == "google-workspace-token" else None,
            raw={"id_token": id_token},
        )


class InvalidGoogleVerifier:
    def verify(self, id_token: str) -> GoogleIdTokenClaims:
        raise HTTPException(status_code=401, detail="Invalid Google token.")


class InMemoryAuthUserRepository:
    def __init__(self) -> None:
        self.users_by_id: dict[UUID, AuthUser] = {}
        self.users_by_email: dict[str, AuthUser] = {}
        self.refresh_sessions: dict[UUID, SimpleNamespace] = {}

    def get_by_id(self, user_id: UUID) -> AuthUser | None:
        return self.users_by_id.get(user_id)

    def get_by_email(self, email: str) -> AuthUser | None:
        return self.users_by_email.get(email.casefold())

    def get_users_by_email(self, email: str) -> list[AuthUser]:
        normalized_email = email.strip().casefold()
        return [
            user
            for user in self.users_by_id.values()
            if user.email.strip().casefold() == normalized_email
        ]

    def get_by_google_subject(self, subject: str) -> AuthUser | None:
        return next((u for u in self.users_by_id.values() if u.google_subject == subject), None)

    def get_by_id_for_update(self, user_id: UUID) -> AuthUser | None:
        return self.get_by_id(user_id)

    def create(
        self,
        *,
        email: str,
        password_hash: str | None,
        google_subject: str | None = None,
        legacy_google_unbound: bool = False,
        name: str | None = None,
        preferred_language: str = "en",
        email_verified: bool = False,
        is_moderator: bool = False,
        accepted_terms_version: str | None = None,
        accepted_privacy_version: str | None = None,
        accepted_legal_at: datetime | None = None,
    ) -> AuthUser:
        user = AuthUser(
            id=uuid4(),
            email=email,
            password_hash=password_hash,
            google_subject=google_subject,
            legacy_google_unbound=legacy_google_unbound,
            name=name,
            preferred_language=preferred_language,
            email_verified=email_verified,
            is_moderator=is_moderator,
            accepted_terms_version=accepted_terms_version,
            accepted_privacy_version=accepted_privacy_version,
            accepted_legal_at=accepted_legal_at,
        )
        self.users_by_id[user.id] = user
        self.users_by_email[user.email.casefold()] = user
        return user

    def save(self, user: AuthUser) -> AuthUser:
        self.users_by_id[user.id] = user
        self.users_by_email[user.email.casefold()] = user
        return user

    def update_last_login_at(self, user_id: UUID, last_login_at: datetime) -> AuthUser | None:
        user = self.users_by_id.get(user_id)
        if user is None:
            return None
        user.last_login_at = last_login_at
        return user

    def mark_email_verified(self, user_id: UUID) -> AuthUser | None:
        user = self.users_by_id.get(user_id)
        if user is None:
            return None
        user.email_verified = True
        return user

    def create_refresh_session(
        self,
        *,
        user_id: UUID,
        token_hash: str,
        expires_at: datetime,
    ) -> SimpleNamespace:
        session = SimpleNamespace(
            id=uuid4(),
            user_id=user_id,
            token_hash=token_hash,
            expires_at=expires_at,
            revoked_at=None,
            last_used_at=None,
        )
        self.refresh_sessions[session.id] = session
        return session

    def get_refresh_session_by_hash(self, token_hash: str) -> SimpleNamespace | None:
        for session in self.refresh_sessions.values():
            if session.token_hash == token_hash:
                return session
        return None

    def rotate_refresh_session(
        self,
        session_id: UUID,
        *,
        new_token_hash: str,
        expires_at: datetime,
        used_at: datetime,
    ) -> SimpleNamespace | None:
        session = self.refresh_sessions.get(session_id)
        if session is None:
            return None
        session.token_hash = new_token_hash
        session.expires_at = expires_at
        session.last_used_at = used_at
        return session

    def revoke_refresh_session(self, token_hash: str, revoked_at: datetime) -> None:
        session = self.get_refresh_session_by_hash(token_hash)
        if session is not None:
            session.revoked_at = revoked_at

    def revoke_user_refresh_sessions(self, user_id: UUID, revoked_at: datetime) -> None:
        for session in self.refresh_sessions.values():
            if session.user_id == user_id:
                session.revoked_at = revoked_at


class InMemorySessionManager:
    @contextmanager
    def session_scope(self) -> Iterator[object]:
        yield object()


def _auth_service_with_repository(
    monkeypatch: pytest.MonkeyPatch,
    repository: InMemoryAuthUserRepository,
    *,
    google_verifier: object | None = None,
) -> AuthService:
    settings = _test_settings(monkeypatch)
    return AuthService(
        settings=settings,
        db_session_manager=InMemorySessionManager(),  # type: ignore[arg-type]
        password_hasher=PasslibPasswordHasher(),
        access_token_service=JoseAccessTokenService(settings),
        google_token_verifier=google_verifier or StubGoogleVerifier(),  # type: ignore[arg-type]
        repository_factory=lambda _: repository,
    )


def test_verified_google_email_auto_links_existing_password_account(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    password_hash = PasslibPasswordHasher().hash_password("Password123")
    existing = repository.create(
        email="google-user@gmail.com",
        password_hash=password_hash,
        name="Password User",
        email_verified=True,
    )
    service = _auth_service_with_repository(monkeypatch, repository)

    google_login = service.authenticate_with_google_id_token(
        "google-upper-token",
        accept_terms=True,
        accept_privacy=True,
    )
    password_login = service.authenticate_with_password("GOOGLE-USER@GMAIL.COM", "Password123")
    repeated_google_login = service.authenticate_with_google_id_token(
        "google-id-token",
        accept_terms=True,
        accept_privacy=True,
    )

    assert google_login.user.id == existing.id
    assert password_login.user.id == existing.id
    assert repeated_google_login.user.id == existing.id
    assert len(repository.users_by_id) == 1
    assert existing.google_subject == "google-subject"
    assert existing.password_hash == password_hash


def test_new_google_identity_reuses_the_same_user_on_repeated_login(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)

    first = service.authenticate_with_google_id_token(
        "google-id-token",
        accept_terms=True,
        accept_privacy=True,
    )
    second = service.authenticate_with_google_id_token("google-id-token")

    assert second.user.id == first.user.id
    assert len(repository.users_by_id) == 1
    assert first.user.email_verified is True
    assert first.user.password_hash is None


def test_known_google_subject_does_not_move_when_claim_email_matches_another_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    original = repository.create(
        email="google-user@gmail.com",
        password_hash=None,
        google_subject="google-subject",
        name="Google User",
        email_verified=True,
    )
    other = repository.create(
        email="other-user@gmail.com",
        password_hash=None,
        name="Other User",
        email_verified=True,
    )
    service = _auth_service_with_repository(monkeypatch, repository)

    result = service.authenticate_with_google_id_token(
        "google-other-email-same-sub-token",
        accept_terms=True,
        accept_privacy=True,
    )

    assert result.user.id == original.id
    assert original.email == "google-user@gmail.com"
    assert original.google_subject == "google-subject"
    assert other.email == "other-user@gmail.com"
    assert other.google_subject is None
    assert len(repository.users_by_id) == 2


def test_unverified_google_email_claim_is_rejected_without_creating_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_google_id_token(
            "google-unverified-token",
            accept_terms=True,
            accept_privacy=True,
        )

    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"
    assert repository.users_by_id == {}


def test_new_google_subject_cannot_replace_subject_already_on_email_match(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    existing = repository.create(
        email="google-user@gmail.com",
        password_hash=PasslibPasswordHasher().hash_password("Password123"),
        google_subject="google-subject",
        email_verified=True,
    )
    service = _auth_service_with_repository(monkeypatch, repository)

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_google_id_token(
            "google-id-token-2",
            accept_terms=True,
            accept_privacy=True,
        )

    assert excinfo.value.detail["error"]["code"] == "GOOGLE_IDENTITY_CONFLICT"
    assert existing.google_subject == "google-subject"
    assert len(repository.users_by_id) == 1


def test_google_email_match_to_inactive_account_is_rejected(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    existing = repository.create(
        email="google-user@gmail.com",
        password_hash=PasslibPasswordHasher().hash_password("Password123"),
        email_verified=True,
    )
    existing.is_active = False
    service = _auth_service_with_repository(monkeypatch, repository)

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_google_id_token(
            "google-id-token",
            accept_terms=True,
            accept_privacy=True,
        )

    assert excinfo.value.detail["error"]["code"] == "ACCOUNT_DISABLED"
    assert existing.google_subject is None
    assert len(repository.users_by_id) == 1


def test_legacy_normalized_email_duplicates_fail_closed_without_merging(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    first = repository.create(
        email="google-user@gmail.com",
        password_hash=PasslibPasswordHasher().hash_password("Password123"),
        name="First User",
        email_verified=True,
    )
    second = repository.create(
        email=" GOOGLE-USER@GMAIL.COM ",
        password_hash=PasslibPasswordHasher().hash_password("Password456"),
        name="Second User",
        email_verified=True,
    )
    service = _auth_service_with_repository(monkeypatch, repository)

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_google_id_token(
            "google-id-token",
            accept_terms=True,
            accept_privacy=True,
        )

    assert excinfo.value.detail["error"]["code"] == "GOOGLE_IDENTITY_CONFLICT"
    assert first.id != second.id
    assert first.google_subject is None
    assert second.google_subject is None
    assert len(repository.users_by_id) == 2

    with pytest.raises(HTTPException) as password_excinfo:
        service.authenticate_with_password("google-user@gmail.com", "Password123")

    assert password_excinfo.value.status_code == 401
    assert password_excinfo.value.detail["error"]["code"] == "INVALID_CREDENTIALS"
    assert password_excinfo.value.detail["error"]["message"] == "Invalid email or password."


@pytest.fixture()
def auth_runtime(monkeypatch: pytest.MonkeyPatch, db_session_manager: DatabaseSessionManager):
    settings = _test_settings(monkeypatch)
    auth_service = AuthService(
        settings=settings,
        db_session_manager=db_session_manager,
        password_hasher=PasslibPasswordHasher(),
        access_token_service=JoseAccessTokenService(settings),
        google_token_verifier=StubGoogleVerifier(),
        repository_factory=SqlAlchemyAuthUserRepository,
    )

    app.state.container = AppContainer(settings=settings, db_session_manager=db_session_manager)
    app.dependency_overrides[get_auth_service] = lambda: auth_service

    try:
        yield settings, auth_service
    finally:
        app.dependency_overrides.clear()


@pytest.fixture()
def client(auth_runtime):
    with TestClient(app) as test_client:
        yield test_client


def test_password_hasher_round_trip() -> None:
    hasher = PasslibPasswordHasher()
    hashed = hasher.hash_password("StrongPass123")

    assert hashed != "StrongPass123"
    assert hasher.verify_password("StrongPass123", hashed) is True
    assert hasher.verify_password("WrongPass123", hashed) is False


def test_access_token_round_trip(monkeypatch: pytest.MonkeyPatch) -> None:
    settings = _test_settings(monkeypatch)
    service = JoseAccessTokenService(settings)
    principal = AuthenticatedPrincipal(
        user_id=UUID("11111111-1111-4111-8111-111111111111"),
        role=Role.USER,
    )

    token = service.issue_access_token(principal)
    decoded = service.decode_access_token(token)

    assert decoded.user_id == principal.user_id
    assert decoded.role == Role.USER


def test_access_token_rejects_invalid_issuer_audience_or_type(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _test_settings(monkeypatch)
    service = JoseAccessTokenService(settings)
    now = datetime.now(UTC)
    base_claims = {
        "sub": "11111111-1111-4111-8111-111111111111",
        "role": "user",
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": int(now.timestamp()),
        "nbf": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=5)).timestamp()),
        "token_type": "access",
    }

    wrong_issuer = jwt.encode(
        {**base_claims, "iss": "wrong-issuer"},
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )
    wrong_audience = jwt.encode(
        {**base_claims, "aud": "wrong-audience"},
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )
    wrong_type = jwt.encode(
        {**base_claims, "token_type": "refresh"},
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )
    expired = jwt.encode(
        {**base_claims, "exp": int((now - timedelta(minutes=5)).timestamp())},
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )

    for token in (wrong_issuer, wrong_audience, wrong_type, expired):
        with pytest.raises(HTTPException) as excinfo:
            service.decode_access_token(token)
        assert excinfo.value.status_code == 401


def test_account_deletion_token_round_trip(monkeypatch: pytest.MonkeyPatch) -> None:
    settings = _test_settings(monkeypatch)
    service = JoseAccountDeletionTokenService(settings)
    user_id = UUID("11111111-1111-4111-8111-111111111111")

    token = service.issue_token(user_id=user_id, email="delete@example.com")
    claims = service.decode_token(token)

    assert claims.user_id == user_id
    assert claims.email == "delete@example.com"


def test_account_deletion_token_rejects_wrong_type_and_expired(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _test_settings(monkeypatch)
    service = JoseAccountDeletionTokenService(settings)
    now = datetime.now(UTC)
    base_claims = {
        "sub": "11111111-1111-4111-8111-111111111111",
        "email": "delete@example.com",
        "iss": settings.jwt_issuer,
        "aud": settings.jwt_audience,
        "iat": int(now.timestamp()),
        "nbf": int(now.timestamp()),
        "exp": int((now + timedelta(minutes=5)).timestamp()),
        "token_type": "account_deletion",
    }
    wrong_type = jwt.encode(
        {**base_claims, "token_type": "email_verification"},
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )
    expired = jwt.encode(
        {**base_claims, "exp": int((now - timedelta(minutes=5)).timestamp())},
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )

    for token in (wrong_type, expired):
        with pytest.raises(HTTPException) as excinfo:
            service.decode_token(token)
        assert excinfo.value.status_code == 401
        assert excinfo.value.detail["error"]["code"] == "INVALID_ACCOUNT_DELETION_TOKEN"


def test_settings_parse_multiple_google_oauth_client_ids(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "web-client-id, android-client-id")

    settings = Settings()

    assert settings.google_oauth_client_ids == ["web-client-id", "android-client-id"]


def test_google_verifier_accepts_any_configured_audience(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "web-client-id,android-client-id")
    settings = Settings()
    verifier = GoogleOAuthIdTokenVerifier(settings)

    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")
    monkeypatch.setattr(
        token_module.jwt,
        "decode",
        lambda *_, **__: {
            "iss": "https://accounts.google.com",
            "aud": "android-client-id",
            "iat": int(datetime.now(UTC).timestamp()),
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
            "email": "google-user@example.com",
            "sub": "google-subject",
            "name": "Google User",
            "email_verified": True,
            "hd": "example.com",
        },
    )

    claims = verifier.verify("google-id-token")

    assert claims.aud == "android-client-id"
    assert claims.email == "google-user@example.com"
    assert claims.hosted_domain == "example.com"


@pytest.mark.parametrize(
    ("email", "subject", "expected_code"),
    [
        (None, "google-subject", "GOOGLE_EMAIL_MISSING"),
        ("not-an-email", "google-subject", "INVALID_GOOGLE_TOKEN"),
        ("google-user@example.com", None, "INVALID_GOOGLE_TOKEN"),
    ],
)
def test_google_verifier_requires_email_and_stable_subject(
    monkeypatch: pytest.MonkeyPatch,
    email: str | None,
    subject: str | None,
    expected_code: str,
) -> None:
    verifier = GoogleOAuthIdTokenVerifier(_test_settings(monkeypatch))
    monkeypatch.setattr(
        token_module.jwt, "get_unverified_header", lambda _: {"alg": "RS256", "kid": "kid"}
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")
    monkeypatch.setattr(
        token_module.jwt,
        "decode",
        lambda *_, **__: {
            "iss": "https://accounts.google.com",
            "aud": "google-client-id",
            "iat": int(datetime.now(UTC).timestamp()),
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
            "email": email,
            "sub": subject,
            "email_verified": True,
        },
    )

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("google-id-token")
    assert excinfo.value.detail["error"]["code"] == expected_code


def test_google_verifier_rejects_unconfigured_audience(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "web-client-id,android-client-id")
    settings = Settings()
    verifier = GoogleOAuthIdTokenVerifier(settings)

    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")
    monkeypatch.setattr(
        token_module.jwt,
        "decode",
        lambda *_, **__: {
            "iss": "https://accounts.google.com",
            "aud": "other-client-id",
            "iat": int(datetime.now(UTC).timestamp()),
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
            "email": "google-user@example.com",
        },
    )

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("google-id-token")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"


def test_google_verifier_rejects_expired_token_even_when_decoder_is_stubbed(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    verifier = GoogleOAuthIdTokenVerifier(_test_settings(monkeypatch))
    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")
    monkeypatch.setattr(
        token_module.jwt,
        "decode",
        lambda *_, **__: {
            "iss": "https://accounts.google.com",
            "aud": "google-client-id",
            "iat": int((datetime.now(UTC) - timedelta(hours=2)).timestamp()),
            "exp": int((datetime.now(UTC) - timedelta(minutes=5)).timestamp()),
            "email": "google-user@gmail.com",
            "sub": "google-subject",
            "email_verified": True,
        },
    )

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("expired-google-token")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"


@pytest.mark.parametrize(("claim", "value"), [("exp", 10**1000), ("iat", float("nan"))])
def test_google_verifier_rejects_malformed_timestamp_claims(
    monkeypatch: pytest.MonkeyPatch,
    claim: str,
    value: int | float,
) -> None:
    verifier = GoogleOAuthIdTokenVerifier(_test_settings(monkeypatch))
    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")
    claims = {
        "iss": "https://accounts.google.com",
        "aud": "google-client-id",
        "iat": int(datetime.now(UTC).timestamp()),
        "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
        "email": "google-user@gmail.com",
        "sub": "google-subject",
        "email_verified": True,
    }
    claims[claim] = value
    monkeypatch.setattr(token_module.jwt, "decode", lambda *_, **__: claims)

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("malformed-timestamp-google-token")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"


@pytest.mark.parametrize(
    ("audience", "authorized_party"),
    [
        (["web-client-id", "android-client-id"], None),
        (["web-client-id", "android-client-id"], "unconfigured-client-id"),
    ],
)
def test_google_verifier_checks_authorized_party_for_multiple_audiences(
    monkeypatch: pytest.MonkeyPatch,
    audience: list[str],
    authorized_party: str | None,
) -> None:
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "web-client-id,android-client-id")
    verifier = GoogleOAuthIdTokenVerifier(Settings())
    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")
    monkeypatch.setattr(
        token_module.jwt,
        "decode",
        lambda *_, **__: {
            "iss": "https://accounts.google.com",
            "aud": audience,
            "azp": authorized_party,
            "iat": int(datetime.now(UTC).timestamp()),
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
            "email": "google-user@gmail.com",
            "sub": "google-subject",
            "email_verified": True,
        },
    )

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("multiple-audience-google-token")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"


def test_google_verifier_rejects_malformed_token(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _test_settings(monkeypatch)
    verifier = GoogleOAuthIdTokenVerifier(settings)

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("not-a-jwt")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"


def test_google_verifier_rejects_invalid_signature(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _test_settings(monkeypatch)
    verifier = GoogleOAuthIdTokenVerifier(settings)
    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")

    def reject_signature(*_, **__):
        raise token_module.JWTError("invalid signature")

    monkeypatch.setattr(token_module.jwt, "decode", reject_signature)

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("invalid-signature-token")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"


def test_google_verifier_returns_controlled_error_when_jwks_unavailable(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _test_settings(monkeypatch)
    verifier = GoogleOAuthIdTokenVerifier(settings)
    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )

    def unavailable(*_, **__):
        raise OSError("network unavailable")

    monkeypatch.setattr(token_module, "urlopen", unavailable)

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("google-id-token")

    assert excinfo.value.status_code == 503
    assert excinfo.value.detail["error"]["code"] == "GOOGLE_AUTH_UNAVAILABLE"


def test_google_verifier_rejects_unverified_email(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    settings = _test_settings(monkeypatch)
    verifier = GoogleOAuthIdTokenVerifier(settings)
    monkeypatch.setattr(
        token_module.jwt,
        "get_unverified_header",
        lambda _: {"alg": "RS256", "kid": "kid"},
    )
    monkeypatch.setattr(verifier, "_google_public_key", lambda _: "public-key")
    monkeypatch.setattr(
        token_module.jwt,
        "decode",
        lambda *_, **__: {
            "iss": "https://accounts.google.com",
            "aud": "google-client-id",
            "iat": int(datetime.now(UTC).timestamp()),
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
            "email": "unverified@example.com",
            "sub": "google-subject",
            "email_verified": False,
        },
    )

    with pytest.raises(HTTPException) as excinfo:
        verifier.verify("google-id-token")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_GOOGLE_TOKEN"


def test_google_service_rejects_new_user_without_legal_acceptance(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_google_id_token("google-id-token")

    assert excinfo.value.status_code == 422
    assert excinfo.value.detail["error"]["code"] == "LEGAL_ACCEPTANCE_REQUIRED"
    assert repository.get_by_email("google-user@gmail.com") is None


def test_google_service_creates_user_with_legal_acceptance(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)

    result = service.authenticate_with_google_id_token(
        "google-id-token",
        accept_terms=True,
        accept_privacy=True,
    )

    assert result.user.email == "google-user@gmail.com"
    assert result.user.email_verified is True
    assert result.user.password_hash is None
    assert result.user.accepted_terms_version == CURRENT_TERMS_VERSION
    assert result.user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
    assert result.user.accepted_legal_at is not None
    assert result.access_token
    assert result.refresh_token


def test_password_registration_requires_verification_then_allows_login(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)
    registration = service.register(
        "password-user@example.com",
        "StrongPass123",
        "Password User",
        accept_terms=True,
        accept_privacy=True,
    )

    assert registration.verification_required is True
    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_password("password-user@example.com", "StrongPass123")
    assert excinfo.value.detail["error"]["code"] == "EMAIL_NOT_VERIFIED"

    assert registration.dev_verification_token is not None
    service.verify_email(registration.dev_verification_token)
    password_login = service.authenticate_with_password(
        "PASSWORD-USER@example.com", "StrongPass123"
    )

    assert password_login.user.id == registration.user.id
    assert password_login.user.email_verified is True
    assert password_login.access_token
    assert password_login.refresh_token


def test_verified_password_account_and_google_login_use_the_same_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)
    registration = service.register(
        "google-user@gmail.com",
        "Password123",
        "Password User",
        accept_terms=True,
        accept_privacy=True,
    )
    assert registration.dev_verification_token is not None
    service.verify_email(registration.dev_verification_token)

    google_login = service.authenticate_with_google_id_token("google-id-token")
    password_login = service.authenticate_with_password("google-user@gmail.com", "Password123")
    repeated_google_login = service.authenticate_with_google_id_token("google-id-token")

    assert google_login.user.id == registration.user.id
    assert password_login.user.id == registration.user.id
    assert repeated_google_login.user.id == registration.user.id
    assert len(repository.users_by_id) == 1
    methods = service.get_sign_in_methods(registration.user.id)
    assert methods == {
        "has_password": True,
        "google_connected": True,
        "email_verified": True,
    }


def test_new_google_user_repeated_login_keeps_one_user(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)

    first = service.authenticate_with_google_id_token(
        "google-id-token",
        accept_terms=True,
        accept_privacy=True,
    )
    second = service.authenticate_with_google_id_token("google-id-token")

    assert first.user.id == second.user.id
    assert first.user.id == repository.get_by_google_subject("google-subject").id
    assert len(repository.users_by_id) == 1


def test_both_methods_refresh_and_logout_use_the_same_session_system(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)
    registered = service.register(
        "google-user@gmail.com",
        "Password123",
        "Test User",
        accept_terms=True,
        accept_privacy=True,
    )
    service.verify_email(registered.dev_verification_token)
    google_login = service.authenticate_with_google_id_token("google-id-token")
    password_login = service.authenticate_with_password("google-user@gmail.com", "Password123")

    google_refresh = service.refresh_session(google_login.refresh_token)
    password_refresh = service.refresh_session(password_login.refresh_token)
    assert google_refresh.user.id == password_login.user.id == google_login.user.id
    assert google_refresh.refresh_token == google_login.refresh_token
    assert password_refresh.refresh_token == password_login.refresh_token

    service.revoke_refresh_session(google_login.refresh_token, user_id=google_login.user.id)
    with pytest.raises(HTTPException) as excinfo:
        service.refresh_session(google_login.refresh_token)
    assert excinfo.value.detail["error"]["code"] == "INVALID_REFRESH_TOKEN"
    assert service.refresh_session(password_login.refresh_token).user.id == google_login.user.id

    service.revoke_refresh_session(None, user_id=google_login.user.id)
    with pytest.raises(HTTPException) as excinfo:
        service.refresh_session(password_login.refresh_token)
    assert excinfo.value.detail["error"]["code"] == "INVALID_REFRESH_TOKEN"


def test_google_unlink_endpoint_is_not_registered() -> None:
    auth_paths = {route.path for route in auth_routes.router.routes}

    assert "/auth/unlink-google" not in auth_paths


def test_refresh_session_renews_existing_token(monkeypatch: pytest.MonkeyPatch) -> None:
    repository = InMemoryAuthUserRepository()
    repository.create(
        email="refresh@example.com",
        password_hash=None,
        name="Refresh User",
        email_verified=True,
        accepted_terms_version=CURRENT_TERMS_VERSION,
        accepted_privacy_version=CURRENT_PRIVACY_VERSION,
        accepted_legal_at=datetime.now(UTC),
    )
    service = _auth_service_with_repository(monkeypatch, repository)
    issued = service.authenticate_with_google_id_token(
        "google-id-token",
        accept_terms=True,
        accept_privacy=True,
    )

    refreshed = service.refresh_session(issued.refresh_token)

    assert refreshed.user.email == "google-user@gmail.com"
    assert refreshed.access_token
    assert refreshed.refresh_token
    assert refreshed.refresh_token == issued.refresh_token


def test_refresh_session_rejects_revoked_token(monkeypatch: pytest.MonkeyPatch) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)
    issued = service.authenticate_with_google_id_token(
        "google-id-token",
        accept_terms=True,
        accept_privacy=True,
    )
    service.revoke_refresh_session(issued.refresh_token)

    with pytest.raises(HTTPException) as excinfo:
        service.refresh_session(issued.refresh_token)

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_REFRESH_TOKEN"


def test_google_service_existing_user_with_legal_acceptance_does_not_require_flags(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    existing = repository.create(
        email="google-user@gmail.com",
        password_hash=None,
        name="Existing User",
        legacy_google_unbound=True,
        email_verified=True,
        accepted_terms_version=CURRENT_TERMS_VERSION,
        accepted_privacy_version=CURRENT_PRIVACY_VERSION,
        accepted_legal_at=datetime.now(UTC),
    )
    service = _auth_service_with_repository(monkeypatch, repository)

    result = service.authenticate_with_google_id_token("google-id-token")

    assert result.user.id == existing.id
    assert result.user.email == "google-user@gmail.com"
    assert result.access_token


def test_google_service_existing_user_without_current_legal_acceptance_requires_flags(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    existing = repository.create(
        email="google-user@gmail.com",
        password_hash=None,
        name="Existing User",
        legacy_google_unbound=True,
        email_verified=True,
    )
    service = _auth_service_with_repository(monkeypatch, repository)

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_google_id_token("google-id-token")

    assert excinfo.value.status_code == 422
    assert excinfo.value.detail["error"]["code"] == "LEGAL_ACCEPTANCE_REQUIRED"

    result = service.authenticate_with_google_id_token(
        "google-id-token",
        accept_terms=True,
        accept_privacy=True,
    )

    assert result.user.id == existing.id
    assert result.user.accepted_terms_version == CURRENT_TERMS_VERSION
    assert result.user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
    assert result.user.accepted_legal_at is not None


def test_google_service_rejects_invalid_credential(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(
        monkeypatch,
        repository,
        google_verifier=InvalidGoogleVerifier(),
    )

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_google_id_token(
            "invalid-google-token",
            accept_terms=True,
            accept_privacy=True,
        )

    assert excinfo.value.status_code == 401
    assert repository.users_by_email == {}


def test_password_auth_still_requires_verified_email(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)

    registration = service.register(
        email="password-user@example.com",
        password="StrongPass123",
        name="Password User",
        accept_terms=True,
        accept_privacy=True,
    )

    assert registration.user.accepted_terms_version == CURRENT_TERMS_VERSION
    assert registration.user.accepted_privacy_version == CURRENT_PRIVACY_VERSION

    with pytest.raises(HTTPException) as excinfo:
        service.authenticate_with_password("password-user@example.com", "StrongPass123")

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "EMAIL_NOT_VERIFIED"


def test_email_verification_token_expiry_is_enforced(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    service = _auth_service_with_repository(monkeypatch, repository)
    user = repository.create(
        email="verify-expiry@example.com",
        password_hash=PasslibPasswordHasher().hash_password("StrongPass123"),
    )
    now = datetime.now(UTC)
    expired_token = jwt.encode(
        {
            "sub": str(user.id),
            "email": user.email,
            "iss": service.settings.jwt_issuer,
            "aud": service.settings.jwt_audience,
            "iat": int((now - timedelta(hours=2)).timestamp()),
            "nbf": int((now - timedelta(hours=2)).timestamp()),
            "exp": int((now - timedelta(hours=1)).timestamp()),
            "token_type": "email_verification",
        },
        service.settings.jwt_secret_key,
        algorithm=service.settings.jwt_algorithm,
    )

    with pytest.raises(HTTPException) as excinfo:
        service.verify_email(expired_token)

    assert excinfo.value.status_code == 401
    assert excinfo.value.detail["error"]["code"] == "INVALID_VERIFICATION_TOKEN"


def test_rbac_dependency_rejects_non_moderator() -> None:
    user = SimpleNamespace(is_moderator=False)

    with pytest.raises(HTTPException) as excinfo:
        require_moderator(user)

    assert excinfo.value.status_code == 403


def test_rbac_dependency_allows_moderator() -> None:
    user = SimpleNamespace(is_moderator=True)
    assert require_moderator(user) is user


def test_register_login_logout_flow(client: TestClient, auth_runtime) -> None:
    _, auth_service = auth_runtime
    email = "register-login@example.com"
    password = "StrongPass123"

    register_response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": password,
            "name": "Register User",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert register_response.status_code == 201
    register_payload = register_response.json()
    assert register_payload["success"] is True
    assert register_payload["data"]["email"] == email
    assert register_payload["data"]["verification_required"] is True
    assert register_payload["data"]["dev_verification_token"]

    duplicate_response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": password,
            "name": "Register User",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert duplicate_response.status_code == 201
    assert duplicate_response.json()["success"] is True
    assert duplicate_response.json()["data"]["email"] == email
    assert duplicate_response.json()["data"]["verification_required"] is True
    assert "dev_verification_token" not in duplicate_response.json()["data"]

    with auth_service.db_session_manager.session_scope() as session:
        count = session.scalar(select(schema.User).where(schema.User.email == email))
        assert count is not None

    login_response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
    )
    assert login_response.status_code == 401
    assert login_response.json()["error"]["code"] == "EMAIL_NOT_VERIFIED"

    verify_response = client.post(
        "/api/v1/auth/verify-email",
        json={"token": register_payload["data"]["dev_verification_token"]},
    )
    assert verify_response.status_code == 200
    assert verify_response.json()["data"]["verified"] is True
    replayed_verification = client.post(
        "/api/v1/auth/verify-email",
        json={"token": register_payload["data"]["dev_verification_token"]},
    )
    assert replayed_verification.status_code == 200
    assert replayed_verification.json()["data"]["verified"] is True

    login_response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
    )
    assert login_response.status_code == 200
    login_payload = login_response.json()
    assert login_payload["success"] is True
    assert login_payload["data"]["token_type"] == "Bearer"
    assert login_payload["data"]["expires_in"] == 3600
    assert login_payload["data"]["user"]["email"] == email

    invalid_login_response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": "WrongPass123"},
    )
    assert invalid_login_response.status_code == 401
    assert invalid_login_response.json()["error"]["code"] == "INVALID_CREDENTIALS"

    logout_response = client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {login_payload['data']['access_token']}"},
    )
    assert logout_response.status_code == 204


def test_logout_does_not_revoke_another_users_refresh_session(
    client: TestClient, auth_runtime
) -> None:
    _, auth_service = auth_runtime
    sessions = []
    for email in ("logout-owner@example.com", "other-owner@example.com"):
        registered = auth_service.register(
            email,
            "StrongPass123",
            "Session Owner",
            accept_terms=True,
            accept_privacy=True,
        )
        auth_service.verify_email(registered.dev_verification_token)
        response = client.post(
            "/api/v1/auth/login",
            json={"email": email, "password": "StrongPass123"},
        )
        assert response.status_code == 200
        sessions.append(response.json()["data"])

    first_logout = client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {sessions[0]['access_token']}"},
        json={"refresh_token": sessions[1]["refresh_token"]},
    )
    assert first_logout.status_code == 204
    other_refresh = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": sessions[1]["refresh_token"]}
    )
    assert other_refresh.status_code == 200

    own_logout = client.post(
        "/api/v1/auth/logout",
        headers={"Authorization": f"Bearer {sessions[1]['access_token']}"},
        json={"refresh_token": sessions[1]["refresh_token"]},
    )
    assert own_logout.status_code == 204
    revoked_refresh = client.post(
        "/api/v1/auth/refresh", json={"refresh_token": sessions[1]["refresh_token"]}
    )
    assert revoked_refresh.status_code == 401


def test_refresh_endpoint_renews_refresh_session_and_new_access_token_works(
    client: TestClient,
    auth_runtime,
) -> None:
    settings, _ = auth_runtime
    email = "refresh-rotation@example.com"
    password = "StrongPass123"

    register_response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": password,
            "name": "Refresh Rotation User",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert register_response.status_code == 201
    verification_token = register_response.json()["data"]["dev_verification_token"]

    verify_response = client.post(
        "/api/v1/auth/verify-email",
        json={"token": verification_token},
    )
    assert verify_response.status_code == 200

    login_response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
    )
    assert login_response.status_code == 200
    login_payload = login_response.json()["data"]
    assert login_payload["user"]["is_moderator"] is False
    user_id = login_payload["user"]["id"]
    old_refresh_token = login_payload["refresh_token"]
    now = datetime.now(UTC)
    expired_access_token = jwt.encode(
        {
            "sub": user_id,
            "role": "user",
            "iss": settings.jwt_issuer,
            "aud": settings.jwt_audience,
            "iat": int((now - timedelta(minutes=10)).timestamp()),
            "nbf": int((now - timedelta(minutes=10)).timestamp()),
            "exp": int((now - timedelta(minutes=5)).timestamp()),
            "token_type": "access",
        },
        settings.jwt_secret_key,
        algorithm=settings.jwt_algorithm,
    )

    expired_access_response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {expired_access_token}"},
    )
    assert expired_access_response.status_code == 401

    refresh_response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": old_refresh_token},
    )
    assert refresh_response.status_code == 200
    refresh_payload = refresh_response.json()["data"]
    assert refresh_payload["access_token"]
    assert refresh_payload["access_token"] != expired_access_token
    assert refresh_payload["refresh_token"]
    assert refresh_payload["refresh_token"] == old_refresh_token
    assert refresh_payload["user"]["email"] == email

    old_refresh_response = client.post(
        "/api/v1/auth/refresh",
        json={"refresh_token": old_refresh_token},
    )
    assert old_refresh_response.status_code == 200

    protected_response = client.get(
        "/api/v1/users/me",
        headers={"Authorization": f"Bearer {refresh_payload['access_token']}"},
    )
    assert protected_response.status_code == 200
    protected_payload = protected_response.json()
    assert protected_payload["success"] is True
    assert protected_payload["data"]["email"] == email


def test_register_requires_name(client: TestClient) -> None:
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "missing-name@example.com",
            "password": "StrongPass123",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )

    assert response.status_code == 422
    payload = response.json()
    assert payload["success"] is False
    assert payload["error"]["code"] == "VALIDATION_ERROR"

    blank_response = client.post(
        "/api/v1/auth/register",
        json={
            "email": "blank-name@example.com",
            "password": "StrongPass123",
            "name": "   ",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )

    assert blank_response.status_code == 422
    assert blank_response.json()["error"]["code"] == "VALIDATION_ERROR"


def test_google_login_creates_or_updates_user(client: TestClient, auth_runtime) -> None:
    _, auth_service = auth_runtime
    response = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "google-id-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["success"] is True
    assert payload["data"]["user"]["email"] == "google-user@gmail.com"
    assert payload["data"]["user"]["name"] == "Google User"
    assert payload["data"]["user"]["email"] is not None
    assert payload["data"]["refresh_token"]

    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(
            select(schema.User).where(schema.User.email == "google-user@gmail.com")
        )
        assert user is not None
        assert user.email_verified is True
        assert user.password_hash is None
        assert user.accepted_terms_version == CURRENT_TERMS_VERSION
        assert user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
        assert user.accepted_legal_at is not None


def test_repeated_google_login_uses_the_existing_user_and_session_model(
    client: TestClient, auth_runtime
) -> None:
    _, auth_service = auth_runtime
    first = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "google-id-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    second = client.post("/api/v1/auth/google", json={"id_token": "google-id-token"})

    assert first.status_code == 200
    assert second.status_code == 200
    assert second.json()["data"]["user"]["id"] == first.json()["data"]["user"]["id"]
    assert second.json()["data"]["access_token"]
    assert second.json()["data"]["refresh_token"]
    with auth_service.db_session_manager.session_scope() as session:
        assert len(session.scalars(select(schema.User)).all()) == 1
        assert len(session.scalars(select(schema.AuthRefreshSession)).all()) == 2


def test_google_only_account_has_no_unlink_operation(client: TestClient, auth_runtime) -> None:
    _, auth_service = auth_runtime
    login = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "google-id-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    headers = {"Authorization": f"Bearer {login.json()['data']['access_token']}"}

    response = client.post("/api/v1/auth/unlink-google", headers=headers)
    methods = client.get("/api/v1/auth/methods", headers=headers)

    assert response.status_code == 404
    assert methods.json()["data"] == {
        "has_password": False,
        "google_connected": True,
        "email_verified": True,
    }
    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(select(schema.User))
        assert user is not None and user.google_subject == "google-subject"


def test_concurrent_first_google_logins_converge_on_one_user(auth_runtime) -> None:
    _, auth_service = auth_runtime
    from threading import Barrier

    barrier = Barrier(2)

    class RacingRepository(SqlAlchemyAuthUserRepository):
        def get_users_by_email(self, email):
            users = super().get_users_by_email(email)
            if not users:
                barrier.wait(timeout=10)
            return users

    auth_service.repository_factory = RacingRepository

    def authenticate() -> str:
        result = auth_service.authenticate_with_google_id_token(
            "google-id-token",
            accept_terms=True,
            accept_privacy=True,
        )
        return str(result.user.id)

    with ThreadPoolExecutor(max_workers=2) as executor:
        user_ids = list(executor.map(lambda _: authenticate(), range(2)))

    assert user_ids[0] == user_ids[1]
    with auth_service.db_session_manager.session_scope() as session:
        assert len(session.scalars(select(schema.User)).all()) == 1
        assert len(session.scalars(select(schema.AuthRefreshSession)).all()) == 2


def test_password_account_google_login_links_same_verified_gmail_account(
    client: TestClient, auth_runtime
) -> None:
    _, auth_service = auth_runtime
    registered = auth_service.register(
        "google-user@gmail.com",
        "Password123",
        "Password User",
        accept_terms=True,
        accept_privacy=True,
    )
    auth_service.verify_email(registered.dev_verification_token)
    google_attempt = client.post("/api/v1/auth/google", json={"id_token": "google-upper-token"})
    assert google_attempt.status_code == 200
    user_id = google_attempt.json()["data"]["user"]["id"]
    password_login = client.post(
        "/api/v1/auth/login", json={"email": "GOOGLE-USER@GMAIL.COM", "password": "Password123"}
    )
    assert password_login.status_code == 200
    assert password_login.json()["data"]["user"]["id"] == user_id
    assert (
        client.post("/api/v1/auth/google", json={"id_token": "google-id-token"}).json()["data"][
            "user"
        ]["id"]
        == user_id
    )
    conflicting = client.post("/api/v1/auth/google", json={"id_token": "google-id-token-2"})
    assert conflicting.status_code == 409
    assert conflicting.json()["error"]["code"] == "GOOGLE_IDENTITY_CONFLICT"
    with auth_service.db_session_manager.session_scope() as session:
        assert len(session.scalars(select(schema.User)).all()) == 1


def test_simultaneous_google_link_for_two_subjects_keeps_only_one_identity(
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    registered = auth_service.register(
        "google-user@gmail.com",
        "Password123",
        "Password User",
        accept_terms=True,
        accept_privacy=True,
    )
    auth_service.verify_email(registered.dev_verification_token)

    def authenticate(token: str) -> str:
        try:
            result = auth_service.authenticate_with_google_id_token(
                token,
                accept_terms=True,
                accept_privacy=True,
            )
            return f"success:{result.user.id}"
        except HTTPException as exc:
            return f"error:{exc.detail['error']['code']}"

    with ThreadPoolExecutor(max_workers=2) as executor:
        outcomes = list(executor.map(authenticate, ["google-id-token", "google-id-token-2"]))

    assert sum(outcome.startswith("success:") for outcome in outcomes) == 1
    assert outcomes.count("error:GOOGLE_IDENTITY_CONFLICT") == 1
    with auth_service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User)).all()
        assert len(users) == 1
        assert users[0].id == registered.user.id
        assert users[0].google_subject in {"google-subject", "other-google-subject"}


def test_unverified_google_identity_is_rejected_before_account_link_or_creation(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    response = client.post(
        "/api/v1/auth/google",
        json={"id_token": "google-unverified-token"},
    )

    assert response.status_code == 401
    with auth_service.db_session_manager.session_scope() as session:
        assert session.scalar(select(schema.User)) is None


def test_google_subject_remains_authoritative_when_claim_email_matches_another_user(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    first = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "google-id-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert first.status_code == 200
    first_id = first.json()["data"]["user"]["id"]

    other = auth_service.register(
        "other-user@gmail.com",
        "OtherPassword123",
        "Other User",
        accept_terms=True,
        accept_privacy=True,
    )
    auth_service.verify_email(other.dev_verification_token)

    login = client.post(
        "/api/v1/auth/google",
        json={"id_token": "google-other-email-same-sub-token"},
    )

    assert login.status_code == 200
    assert login.json()["data"]["user"]["id"] == first_id
    with auth_service.db_session_manager.session_scope() as session:
        first_user = session.scalar(select(schema.User).where(schema.User.id == UUID(first_id)))
        other_user = session.scalar(select(schema.User).where(schema.User.id == other.user.id))
        assert first_user is not None
        assert first_user.email == "google-user@gmail.com"
        assert first_user.google_subject == "google-subject"
        assert other_user is not None
        assert other_user.email == "other-user@gmail.com"
        assert other_user.google_subject is None


def test_google_login_refuses_inactive_account_matched_by_email(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        repository = SqlAlchemyAuthUserRepository(session)
        user = repository.create(
            email="google-user@gmail.com",
            password_hash=PasslibPasswordHasher().hash_password("Password123"),
            name="Inactive User",
            email_verified=True,
        )
        user.is_active = False
        repository.save(user)
        user_id = user.id

    response = client.post("/api/v1/auth/google", json={"id_token": "google-id-token"})

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "ACCOUNT_DISABLED"
    with auth_service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User)).all()
        assert len(users) == 1
        assert users[0].id == user_id
        assert users[0].google_subject is None


def test_external_google_email_does_not_prove_current_mailbox_ownership(
    client: TestClient, auth_runtime
) -> None:
    _, auth_service = auth_runtime
    response = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "google-external-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert response.status_code == 200
    user_id = response.json()["data"]["user"]["id"]
    assert response.json()["data"]["user"]["email"] == "google-user@example.com"

    repeated = client.post("/api/v1/auth/google", json={"id_token": "google-external-token"})

    assert repeated.status_code == 200
    assert repeated.json()["data"]["user"]["id"] == user_id
    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(select(schema.User).where(schema.User.id == UUID(user_id)))
        assert user is not None
        assert user.email_verified is False
        assert user.google_subject == "external-google-subject"


def test_linked_google_subject_keeps_mushukistan_email_when_provider_email_changes(
    client: TestClient, auth_runtime
) -> None:
    _, auth_service = auth_runtime
    created = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "google-external-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert created.status_code == 200
    user_id = UUID(created.json()["data"]["user"]["id"])

    changed_claim = client.post(
        "/api/v1/auth/google", json={"id_token": "google-changed-email-token"}
    )

    assert changed_claim.status_code == 200
    assert changed_claim.json()["data"]["user"]["id"] == str(user_id)
    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(select(schema.User).where(schema.User.id == user_id))
        assert user is not None
        assert user.email == "google-user@example.com"
        assert user.email_verified is False


def test_google_login_rejects_new_user_without_legal_acceptance(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    response = client.post(
        "/api/v1/auth/google",
        json={"id_token": "google-id-token"},
    )

    assert response.status_code == 422
    payload = response.json()
    assert payload["error"]["code"] == "LEGAL_ACCEPTANCE_REQUIRED"

    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(
            select(schema.User).where(schema.User.email == "google-user@gmail.com")
        )
        assert user is None


def test_google_failure_log_excludes_credentials(
    client: TestClient, auth_runtime, monkeypatch: pytest.MonkeyPatch
) -> None:
    records: list[tuple[str, dict[str, object]]] = []

    class RecordingLogger:
        def info(self, event: str, **fields: object) -> None:
            records.append((event, fields))

    monkeypatch.setattr(auth_routes, "logger", RecordingLogger())
    response = client.post("/api/v1/auth/google", json={"id_token": "google-id-token"})
    assert response.status_code == 422
    assert records == [
        (
            "google_auth_rejected",
            {
                "provider": "google",
                "status_code": 422,
                "error_code": "LEGAL_ACCEPTANCE_REQUIRED",
            },
        )
    ]
    assert "google-id-token" not in str(records)


def test_google_login_existing_user_with_legal_acceptance_does_not_require_flags(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        repository = SqlAlchemyAuthUserRepository(session)
        legacy = repository.create(
            email="google-user@gmail.com",
            password_hash=None,
            name="Existing Google User",
            legacy_google_unbound=True,
            email_verified=True,
            is_moderator=False,
            accepted_terms_version=CURRENT_TERMS_VERSION,
            accepted_privacy_version=CURRENT_PRIVACY_VERSION,
            accepted_legal_at=datetime.now(UTC),
        )
        legacy_id = legacy.id

    response = client.post(
        "/api/v1/auth/google",
        json={"id_token": "google-id-token"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["success"] is True
    assert payload["data"]["user"]["email"] == "google-user@gmail.com"
    assert payload["data"]["user"]["id"] == str(legacy_id)
    with auth_service.db_session_manager.session_scope() as session:
        saved = session.scalar(select(schema.User).where(schema.User.id == legacy_id))
        assert saved.name == "Existing Google User"
        assert saved.google_subject == "google-subject"
        assert len(session.scalars(select(schema.User)).all()) == 1


def test_unbound_external_legacy_account_requires_support(client: TestClient, auth_runtime) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        user = SqlAlchemyAuthUserRepository(session).create(
            email="google-user@example.com",
            password_hash=None,
            name="Legacy Google User",
            email_verified=True,
            is_moderator=True,
            accepted_terms_version=CURRENT_TERMS_VERSION,
            accepted_privacy_version=CURRENT_PRIVACY_VERSION,
            accepted_legal_at=datetime.now(UTC),
        )
        user_id = user.id

    linked = client.post("/api/v1/auth/google", json={"id_token": "google-external-token"})
    assert linked.status_code == 409
    assert linked.json()["error"]["code"] == "GOOGLE_IDENTITY_CONFLICT"
    with auth_service.db_session_manager.session_scope() as session:
        saved = session.scalar(select(schema.User).where(schema.User.id == user_id))
        assert saved.google_subject is None
        assert saved.email_verified is True
        assert len(session.scalars(select(schema.User)).all()) == 1


def test_duplicate_concurrent_google_link_requests_are_idempotent(
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        user = SqlAlchemyAuthUserRepository(session).create(
            email="google-user@gmail.com",
            password_hash=PasslibPasswordHasher().hash_password("Password123"),
            name="Password User",
            email_verified=True,
            accepted_terms_version=CURRENT_TERMS_VERSION,
            accepted_privacy_version=CURRENT_PRIVACY_VERSION,
            accepted_legal_at=datetime.now(UTC),
        )
        user_id = user.id

    def connect() -> UUID:
        return auth_service.authenticate_with_google_id_token("google-id-token").user.id

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _: connect(), range(2)))

    assert results == [user_id, user_id]
    with auth_service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User)).all()
        assert len(users) == 1
        assert users[0].google_subject == "google-subject"


def test_google_login_existing_user_without_current_legal_acceptance_requires_flags(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        repository = SqlAlchemyAuthUserRepository(session)
        repository.create(
            email="google-user@gmail.com",
            password_hash=None,
            name="Existing Google User",
            legacy_google_unbound=True,
            email_verified=True,
            is_moderator=False,
        )

    rejected = client.post(
        "/api/v1/auth/google",
        json={"id_token": "google-id-token"},
    )
    assert rejected.status_code == 422
    assert rejected.json()["error"]["code"] == "LEGAL_ACCEPTANCE_REQUIRED"

    accepted = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "google-id-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert accepted.status_code == 200

    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(
            select(schema.User).where(schema.User.email == "google-user@gmail.com")
        )
        assert user is not None
        assert user.accepted_terms_version == CURRENT_TERMS_VERSION
        assert user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
        assert user.accepted_legal_at is not None


def test_google_login_rejects_invalid_token(client: TestClient, auth_runtime) -> None:
    response = client.post(
        "/api/v1/auth/google",
        json={
            "id_token": "invalid-google-token",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )

    assert response.status_code == 401


def test_resend_verification_returns_dev_token_for_unverified_user(
    client: TestClient, auth_runtime
) -> None:
    _, auth_service = auth_runtime
    email = "resend@example.com"
    password = "StrongPass123"

    auth_service.register(
        email=email,
        password=password,
        name="Resend User",
        accept_terms=True,
        accept_privacy=True,
    )

    response = client.post(
        "/api/v1/auth/resend-verification",
        json={"email": email},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["success"] is True
    assert payload["data"]["email"] == email
    assert payload["data"]["dev_verification_token"]


def test_login_rejects_inactive_user(client: TestClient, auth_runtime) -> None:
    _, auth_service = auth_runtime
    email = "inactive@example.com"
    password = "StrongPass123"

    with auth_service.db_session_manager.session_scope() as session:
        repository = SqlAlchemyAuthUserRepository(session)
        user = repository.create(
            email=email,
            password_hash=PasslibPasswordHasher().hash_password(password),
            name="Inactive User",
            is_moderator=False,
        )
        user.is_active = False
        repository.save(user)

    response = client.post(
        "/api/v1/auth/login",
        json={"email": email, "password": password},
    )
    assert response.status_code == 403
    assert response.json()["error"]["code"] == "ACCOUNT_DISABLED"


def test_google_subject_on_deactivated_user_cannot_create_or_sign_into_another_user(
    client: TestClient, auth_runtime
) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        repository = SqlAlchemyAuthUserRepository(session)
        user = repository.create(
            email="google-user@gmail.com",
            password_hash=None,
            google_subject="google-subject",
            name="Deleted User",
            email_verified=True,
        )
        user.is_active = False
        repository.save(user)
        user_id = user.id

    response = client.post("/api/v1/auth/google", json={"id_token": "google-id-token"})

    assert response.status_code == 403
    assert response.json()["error"]["code"] == "ACCOUNT_DISABLED"
    with auth_service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User)).all()
        assert len(users) == 1
        assert users[0].id == user_id
        assert users[0].google_subject == "google-subject"


def test_duplicate_registration_is_generic_and_does_not_create_another_user(auth_runtime) -> None:
    _, auth_service = auth_runtime
    email = "rollback@example.com"
    password = "StrongPass123"

    auth_service.register(
        email=email,
        password=password,
        name="Rollback User",
        accept_terms=True,
        accept_privacy=True,
    )

    duplicate = auth_service.register(
        email=email,
        password=password,
        name="Rollback User",
        accept_terms=True,
        accept_privacy=True,
    )

    assert duplicate.user is None
    assert duplicate.email == email
    assert duplicate.verification_required is True
    assert duplicate.dev_verification_token is None

    with auth_service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User).where(schema.User.email == email)).all()
        assert len(users) == 1


def test_email_normalization_is_case_insensitive_without_gmail_dot_rewrites(
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    first = auth_service.register(
        "First.Last@Example.com",
        "StrongPass123",
        "First User",
        accept_terms=True,
        accept_privacy=True,
    )
    assert first.user.email == "first.last@example.com"

    duplicate = auth_service.register(
        "first.last@example.com",
        "StrongPass123",
        "Duplicate User",
        accept_terms=True,
        accept_privacy=True,
    )
    assert duplicate.user is None
    assert duplicate.email == "first.last@example.com"

    distinct = auth_service.register(
        "firstlast@example.com",
        "StrongPass123",
        "Distinct User",
        accept_terms=True,
        accept_privacy=True,
    )
    assert distinct.user.email == "firstlast@example.com"


@pytest.mark.parametrize(
    ("email", "token"),
    [
        ("workspace-user@workspace.example", "google-workspace-token"),
        ("google-user@example.com", "google-external-token"),
    ],
)
def test_google_collision_requires_password_and_preserves_account(
    client, auth_runtime, email, token
):
    _, service = auth_runtime
    registered = service.register(
        email, "Original123", "Original Name", accept_terms=True, accept_privacy=True
    )
    service.verify_email(registered.dev_verification_token)
    payload = {"id_token": token}
    required = client.post("/api/v1/auth/google", json=payload)
    assert required.status_code == 409
    assert required.json()["error"]["code"] == "GOOGLE_PASSWORD_REQUIRED"
    wrong = client.post("/api/v1/auth/google", json={**payload, "password": "Wrong1234"})
    assert wrong.status_code == 401
    with service.db_session_manager.session_scope() as session:
        saved = session.get(schema.User, registered.user.id)
        original_hash = saved.password_hash
        accepted_at = saved.accepted_legal_at
        assert saved.google_subject is None
        assert session.scalars(select(schema.AuthRefreshSession)).all() == []
    confirmed = client.post("/api/v1/auth/google", json={**payload, "password": "Original123"})
    assert confirmed.status_code == 200
    assert confirmed.json()["data"]["user"]["id"] == str(registered.user.id)
    repeated = client.post("/api/v1/auth/google", json=payload)
    assert repeated.status_code == 200
    assert repeated.json()["data"]["user"]["id"] == str(registered.user.id)
    password_login = service.authenticate_with_password(email, "Original123")
    assert password_login.user.id == registered.user.id
    with service.db_session_manager.session_scope() as session:
        saved = session.get(schema.User, registered.user.id)
        assert saved.password_hash == original_hash
        assert saved.name == "Original Name"
        assert saved.accepted_legal_at == accepted_at
        assert len(session.scalars(select(schema.User)).all()) == 1


@pytest.mark.parametrize(
    ("email", "token"),
    [
        ("google-user@gmail.com", "google-id-token"),
        ("workspace-user@workspace.example", "google-workspace-token"),
        ("google-user@example.com", "google-external-token"),
    ],
)
def test_pending_password_account_is_never_claimed_by_google(client, auth_runtime, email, token):
    _, service = auth_runtime
    registered = service.register(
        email, "Original123", "Pending User", accept_terms=True, accept_privacy=True
    )
    for password in (None, "Wrong1234", "Original123"):
        payload = {"id_token": token, "accept_terms": True, "accept_privacy": True}
        if password is not None:
            payload["password"] = password
        response = client.post("/api/v1/auth/google", json=payload)
        assert response.status_code == 409
        assert response.json()["error"]["code"] == "GOOGLE_ACCOUNT_UNVERIFIED"
    with service.db_session_manager.session_scope() as session:
        saved = session.get(schema.User, registered.user.id)
        assert saved.google_subject is None
        assert saved.email_verified is False
        assert saved.name == "Pending User"
        assert service.password_hasher.verify_password("Original123", saved.password_hash)
        assert len(session.scalars(select(schema.User)).all()) == 1
        assert session.scalars(select(schema.AuthRefreshSession)).all() == []
    assert (
        client.post(
            "/api/v1/auth/login",
            json={
                "email": email,
                "password": "Original123",
            },
        ).json()["error"]["code"]
        == "EMAIL_NOT_VERIFIED"
    )
    service.verify_email(registered.dev_verification_token)
    result = service.authenticate_with_google_id_token(token, password="Original123")
    assert result.user.id == registered.user.id


def test_removed_credential_management_endpoints_do_not_mutate_google_account(client, auth_runtime):
    _, service = auth_runtime
    login = service.authenticate_with_google_id_token(
        "google-id-token", accept_terms=True, accept_privacy=True
    )
    headers = {"Authorization": f"Bearer {login.access_token}"}
    for path in ("set-password", "connect-google"):
        response = client.post(
            f"/api/v1/auth/{path}",
            headers=headers,
            json={
                "new_password": "Password123",
                "confirm_password": "Password123",
                "id_token": "google-id-token",
            },
        )
        assert response.status_code == 404
    with service.db_session_manager.session_scope() as session:
        saved = session.get(schema.User, login.user.id)
        assert saved.password_hash is None
        assert saved.google_subject == "google-subject"


def test_change_password_requires_current_password_and_preserves_google(client, auth_runtime):
    _, service = auth_runtime
    registered = service.register(
        "google-user@gmail.com", "Original123", "User", accept_terms=True, accept_privacy=True
    )
    service.verify_email(registered.dev_verification_token)
    login = service.authenticate_with_google_id_token("google-id-token")
    headers = {"Authorization": f"Bearer {login.access_token}"}
    payload = {
        "current_password": "Wrong1234",
        "new_password": "Changed123",
        "confirm_password": "Changed123",
    }
    assert (
        client.post("/api/v1/auth/change-password", headers=headers, json=payload).status_code
        == 401
    )
    payload["current_password"] = "Original123"
    payload["confirm_password"] = "Mismatch123"
    assert (
        client.post("/api/v1/auth/change-password", headers=headers, json=payload).status_code
        == 422
    )
    payload["confirm_password"] = "Changed123"
    assert (
        client.post("/api/v1/auth/change-password", headers=headers, json=payload).status_code
        == 204
    )
    with pytest.raises(HTTPException):
        service.authenticate_with_password("google-user@gmail.com", "Original123")
    assert (
        service.authenticate_with_password("google-user@gmail.com", "Changed123").user.id
        == login.user.id
    )
    assert service.authenticate_with_google_id_token("google-id-token").user.id == login.user.id


def test_inactive_refresh_revocation_survives_reactivation(client, auth_runtime):
    _, service = auth_runtime
    login = service.authenticate_with_google_id_token(
        "google-id-token", accept_terms=True, accept_privacy=True
    )
    second = service.authenticate_with_google_id_token("google-id-token")
    with service.db_session_manager.session_scope() as session:
        session.get(schema.User, login.user.id).is_active = False
    assert (
        client.post("/api/v1/auth/refresh", json={"refresh_token": login.refresh_token}).status_code
        == 403
    )
    assert (
        client.get(
            "/api/v1/auth/methods",
            headers={
                "Authorization": f"Bearer {login.access_token}",
            },
        ).status_code
        == 403
    )
    with service.db_session_manager.session_scope() as session:
        assert all(row.revoked_at for row in session.scalars(select(schema.AuthRefreshSession)))
        session.get(schema.User, login.user.id).is_active = True
    for token in (login.refresh_token, second.refresh_token):
        assert client.post("/api/v1/auth/refresh", json={"refresh_token": token}).status_code == 401


@pytest.mark.parametrize("same_subject", [True, False])
def test_concurrent_password_confirmations_do_not_overwrite_subject(auth_runtime, same_subject):
    from threading import Barrier

    _, service = auth_runtime
    registered = service.register(
        "workspace-user@workspace.example",
        "Original123",
        "User",
        accept_terms=True,
        accept_privacy=True,
    )
    service.verify_email(registered.dev_verification_token)
    barrier = Barrier(2)

    class RacingRepository(SqlAlchemyAuthUserRepository):
        def get_users_by_email(self, email):
            users = super().get_users_by_email(email)
            barrier.wait(timeout=10)
            return users

    class Verifier(StubGoogleVerifier):
        def verify(self, token):
            claims = super().verify("google-workspace-token")
            if token == "second":
                claims = replace(claims, sub="second-subject")
            return claims

    service.repository_factory = RacingRepository
    service.google_token_verifier = Verifier()

    def login(token):
        try:
            return service.authenticate_with_google_id_token(token, password="Original123").user.id
        except HTTPException as error:
            return error.detail["error"]["code"]

    tokens = ["first", "first" if same_subject else "second"]
    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(login, tokens))
    assert results.count(registered.user.id) == (2 if same_subject else 1)
    if not same_subject:
        assert results.count("GOOGLE_IDENTITY_CONFLICT") == 1
    with service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User)).all()
        assert len(users) == 1
        assert users[0].id == registered.user.id
        assert users[0].google_subject in {"workspace-google-subject", "second-subject"}


def test_concurrent_normalized_password_registrations_create_one_account(auth_runtime):
    from threading import Barrier

    _, service = auth_runtime
    barrier = Barrier(2)

    class RacingRepository(SqlAlchemyAuthUserRepository):
        def get_users_by_email(self, email):
            users = super().get_users_by_email(email)
            if not users:
                barrier.wait(timeout=10)
            return users

    service.repository_factory = RacingRepository

    def register(email):
        return service.register(
            email, "Password123", "User", accept_terms=True, accept_privacy=True
        )

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(register, ["race@example.com", " RACE@EXAMPLE.COM "]))
    assert all(
        result.email == "race@example.com" and result.verification_required for result in results
    )
    assert sum(result.user is not None for result in results) == 1
    with service.db_session_manager.session_scope() as session:
        assert len(session.scalars(select(schema.User)).all()) == 1
        assert session.scalars(select(schema.AuthRefreshSession)).all() == []
