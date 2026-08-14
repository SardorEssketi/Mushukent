from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from jose import jwt
from sqlalchemy import select

from app.core.auth import AuthenticatedPrincipal, GoogleIdTokenClaims, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.core.dependencies import get_auth_service, require_moderator
from app.features.auth.application.schemas import CURRENT_PRIVACY_VERSION, CURRENT_TERMS_VERSION
from app.features.auth.application.service import AuthService
from app.features.auth.domain.models import AuthUser
from app.features.auth.infrastructure import tokens as token_module
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.repositories import SqlAlchemyAuthUserRepository
from app.features.auth.infrastructure.tokens import (
    GoogleOAuthIdTokenVerifier,
    JoseAccessTokenService,
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
        if id_token != "google-id-token":
            raise HTTPException(status_code=401, detail="Invalid Google token.")
        return GoogleIdTokenClaims(
            email="google-user@example.com",
            iss="accounts.google.com",
            aud="google-client-id",
            exp=datetime.now(UTC) + timedelta(minutes=5),
            sub="google-subject",
            name="Google User",
            email_verified=True,
            raw={"id_token": id_token},
        )


class InvalidGoogleVerifier:
    def verify(self, id_token: str) -> GoogleIdTokenClaims:
        raise HTTPException(status_code=401, detail="Invalid Google token.")


class InMemoryAuthUserRepository:
    def __init__(self) -> None:
        self.users_by_id: dict[UUID, AuthUser] = {}
        self.users_by_email: dict[str, AuthUser] = {}

    def get_by_id(self, user_id: UUID) -> AuthUser | None:
        return self.users_by_id.get(user_id)

    def get_by_email(self, email: str) -> AuthUser | None:
        return self.users_by_email.get(email.casefold())

    def create(
        self,
        *,
        email: str,
        password_hash: str | None,
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
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
            "email": "google-user@example.com",
            "sub": "google-subject",
            "name": "Google User",
            "email_verified": True,
        },
    )

    claims = verifier.verify("google-id-token")

    assert claims.aud == "android-client-id"
    assert claims.email == "google-user@example.com"


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
            "exp": int((datetime.now(UTC) + timedelta(minutes=5)).timestamp()),
            "email": "google-user@example.com",
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
    assert repository.get_by_email("google-user@example.com") is None


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

    assert result.user.email == "google-user@example.com"
    assert result.user.email_verified is True
    assert result.user.password_hash is None
    assert result.user.accepted_terms_version == CURRENT_TERMS_VERSION
    assert result.user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
    assert result.user.accepted_legal_at is not None
    assert result.access_token


def test_google_service_existing_user_with_legal_acceptance_does_not_require_flags(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    existing = repository.create(
        email="google-user@example.com",
        password_hash=None,
        name="Existing User",
        email_verified=True,
        accepted_terms_version=CURRENT_TERMS_VERSION,
        accepted_privacy_version=CURRENT_PRIVACY_VERSION,
        accepted_legal_at=datetime.now(UTC),
    )
    service = _auth_service_with_repository(monkeypatch, repository)

    result = service.authenticate_with_google_id_token("google-id-token")

    assert result.user.id == existing.id
    assert result.user.email == "google-user@example.com"
    assert result.access_token


def test_google_service_existing_user_without_current_legal_acceptance_requires_flags(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    repository = InMemoryAuthUserRepository()
    existing = repository.create(
        email="google-user@example.com",
        password_hash=None,
        name="Existing User",
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
    assert duplicate_response.status_code == 409
    assert duplicate_response.json()["error"]["code"] == "EMAIL_ALREADY_EXISTS"

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
    assert payload["data"]["user"]["email"] == "google-user@example.com"
    assert payload["data"]["user"]["name"] == "Google User"
    assert payload["data"]["user"]["email"] is not None
    assert "refresh_token" not in payload["data"]

    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(
            select(schema.User).where(schema.User.email == "google-user@example.com")
        )
        assert user is not None
        assert user.email_verified is True
        assert user.password_hash is None
        assert user.accepted_terms_version == CURRENT_TERMS_VERSION
        assert user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
        assert user.accepted_legal_at is not None


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
            select(schema.User).where(schema.User.email == "google-user@example.com")
        )
        assert user is None


def test_google_login_existing_user_with_legal_acceptance_does_not_require_flags(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        repository = SqlAlchemyAuthUserRepository(session)
        repository.create(
            email="google-user@example.com",
            password_hash=None,
            name="Existing Google User",
            email_verified=True,
            is_moderator=False,
            accepted_terms_version=CURRENT_TERMS_VERSION,
            accepted_privacy_version=CURRENT_PRIVACY_VERSION,
            accepted_legal_at=datetime.now(UTC),
        )

    response = client.post(
        "/api/v1/auth/google",
        json={"id_token": "google-id-token"},
    )

    assert response.status_code == 200
    payload = response.json()
    assert payload["success"] is True
    assert payload["data"]["user"]["email"] == "google-user@example.com"


def test_google_login_existing_user_without_current_legal_acceptance_requires_flags(
    client: TestClient,
    auth_runtime,
) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        repository = SqlAlchemyAuthUserRepository(session)
        repository.create(
            email="google-user@example.com",
            password_hash=None,
            name="Existing Google User",
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
            select(schema.User).where(schema.User.email == "google-user@example.com")
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


def test_auth_service_rolls_back_on_duplicate_registration(auth_runtime) -> None:
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

    with pytest.raises(HTTPException) as excinfo:
        auth_service.register(
            email=email,
            password=password,
            name="Rollback User",
            accept_terms=True,
            accept_privacy=True,
        )

    assert excinfo.value.status_code == 409

    with auth_service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User).where(schema.User.email == email)).all()
        assert len(users) == 1
