from __future__ import annotations

from collections.abc import Generator

from fastapi import Depends, Header, Request
from sqlalchemy.orm import Session

from app.core.auth import AuthenticatedPrincipal
from app.core.container import AppContainer
from app.core.rbac import AuthorizationService, RoleBasedAuthorizationService
from app.core.security import api_error, get_bearer_token
from app.features.auth.application.service import AuthService
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.repositories import SqlAlchemyAuthUserRepository
from app.features.auth.infrastructure.tokens import (
    GoogleOAuthIdTokenVerifier,
    JoseAccessTokenService,
)
from app.features.users.application.service import UsersService
from app.features.users.infrastructure.repositories import SqlAlchemyUserProfileRepository


def get_container(request: Request) -> AppContainer:
    return request.app.state.container


def get_db_session(request: Request) -> Generator[Session]:
    container = get_container(request)
    db = container.db_session_manager.create_session()
    try:
        yield db
    finally:
        db.close()


def get_password_hasher() -> PasslibPasswordHasher:
    return PasslibPasswordHasher()


def get_access_token_service(request: Request) -> JoseAccessTokenService:
    return JoseAccessTokenService(get_container(request).settings)


def get_google_token_verifier(request: Request) -> GoogleOAuthIdTokenVerifier:
    return GoogleOAuthIdTokenVerifier(get_container(request).settings)


def get_authorization_service() -> AuthorizationService:
    return RoleBasedAuthorizationService()


def get_auth_service(request: Request) -> AuthService:
    container = get_container(request)
    return AuthService(
        settings=container.settings,
        db_session_manager=container.db_session_manager,
        password_hasher=get_password_hasher(),
        access_token_service=JoseAccessTokenService(container.settings),
        google_token_verifier=GoogleOAuthIdTokenVerifier(container.settings),
        repository_factory=SqlAlchemyAuthUserRepository,
    )


def get_users_service(request: Request) -> UsersService:
    container = get_container(request)
    return UsersService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyUserProfileRepository,
    )


def get_optional_bearer_token(authorization: str | None = Header(default=None)) -> str | None:
    if not authorization:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise api_error(
            401,
            "UNAUTHORIZED",
            "Missing or invalid Authorization header.",
        )
    return token


def get_current_principal(
    request: Request,
    token: str = Depends(get_bearer_token),
) -> AuthenticatedPrincipal:
    access_token_service = get_access_token_service(request)
    return access_token_service.decode_access_token(token)


def get_optional_current_principal(
    request: Request,
    authorization: str | None = Header(default=None),
) -> AuthenticatedPrincipal | None:
    token = get_optional_bearer_token(authorization)
    if token is None:
        return None
    return get_access_token_service(request).decode_access_token(token)


def get_current_user(
    request: Request,
    db: Session = Depends(get_db_session),
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
):
    repository = SqlAlchemyAuthUserRepository(db)
    user = repository.get_by_id(principal.user_id)
    if user is None:
        raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")
    if not user.is_active:
        raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")
    return user


def get_optional_current_user(
    request: Request,
    db: Session = Depends(get_db_session),
    authorization: str | None = Header(default=None),
):
    principal = get_optional_current_principal(request, authorization)
    if principal is None:
        return None
    repository = SqlAlchemyAuthUserRepository(db)
    user = repository.get_by_id(principal.user_id)
    if user is None:
        raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")
    if not user.is_active:
        raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")
    return user


def get_current_active_user(user=Depends(get_current_user)):
    return user


def require_moderator(user=Depends(get_current_user)) -> object:
    if not user.is_moderator:
        raise api_error(403, "FORBIDDEN", "You do not have permission to perform this action.")
    return user
