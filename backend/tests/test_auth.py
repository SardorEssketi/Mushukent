from __future__ import annotations

from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from uuid import UUID

import pytest
from fastapi import HTTPException
from fastapi.testclient import TestClient
from jose import jwt
from sqlalchemy import select

from app.core.auth import AuthenticatedPrincipal, GoogleIdTokenClaims, Role
from app.core.config import Settings
from app.core.container import AppContainer
from app.core.dependencies import get_auth_service, require_moderator
from app.features.auth.application.service import AuthService
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.repositories import SqlAlchemyAuthUserRepository
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.main import app


def _test_settings(monkeypatch: pytest.MonkeyPatch) -> Settings:
    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key")
    monkeypatch.setenv("JWT_ISSUER", "mushukent-api")
    monkeypatch.setenv("JWT_AUDIENCE", "mushukent-mobile")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "google-client-id")
    monkeypatch.setenv(
        "DATABASE_URL", "postgresql+psycopg://mushukent:change_me@localhost:5432/mushukent"
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
        email="user@example.com",
    )

    token = service.issue_access_token(principal)
    decoded = service.decode_access_token(token)

    assert decoded.user_id == principal.user_id
    assert decoded.role == Role.USER
    assert decoded.email == principal.email


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
        json={"email": email, "password": password, "name": "Register User"},
    )
    assert register_response.status_code == 201
    register_payload = register_response.json()
    assert register_payload["success"] is True
    assert register_payload["data"]["email"] == email
    assert "refresh_token" not in register_payload["data"]

    duplicate_response = client.post(
        "/api/v1/auth/register",
        json={"email": email, "password": password, "name": "Register User"},
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


def test_google_login_creates_or_updates_user(client: TestClient, auth_runtime) -> None:
    _, auth_service = auth_runtime
    response = client.post("/api/v1/auth/google", json={"id_token": "google-id-token"})

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

    auth_service.register(email=email, password=password, name="Rollback User")

    with pytest.raises(HTTPException) as excinfo:
        auth_service.register(email=email, password=password, name="Rollback User")

    assert excinfo.value.status_code == 409

    with auth_service.db_session_manager.session_scope() as session:
        users = session.scalars(select(schema.User).where(schema.User.email == email)).all()
        assert len(users) == 1
