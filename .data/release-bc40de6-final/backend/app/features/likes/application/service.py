from __future__ import annotations

from typing import Protocol
from uuid import UUID

from structlog import get_logger

from app.core.security import api_error
from app.features.auth.domain.models import AuthUser
from app.features.likes.application.schemas import LikeResponse
from app.features.likes.domain.models import LikeResult
from app.features.likes.domain.repositories import LikeRepository
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)


class LikeRepositoryFactory(Protocol):
    def __call__(self, session) -> LikeRepository: ...


class LikesService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: LikeRepositoryFactory,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory

    def like_post(self, post_id: UUID, user: AuthUser) -> LikeResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            post = repository.lock_visible_post(post_id, viewer_user_id=user.id)
            if post is None or not self._can_view_post(post, user):
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")

            created = repository.create_like(post_id, user.id)
            if not created:
                raise api_error(409, "ALREADY_LIKED", "User already liked this post.")

            repository.increment_post_like_count(post_id)
            result = LikeResult(liked=True, like_count=post.like_count + 1)
            logger.info("post_liked", post_id=str(post_id), actor_id=str(user.id))
            return LikeResponse.model_validate(result, from_attributes=True)

    def unlike_post(self, post_id: UUID, user: AuthUser) -> None:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            post = repository.lock_visible_post(post_id, viewer_user_id=user.id)
            if post is None or not self._can_view_post(post, user):
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")

            removed = repository.delete_like(post_id, user.id)
            if not removed:
                return

            repository.decrement_post_like_count(post_id)
            logger.info("post_unliked", post_id=str(post_id), actor_id=str(user.id))

    @staticmethod
    def _can_view_post(post, current_user: AuthUser | None) -> bool:
        if current_user is not None and current_user.is_moderator:
            return True
        if current_user is not None and post.user_id == current_user.id:
            return True

        cat_visible = (
            post.cat.deleted_at is None and post.cat.is_active and post.cat.merged_into is None
        )
        return post.is_public and cat_visible
