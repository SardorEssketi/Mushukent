from __future__ import annotations

from datetime import datetime
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.features.auth.domain.models import AuthRefreshSession, AuthUser
from app.features.auth.domain.repositories import AuthUserRepository
from app.infrastructure.db.models import schema


class SqlAlchemyAuthUserRepository(AuthUserRepository):
    def __init__(self, session: Session) -> None:
        self.session = session

    def get_by_id(self, user_id: UUID) -> AuthUser | None:
        model = self.session.get(schema.User, user_id)
        return self._to_domain(model) if model is not None else None

    def get_by_email(self, email: str) -> AuthUser | None:
        statement = select(schema.User).where(func.lower(schema.User.email) == email.casefold())
        model = self.session.scalar(statement)
        return self._to_domain(model) if model is not None else None

    def get_by_google_subject(self, subject: str) -> AuthUser | None:
        model = self.session.scalar(
            select(schema.User).where(schema.User.google_subject == subject)
        )
        return self._to_domain(model) if model is not None else None

    def get_by_id_for_update(self, user_id: UUID) -> AuthUser | None:
        model = self.session.scalar(
            select(schema.User).where(schema.User.id == user_id).with_for_update()
        )
        return self._to_domain(model) if model is not None else None

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
        model = schema.User(
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
        self.session.add(model)
        self.session.flush()
        self.session.refresh(model)
        return self._to_domain(model)

    def save(self, user: AuthUser) -> AuthUser:
        model = self.session.get(schema.User, user.id)
        if model is None:
            raise ValueError(f"User {user.id} no longer exists.")
        model.email = user.email
        model.password_hash = user.password_hash
        model.google_subject = user.google_subject
        model.legacy_google_unbound = user.legacy_google_unbound
        model.name = user.name
        model.avatar_url = user.avatar_url
        model.phone_number = user.phone_number
        model.telegram_username = user.telegram_username
        model.preferred_language = user.preferred_language
        model.allow_public_activity_view = user.allow_public_activity_view
        model.bio = user.bio
        model.accepted_terms_version = user.accepted_terms_version
        model.accepted_privacy_version = user.accepted_privacy_version
        model.accepted_legal_at = user.accepted_legal_at
        model.email_verified = user.email_verified
        model.is_active = user.is_active
        model.is_moderator = user.is_moderator
        model.last_login_at = user.last_login_at
        self.session.flush()
        self.session.refresh(model)
        return self._to_domain(model)

    def update_last_login_at(self, user_id: UUID, last_login_at: datetime) -> AuthUser | None:
        model = self.session.get(schema.User, user_id)
        if model is None:
            return None
        model.last_login_at = last_login_at
        self.session.flush()
        self.session.refresh(model)
        return self._to_domain(model)

    def mark_email_verified(self, user_id: UUID) -> AuthUser | None:
        model = self.session.get(schema.User, user_id)
        if model is None:
            return None
        model.email_verified = True
        self.session.flush()
        self.session.refresh(model)
        return self._to_domain(model)

    def create_refresh_session(
        self,
        *,
        user_id: UUID,
        token_hash: str,
        expires_at: datetime,
    ) -> AuthRefreshSession:
        model = schema.AuthRefreshSession(
            user_id=user_id,
            token_hash=token_hash,
            expires_at=expires_at,
        )
        self.session.add(model)
        self.session.flush()
        self.session.refresh(model)
        return self._refresh_to_domain(model)

    def get_refresh_session_by_hash(self, token_hash: str) -> AuthRefreshSession | None:
        model = self.session.scalar(
            select(schema.AuthRefreshSession).where(
                schema.AuthRefreshSession.token_hash == token_hash
            )
        )
        return self._refresh_to_domain(model) if model is not None else None

    def rotate_refresh_session(
        self,
        session_id: UUID,
        *,
        new_token_hash: str,
        expires_at: datetime,
        used_at: datetime,
    ) -> AuthRefreshSession | None:
        model = self.session.get(schema.AuthRefreshSession, session_id)
        if model is None:
            return None
        model.token_hash = new_token_hash
        model.expires_at = expires_at
        model.last_used_at = used_at
        self.session.flush()
        self.session.refresh(model)
        return self._refresh_to_domain(model)

    def revoke_refresh_session(self, token_hash: str, revoked_at: datetime) -> None:
        model = self.session.scalar(
            select(schema.AuthRefreshSession).where(
                schema.AuthRefreshSession.token_hash == token_hash
            )
        )
        if model is not None and model.revoked_at is None:
            model.revoked_at = revoked_at
            self.session.flush()

    def revoke_user_refresh_sessions(self, user_id: UUID, revoked_at: datetime) -> None:
        models = self.session.scalars(
            select(schema.AuthRefreshSession).where(
                schema.AuthRefreshSession.user_id == user_id,
                schema.AuthRefreshSession.revoked_at.is_(None),
            )
        ).all()
        for model in models:
            model.revoked_at = revoked_at
        if models:
            self.session.flush()

    @staticmethod
    def _to_domain(model: schema.User) -> AuthUser:
        return AuthUser(
            id=model.id,
            email=model.email,
            password_hash=model.password_hash,
            google_subject=model.google_subject,
            legacy_google_unbound=model.legacy_google_unbound,
            name=model.name,
            avatar_url=model.avatar_url,
            phone_number=model.phone_number,
            telegram_username=model.telegram_username,
            preferred_language=model.preferred_language,
            allow_public_activity_view=model.allow_public_activity_view,
            bio=model.bio,
            accepted_terms_version=model.accepted_terms_version,
            accepted_privacy_version=model.accepted_privacy_version,
            accepted_legal_at=model.accepted_legal_at,
            email_verified=model.email_verified,
            is_active=model.is_active,
            is_moderator=model.is_moderator,
            registered_at=model.registered_at,
            last_login_at=model.last_login_at,
        )

    @staticmethod
    def _refresh_to_domain(model: schema.AuthRefreshSession) -> AuthRefreshSession:
        return AuthRefreshSession(
            id=model.id,
            user_id=model.user_id,
            token_hash=model.token_hash,
            expires_at=model.expires_at,
            revoked_at=model.revoked_at,
            last_used_at=model.last_used_at,
            created_at=model.created_at,
        )
