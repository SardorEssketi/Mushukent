from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime
from typing import Protocol

from sqlalchemy.exc import IntegrityError
from structlog import get_logger

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
from app.features.auth.application.schemas import CURRENT_PRIVACY_VERSION, CURRENT_TERMS_VERSION
from app.features.auth.domain.models import AuthUser
from app.features.auth.domain.repositories import AuthUserRepository
from app.features.auth.infrastructure.email import EmailVerificationSender
from app.features.auth.infrastructure.tokens import JoseEmailVerificationTokenService
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)


class AuthRepositoryFactory(Protocol):
    def __call__(self, session) -> AuthUserRepository: ...


@dataclass(slots=True)
class AuthSessionResult:
    user: AuthUser
    access_token: str
    token_type: str = "Bearer"
    expires_in: int = 3600


@dataclass(slots=True)
class RegistrationResult:
    user: AuthUser
    verification_required: bool
    dev_verification_token: str | None = None


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
        self.email_verification_token_service = JoseEmailVerificationTokenService(settings)
        self.email_verification_sender = EmailVerificationSender(settings)
        self.google_token_verifier = google_token_verifier
        self.repository_factory = repository_factory

    def register(
        self,
        email: str,
        password: str,
        name: str,
        preferred_language: str = "en",
        accept_terms: bool = False,
        accept_privacy: bool = False,
    ) -> RegistrationResult:
        normalized_email = self._normalize_email(email)
        self._validate_password(password)
        normalized_name = self._validate_name(name)
        self._validate_preferred_language(preferred_language)
        self._validate_legal_acceptance(accept_terms=accept_terms, accept_privacy=accept_privacy)

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

                user = repository.create(
                    email=normalized_email,
                    password_hash=self.password_hasher.hash_password(password),
                    name=normalized_name,
                    preferred_language=preferred_language,
                    email_verified=False,
                    is_moderator=False,
                    accepted_terms_version=CURRENT_TERMS_VERSION,
                    accepted_privacy_version=CURRENT_PRIVACY_VERSION,
                    accepted_legal_at=datetime.now(UTC),
                )
                token = self.email_verification_token_service.issue_token(
                    user_id=user.id,
                    email=user.email,
                )
                self._emit_verification_link(user.email, token)
                return RegistrationResult(
                    user=user,
                    verification_required=True,
                    dev_verification_token=token if self._is_dev_verification_flow else None,
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
            if not user.email_verified:
                raise api_error(
                    401,
                    "EMAIL_NOT_VERIFIED",
                    "Please confirm your email before signing in.",
                )

            now = datetime.now(UTC)
            user = repository.update_last_login_at(user.id, now) or user
            principal = self._principal_from_user(user)

        access_token = self.access_token_service.issue_access_token(principal)
        return AuthSessionResult(
            user=user,
            access_token=access_token,
            expires_in=self.settings.jwt_access_token_exp_minutes * 60,
        )

    def resend_verification(self, email: str) -> str | None:
        normalized_email = self._normalize_email(email)
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_email(normalized_email)
            if user is None or user.email_verified or not user.is_active:
                return None
            token = self.email_verification_token_service.issue_token(
                user_id=user.id,
                email=user.email,
            )
            self._emit_verification_link(user.email, token)
            return token if self._is_dev_verification_flow else None

    def verify_email(self, token: str) -> AuthUser:
        claims = self.email_verification_token_service.decode_token(token)
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_id(claims.user_id)
            if user is None or not user.is_active:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")
            if user.email.casefold() != claims.email.casefold():
                raise api_error(
                    401,
                    "INVALID_VERIFICATION_TOKEN",
                    "Invalid or expired verification token.",
                )
            if user.email_verified:
                return user
            verified = repository.mark_email_verified(user.id)
            if verified is None:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")
            return verified

    def authenticate_with_google_id_token(
        self,
        id_token: str,
        *,
        accept_terms: bool = False,
        accept_privacy: bool = False,
    ) -> AuthSessionResult:
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
                self._validate_legal_acceptance(
                    accept_terms=accept_terms,
                    accept_privacy=accept_privacy,
                )
                user = repository.create(
                    email=normalized_email,
                    password_hash=None,
                    name=claims.name,
                    preferred_language="en",
                    email_verified=True,
                    is_moderator=False,
                    accepted_terms_version=CURRENT_TERMS_VERSION,
                    accepted_privacy_version=CURRENT_PRIVACY_VERSION,
                    accepted_legal_at=datetime.now(UTC),
                )
            else:
                if not self._has_current_legal_acceptance(user):
                    self._validate_legal_acceptance(
                        accept_terms=accept_terms,
                        accept_privacy=accept_privacy,
                    )
                    user.accepted_terms_version = CURRENT_TERMS_VERSION
                    user.accepted_privacy_version = CURRENT_PRIVACY_VERSION
                    user.accepted_legal_at = datetime.now(UTC)
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
            return AuthenticatedPrincipal(
                user_id=user.id,
                role=expected_role,
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
    def _validate_preferred_language(preferred_language: str) -> None:
        if preferred_language not in {"en", "uz", "ru"}:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"preferred_language": ["unsupported"]},
            )

    @staticmethod
    def _validate_name(name: str) -> str:
        normalized_name = name.strip()
        if not normalized_name:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"name": ["required"]},
            )
        if len(normalized_name) > 100:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"name": ["max_length_100"]},
            )
        return normalized_name

    @staticmethod
    def _validate_legal_acceptance(*, accept_terms: bool, accept_privacy: bool) -> None:
        if not accept_terms or not accept_privacy:
            raise api_error(
                422,
                "LEGAL_ACCEPTANCE_REQUIRED",
                "Terms of Service and Privacy Policy acceptance is required.",
                details={
                    "accept_terms": ["required_true"],
                    "accept_privacy": ["required_true"],
                },
            )

    @staticmethod
    def _has_current_legal_acceptance(user: AuthUser) -> bool:
        return (
            user.accepted_terms_version == CURRENT_TERMS_VERSION
            and user.accepted_privacy_version == CURRENT_PRIVACY_VERSION
            and user.accepted_legal_at is not None
        )

    @staticmethod
    def _principal_from_user(user: AuthUser) -> AuthenticatedPrincipal:
        return AuthenticatedPrincipal(
            user_id=user.id,
            role=Role.MODERATOR if user.is_moderator else Role.USER,
            is_active=user.is_active,
        )

    @property
    def _is_dev_verification_flow(self) -> bool:
        return self.settings.app_env.casefold() == "development"

    def _emit_verification_link(self, email: str, token: str) -> None:
        self.email_verification_sender.send_verification_email(email=email, token=token)
        logger.info(
            "email_verification_issued",
            email_domain=email.rsplit("@", 1)[-1],
            verification_token=token if self._is_dev_verification_flow else "<hidden>",
        )
