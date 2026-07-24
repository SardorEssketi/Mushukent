from __future__ import annotations

from typing import Protocol
from uuid import UUID

from app.core.security import api_error
from app.features.auth.domain.models import AuthUser
from app.features.users.application.schemas import UserProfile, UserPublic, UserUpdate
from app.features.users.domain.repositories import UserProfileRepository
from app.infrastructure.db.session import DatabaseSessionManager


class UserProfileRepositoryFactory(Protocol):
    def __call__(self, session) -> UserProfileRepository: ...


class UsersService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: UserProfileRepositoryFactory,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory

    def get_me(self, user: AuthUser) -> UserProfile:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            profile = repository.get_by_id(user.id)
            if profile is None or not profile.is_active:
                raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")

            return self._build_self_profile(repository, profile)

    def get_public_profile(self, user_id: UUID) -> UserPublic:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_id(user_id)
            if user is None or not user.is_active:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")

            observation_count = repository.count_observations(user.id)
            return UserPublic(
                id=user.id,
                name=user.name,
                avatar_url=user.avatar_url,
                registered_at=user.registered_at,
                observation_count=observation_count,
            )

    def update_me(self, user: AuthUser, payload: UserUpdate) -> UserProfile:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(user.id)
            if current is None or not current.is_active:
                raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")

            if payload.name is not None:
                current.name = payload.name.strip()
            if payload.bio is not None:
                current.bio = payload.bio.strip()
            if payload.avatar_url is not None:
                current.avatar_url = str(payload.avatar_url)

            updated = repository.save(current)
            return self._build_self_profile(repository, updated)

    def _build_self_profile(
        self,
        repository: UserProfileRepository,
        user: AuthUser,
    ) -> UserProfile:
        return UserProfile(
            id=user.id,
            email=user.email,
            name=user.name,
            avatar_url=user.avatar_url,
            bio=user.bio,
            registered_at=user.registered_at,
            observation_count=repository.count_observations(user.id),
            total_likes_received=repository.count_likes_received(user.id),
            comment_count=repository.count_comments(user.id),
        )
