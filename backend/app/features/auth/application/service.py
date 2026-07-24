from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from sqlalchemy.exc import IntegrityError

from app.core.auth import (
    AccessTokenService,
    AuthenticatedPrincipal,
    AuthenticationService,
    GoogleIdTokenVerifier,
    PasswordHasher,
    Role,
)
from app.core.config import Settings
from app.core.security import api_error
from app.features.auth.domain.models import AuthUser
from app.features.auth.domain.repositories import AuthUserRepository
from app.infrastructure.db.session import DatabaseSessionManager


class AuthRepositoryFactory(Protocol):
    def __call__(self, session) -> AuthUserRepository: ...


@dataclass(slots=True)
class AuthSessionResult:
    user: AuthUser
    access_token: str
    token_type: str = "Bearer"
    expires_in: int = 3600


class AuthService(AuthenticationService):
    def __init__(
        self,
        *,
        settings: Settings,
        db_session_manager: DatabaseSessionManager,
        password_hasher: PasswordHasher,
        access_token_service: AccessTokenService,
        google_token_verifier: GoogleIdTokenVerifier,
        repository_factory: AuthRepositoryFactory,
    ) -> None:
        self.settings = settings
        self.db_session_manager = db_session_manager
        self.password_hasher = password_hasher
        self.access_token_service = access_token_service
        self.google_token_verifier = google_token_verifier
        self.repository_factory = repository_factory

    def register(self, email: str, password: str, name: str | None = None) -> AuthUser:
        normalized_email = self._normalize_email(email)
        self._validate_password(password)

        try:
            with self.db_session_manager.session_scope() as session:
                repository = self.repository_factory(session)
                existing = repository.get_by_email(normalized_email)
                if existing is not None:
                    raise api_error(
                        409,
                        "EMAIL_ALREADY_EXISTS",
                        "Email already registered.",
                    )

                return repository.create(
                    email=normalized_email,
                    password_hash=self.password_hasher.hash_password(password),
                    name=name,
                    email_verified=False,
                    is_moderator=False,
                )
        except IntegrityError as exc:
            raise api_error(
                409,
                "EMAIL_ALREADY_EXISTS",
                "Email already registered.",
            ) from exc

    def authenticate_with_password(self, email: str, password: str) -> AuthSessionResult:
        normalized_email = self._normalize_email(email)
        self._validate_password(password)

        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_email(normalized_email)
            if user is None or not user.password_hash:
                raise api_error(
                    401,
                    "INVALID_CREDENTIALS",
                    "Invalid email or password.",
                )
            if not self.password_hasher.verify_password(password, user.password_hash):
                raise api_error(
                    401,
                    "INVALID_CREDENTIALS",
                    "Invalid email or password.",
                )
            if not user.is_active:
                raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")

            now = datetime.now(UTC)
            user = repository.update_last_login_at(user.id, now) or user
            principal = self._principal_from_user(user)

        access_token = self.access_token_service.issue_access_token(principal)
        return AuthSessionResult(
            user=user,
            access_token=access_token,
            expires_in=self.settings.jwt_access_token_exp_minutes * 60,
        )

    def authenticate_with_google_id_token(self, id_token: str) -> AuthSessionResult:
        claims = self.google_token_verifier.verify(id_token)
        if not claims.email:
            raise api_error(400, "GOOGLE_EMAIL_MISSING", "Google token is missing an email claim.")

        normalized_email = self._normalize_email(claims.email)

        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_email(normalized_email)
            if user is not None and not user.is_active:
                raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")

            if user is None:
                user = repository.create(
                    email=normalized_email,
                    password_hash=None,
                    name=claims.name,
                    email_verified=True,
                    is_moderator=False,
                )
            else:
                user.email_verified = True
                if claims.name and not user.name:
                    user.name = claims.name
                user = repository.save(user)

            user = repository.update_last_login_at(user.id, datetime.now(UTC)) or user
            principal = self._principal_from_user(user)

        access_token = self.access_token_service.issue_access_token(principal)
        return AuthSessionResult(
            user=user,
            access_token=access_token,
            expires_in=self.settings.jwt_access_token_exp_minutes * 60,
        )

    def resolve_bearer_token(self, token: str) -> AuthenticatedPrincipal:
        principal = self.access_token_service.decode_access_token(token)

        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_id(principal.user_id)
            if user is None:
                raise api_error(
                    401,
                    "UNAUTHORIZED",
                    "Missing or invalid Authorization header.",
                )
            if not user.is_active:
                raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")

            expected_role = Role.MODERATOR if user.is_moderator else Role.USER
            if principal.role != expected_role:
                raise api_error(
                    401,
                    "UNAUTHORIZED",
                    "Missing or invalid Authorization header.",
                )
            if principal.email and principal.email.casefold() != user.email.casefold():
                raise api_error(
                    401,
                    "UNAUTHORIZED",
                    "Missing or invalid Authorization header.",
                )
            return AuthenticatedPrincipal(
                user_id=user.id,
                role=expected_role,
                email=user.email,
                is_active=user.is_active,
            )

    @staticmethod
    def _normalize_email(email: str) -> str:
        return email.strip().casefold()

    @staticmethod
    def _validate_password(password: str) -> None:
        if len(password) < 8 or len(password) > 128:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"password": ["length_must_be_between_8_and_128"]},
            )

    @staticmethod
    def _principal_from_user(user: AuthUser) -> AuthenticatedPrincipal:
        return AuthenticatedPrincipal(
            user_id=user.id,
            role=Role.MODERATOR if user.is_moderator else Role.USER,
            email=user.email,
            is_active=user.is_active,
        )
