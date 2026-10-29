from __future__ import annotations

import hashlib
import hmac
from typing import Protocol
from uuid import UUID

from structlog import get_logger

from app.core.security import api_error
from app.features.adoption_posts.domain.repositories import AdoptionPostRepository
from app.features.auth.domain.models import AuthUser
from app.features.lost_pets.domain.repositories import LostPetRepository
from app.features.posts.application.service import PostsService
from app.features.posts.domain.repositories import PostRepository
from app.features.views.application.schemas import PostViewResponse
from app.features.views.domain.repositories import PostViewRepository
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)


class PostViewRepositoryFactory(Protocol):
    def __call__(self, session) -> PostViewRepository: ...


class PostRepositoryFactory(Protocol):
    def __call__(self, session) -> PostRepository: ...


class LostPetRepositoryFactory(Protocol):
    def __call__(self, session) -> LostPetRepository: ...


class AdoptionPostRepositoryFactory(Protocol):
    def __call__(self, session) -> AdoptionPostRepository: ...


class ViewsService:
    """Counts each person once per post when they open it (see docs/ADRS.md, post views).

    Signed-in viewers are keyed by account. Guests send a random per-install id; only a keyed
    hash of it is stored. Authors opening their own post and guests without an id are not counted.
    """

    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: PostViewRepositoryFactory,
        post_repository_factory: PostRepositoryFactory,
        lost_pet_repository_factory: LostPetRepositoryFactory,
        adoption_post_repository_factory: AdoptionPostRepositoryFactory,
        guest_key_secret: str,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.post_repository_factory = post_repository_factory
        self.lost_pet_repository_factory = lost_pet_repository_factory
        self.adoption_post_repository_factory = adoption_post_repository_factory
        self.guest_key_secret = guest_key_secret.encode()

    def record_post_view(
        self, post_id: UUID, user: AuthUser | None, guest_id: UUID | None
    ) -> PostViewResponse:
        with self.db_session_manager.session_scope() as session:
            post = self.post_repository_factory(session).get_by_id(
                post_id,
                include_deleted=False,
                viewer_user_id=user.id if user is not None else None,
                respect_blocks=True,
            )
            if post is None or not PostsService._can_view_post(post, user):
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")
            return self._record(
                session, "post", post_id, post.user_id, post.view_count, user, guest_id
            )

    def record_lost_pet_view(
        self, lost_pet_id: UUID, user: AuthUser | None, guest_id: UUID | None
    ) -> PostViewResponse:
        with self.db_session_manager.session_scope() as session:
            item = self.lost_pet_repository_factory(session).get_by_id(
                lost_pet_id,
                viewer_user_id=user.id if user is not None else None,
                respect_blocks=True,
            )
            if item is None:
                raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")
            return self._record(
                session, "lost_pet", lost_pet_id, item.user_id, item.view_count, user, guest_id
            )

    def record_adoption_post_view(
        self, adoption_post_id: UUID, user: AuthUser | None, guest_id: UUID | None
    ) -> PostViewResponse:
        with self.db_session_manager.session_scope() as session:
            item = self.adoption_post_repository_factory(session).get_by_id(
                adoption_post_id,
                viewer_user_id=user.id if user is not None else None,
                respect_blocks=True,
            )
            if item is None:
                raise api_error(404, "ADOPTION_POST_NOT_FOUND", "Adoption post not found.")
            return self._record(
                session, "adoption", adoption_post_id, item.user_id, item.view_count, user, guest_id
            )

    def _record(
        self,
        session,
        post_kind: str,
        post_id: UUID,
        owner_id: UUID | None,
        view_count: int,
        user: AuthUser | None,
        guest_id: UUID | None,
    ) -> PostViewResponse:
        if user is not None and user.id == owner_id:
            return PostViewResponse(view_count=view_count, counted=False)
        if user is None and guest_id is None:
            return PostViewResponse(view_count=view_count, counted=False)

        repository = self.repository_factory(session)
        created = repository.record(
            post_kind,
            post_id,
            user_id=user.id if user is not None else None,
            guest_key=self.guest_key(guest_id) if user is None else None,
        )
        if not created:
            return PostViewResponse(view_count=view_count, counted=False)
        new_count = repository.increment_view_count(post_kind, post_id)
        logger.info("post_viewed", post_kind=post_kind, post_id=str(post_id))
        return PostViewResponse(view_count=new_count, counted=True)

    def guest_key(self, guest_id: UUID) -> str:
        """Keyed hash of a guest's install id; the id itself is never stored."""
        return hmac.new(
            self.guest_key_secret, b"post-view-guest:" + guest_id.bytes, hashlib.sha256
        ).hexdigest()
