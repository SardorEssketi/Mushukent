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
from app.features.views.application.schemas import (
    PostViewBatchItem,
    PostViewBatchResponse,
    PostViewResponse,
    PostViewTarget,
)
from app.features.views.domain.repositories import PostViewRepository
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)

NOT_FOUND = {
    "post": ("POST_NOT_FOUND", "Post not found."),
    "lost_pet": ("LOST_PET_NOT_FOUND", "Lost pet post not found."),
    "adoption": ("ADOPTION_POST_NOT_FOUND", "Adoption post not found."),
}


class PostViewRepositoryFactory(Protocol):
    def __call__(self, session) -> PostViewRepository: ...


class PostRepositoryFactory(Protocol):
    def __call__(self, session) -> PostRepository: ...


class LostPetRepositoryFactory(Protocol):
    def __call__(self, session) -> LostPetRepository: ...


class AdoptionPostRepositoryFactory(Protocol):
    def __call__(self, session) -> AdoptionPostRepository: ...


class ViewsService:
    """Counts each person once per post when they open it or see its feed card (ADR-0024).

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
        return self._record_one("post", post_id, user, guest_id)

    def record_lost_pet_view(
        self, lost_pet_id: UUID, user: AuthUser | None, guest_id: UUID | None
    ) -> PostViewResponse:
        return self._record_one("lost_pet", lost_pet_id, user, guest_id)

    def record_adoption_post_view(
        self, adoption_post_id: UUID, user: AuthUser | None, guest_id: UUID | None
    ) -> PostViewResponse:
        return self._record_one("adoption", adoption_post_id, user, guest_id)

    def record_seen(
        self, items: list[PostViewTarget], user: AuthUser | None, guest_id: UUID | None
    ) -> PostViewBatchResponse:
        """Records posts a viewer saw in a list (feed cards). Same rules as opening a post.

        Posts that are missing or hidden from this viewer are skipped instead of failing the
        whole batch, because a feed can go stale while the batch waits on the device.

        Visibility is checked first, without locks. The writes then run in (kind, id) order, so
        concurrent batches lock post rows in the same order (no deadlocks) and hold the locks
        only for the short write phase.
        """
        unique: dict[tuple[str, UUID], None] = dict.fromkeys((item.kind, item.id) for item in items)
        outcomes: dict[tuple[str, UUID], PostViewResponse] = {}
        with self.db_session_manager.session_scope() as session:
            targets = {}
            for kind, post_id in unique:
                target = self._visible_target(session, kind, post_id, user)
                if target is not None:
                    targets[(kind, post_id)] = target
            for kind, post_id in sorted(targets, key=lambda key: (key[0], str(key[1]))):
                owner_id, view_count = targets[(kind, post_id)]
                outcomes[(kind, post_id)] = self._record(
                    session, kind, post_id, owner_id, view_count, user, guest_id
                )
        return PostViewBatchResponse(
            items=[
                PostViewBatchItem(
                    kind=kind,
                    id=post_id,
                    view_count=outcomes[(kind, post_id)].view_count,
                    counted=outcomes[(kind, post_id)].counted,
                )
                for kind, post_id in unique
                if (kind, post_id) in outcomes
            ]
        )

    def _record_one(
        self, post_kind: str, post_id: UUID, user: AuthUser | None, guest_id: UUID | None
    ) -> PostViewResponse:
        with self.db_session_manager.session_scope() as session:
            target = self._visible_target(session, post_kind, post_id, user)
            if target is None:
                raise api_error(404, *NOT_FOUND[post_kind])
            owner_id, view_count = target
            return self._record(session, post_kind, post_id, owner_id, view_count, user, guest_id)

    def _visible_target(
        self, session, post_kind: str, post_id: UUID, user: AuthUser | None
    ) -> tuple[UUID | None, int] | None:
        """(author id, current view count) of a post this viewer may see, else None."""
        viewer_user_id = user.id if user is not None else None
        if post_kind == "post":
            post = self.post_repository_factory(session).get_by_id(
                post_id,
                include_deleted=False,
                viewer_user_id=viewer_user_id,
                respect_blocks=True,
            )
            if post is None or not PostsService._can_view_post(post, user):
                return None
            return post.user_id, post.view_count
        if post_kind == "lost_pet":
            item = self.lost_pet_repository_factory(session).get_by_id(
                post_id, viewer_user_id=viewer_user_id, respect_blocks=True
            )
        else:
            item = self.adoption_post_repository_factory(session).get_by_id(
                post_id, viewer_user_id=viewer_user_id, respect_blocks=True
            )
        if item is None:
            return None
        return item.user_id, item.view_count

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
