from __future__ import annotations

from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

from structlog import get_logger

from app.core.security import api_error
from app.features.auth.domain.models import AuthUser
from app.features.comments.application.schemas import (
    CommentCreate,
    CommentResponse,
    GenericListResponse,
    to_comment_page_response,
    to_comment_response,
)
from app.features.comments.domain.models import CommentOrder
from app.features.comments.domain.repositories import CommentCreateDraft, CommentRepository
from app.features.users.domain.repositories import UserProfileRepository
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)


class CommentRepositoryFactory(Protocol):
    def __call__(self, session) -> CommentRepository: ...


class UserProfileRepositoryFactory(Protocol):
    def __call__(self, session) -> UserProfileRepository: ...


class CommentsService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: CommentRepositoryFactory,
        user_repository_factory: UserProfileRepositoryFactory,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.user_repository_factory = user_repository_factory

    def create_comment(
        self,
        post_id: UUID,
        user: AuthUser,
        payload: CommentCreate,
    ) -> CommentResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            post = repository.lock_visible_post(post_id, viewer_user_id=user.id)
            if post is None or not self._can_view_post(post, user):
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")

            created = repository.create(
                CommentCreateDraft(
                    post_id=post_id,
                    lost_pet_id=None,
                    adoption_post_id=None,
                    user_id=user.id,
                    content=payload.content.strip(),
                )
            )
            repository.increment_post_comment_count(post_id)
            logger.info(
                "comment_created",
                post_id=str(post_id),
                comment_id=str(created.id),
                actor_id=str(user.id),
            )
            return to_comment_response(created)

    def create_lost_pet_comment(
        self,
        lost_pet_id: UUID,
        user: AuthUser,
        payload: CommentCreate,
    ) -> CommentResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            if not repository.lost_pet_exists(lost_pet_id):
                raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")

            created = repository.create(
                CommentCreateDraft(
                    post_id=None,
                    lost_pet_id=lost_pet_id,
                    adoption_post_id=None,
                    user_id=user.id,
                    content=payload.content.strip(),
                )
            )
            repository.increment_lost_pet_comment_count(lost_pet_id)
            logger.info(
                "lost_pet_comment_created",
                lost_pet_id=str(lost_pet_id),
                comment_id=str(created.id),
                actor_id=str(user.id),
            )
            return to_comment_response(created)

    def create_adoption_post_comment(
        self,
        adoption_post_id: UUID,
        user: AuthUser,
        payload: CommentCreate,
    ) -> CommentResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            if not repository.adoption_post_exists(adoption_post_id):
                raise api_error(404, "ADOPTION_POST_NOT_FOUND", "Adoption post not found.")

            created = repository.create(
                CommentCreateDraft(
                    post_id=None,
                    lost_pet_id=None,
                    adoption_post_id=adoption_post_id,
                    user_id=user.id,
                    content=payload.content.strip(),
                )
            )
            repository.increment_adoption_post_comment_count(adoption_post_id)
            logger.info(
                "adoption_post_comment_created",
                adoption_post_id=str(adoption_post_id),
                comment_id=str(created.id),
                actor_id=str(user.id),
            )
            return to_comment_response(created)

    def list_comments(
        self,
        post_id: UUID,
        *,
        current_user: AuthUser | None = None,
        limit: int = 20,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> GenericListResponse[CommentResponse]:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            viewer_id = current_user.id if current_user is not None else None
            post = repository.lock_visible_post(post_id, viewer_user_id=viewer_id)
            if post is None or not self._can_view_post(post, current_user):
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")

            try:
                page = repository.list_for_post(
                    post_id,
                    limit=limit,
                    cursor=cursor,
                    order=order,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_comment_page_response(page)

    def list_adoption_post_comments(
        self,
        adoption_post_id: UUID,
        *,
        current_user: AuthUser | None = None,
        limit: int = 20,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> GenericListResponse[CommentResponse]:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            if not repository.adoption_post_exists(adoption_post_id):
                raise api_error(404, "ADOPTION_POST_NOT_FOUND", "Adoption post not found.")

            try:
                page = repository.list_for_adoption_post(
                    adoption_post_id,
                    limit=limit,
                    cursor=cursor,
                    order=order,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_comment_page_response(page)

    def list_lost_pet_comments(
        self,
        lost_pet_id: UUID,
        *,
        current_user: AuthUser | None = None,
        limit: int = 20,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.ASC,
    ) -> GenericListResponse[CommentResponse]:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            if not repository.lost_pet_exists(lost_pet_id):
                raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")

            try:
                page = repository.list_for_lost_pet(
                    lost_pet_id,
                    limit=limit,
                    cursor=cursor,
                    order=order,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_comment_page_response(page)

    def list_comments_by_user(
        self,
        user_id: UUID,
        *,
        current_user: AuthUser | None = None,
        limit: int = 20,
        cursor: str | None = None,
        order: CommentOrder = CommentOrder.DESC,
    ) -> GenericListResponse[CommentResponse]:
        with self.db_session_manager.session_scope() as session:
            user_repository = self.user_repository_factory(session)
            target_user = user_repository.get_by_id(user_id)
            if target_user is None or not target_user.is_active:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")

            include_private = bool(
                current_user is not None
                and (current_user.is_moderator or current_user.id == user_id)
            )
            if not include_private and not target_user.allow_public_activity_view:
                raise api_error(
                    403,
                    "ACTIVITY_PRIVATE",
                    "This user does not allow public activity viewing.",
                )

            repository = self.repository_factory(session)
            try:
                page = repository.list_for_user(
                    user_id,
                    limit=limit,
                    cursor=cursor,
                    order=order,
                    include_private=include_private,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_comment_page_response(page)

    def delete_comment(self, comment_id: UUID, user: AuthUser) -> None:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(comment_id, include_deleted=True)
            if current is None:
                raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")

            if current.post_id is not None:
                post = repository.lock_visible_post(current.post_id, viewer_user_id=user.id)
                if post is None or not self._can_view_post(post, user):
                    raise api_error(404, "POST_NOT_FOUND", "Post not found.")
            elif current.lost_pet_id is not None and not repository.lost_pet_exists(
                current.lost_pet_id
            ):
                raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")
            elif current.adoption_post_id is not None and not repository.adoption_post_exists(
                current.adoption_post_id
            ):
                raise api_error(404, "ADOPTION_POST_NOT_FOUND", "Adoption post not found.")

            locked = repository.get_by_id(comment_id, include_deleted=True, for_update=True)
            if locked is None:
                raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")

            if locked.deleted_at is not None:
                if user.is_moderator or locked.user_id == user.id:
                    return
                raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")

            if not user.is_moderator and locked.user_id != user.id:
                raise api_error(
                    403,
                    "FORBIDDEN",
                    "You do not have permission to perform this action.",
                )

            deleted = repository.mark_deleted(comment_id, deleted_at=datetime.now(UTC))
            if not deleted:
                return

            if locked.post_id is not None:
                repository.decrement_post_comment_count(locked.post_id)
            elif locked.lost_pet_id is not None:
                repository.decrement_lost_pet_comment_count(locked.lost_pet_id)
            elif locked.adoption_post_id is not None:
                repository.decrement_adoption_post_comment_count(locked.adoption_post_id)
            logger.info(
                "comment_deleted",
                comment_id=str(comment_id),
                post_id=str(locked.post_id) if locked.post_id is not None else None,
                lost_pet_id=str(locked.lost_pet_id) if locked.lost_pet_id is not None else None,
                adoption_post_id=(
                    str(locked.adoption_post_id) if locked.adoption_post_id is not None else None
                ),
                actor_id=str(user.id),
                moderator=user.is_moderator,
            )

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
