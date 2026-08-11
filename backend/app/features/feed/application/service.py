from __future__ import annotations

from typing import Protocol

from app.core.security import api_error
from app.features.adoption_posts.application.schemas import AdoptionPostListItem
from app.features.adoption_posts.domain.repositories import AdoptionPostRepository
from app.features.auth.domain.models import AuthUser
from app.features.feed.application.schemas import FeedListItem, FeedQuery
from app.features.feed.domain.models import FeedFilter
from app.features.feed.domain.repositories import FeedRepository
from app.features.lost_pets.application.schemas import LostPetListItem
from app.features.lost_pets.domain.repositories import LostPetRepository
from app.features.posts.application.schemas import (
    GenericListResponse,
    PostListItem,
)
from app.infrastructure.db.session import DatabaseSessionManager


class FeedRepositoryFactory(Protocol):
    def __call__(self, session) -> FeedRepository: ...


class LostPetRepositoryFactory(Protocol):
    def __call__(self, session) -> LostPetRepository: ...


class AdoptionPostRepositoryFactory(Protocol):
    def __call__(self, session) -> AdoptionPostRepository: ...


class FeedService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: FeedRepositoryFactory,
        lost_pet_repository_factory: LostPetRepositoryFactory,
        adoption_post_repository_factory: AdoptionPostRepositoryFactory,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.lost_pet_repository_factory = lost_pet_repository_factory
        self.adoption_post_repository_factory = adoption_post_repository_factory

    def list_feed(
        self,
        query: FeedQuery,
        *,
        current_user: AuthUser | None = None,
    ) -> GenericListResponse[FeedListItem]:
        with self.db_session_manager.session_scope() as session:
            if query.filter_by == FeedFilter.ADOPTION:
                adoption_repository = self.adoption_post_repository_factory(session)
                try:
                    adoption_page = adoption_repository.list_public(
                        limit=query.limit,
                        cursor=query.cursor,
                    )
                except ValueError as exc:
                    raise api_error(
                        422,
                        "VALIDATION_ERROR",
                        "Validation failed.",
                        details={"cursor": ["invalid"]},
                    ) from exc
                return GenericListResponse[FeedListItem](
                    items=[
                        AdoptionPostListItem.model_validate(item, from_attributes=True)
                        for item in adoption_page.items
                    ],
                    next_cursor=adoption_page.next_cursor,
                    limit=adoption_page.limit,
                )

            repository = self.repository_factory(session)
            viewer_user_id = current_user.id if current_user is not None else None
            viewer_is_moderator = bool(current_user is not None and current_user.is_moderator)
            try:
                post_page = repository.list_feed(
                    limit=query.limit,
                    cursor=query.cursor,
                    filter_by=query.filter_by.value,
                    popular_period=query.popular_period.value,
                    viewer_user_id=viewer_user_id,
                    viewer_is_moderator=viewer_is_moderator,
                    latitude=query.latitude,
                    longitude=query.longitude,
                    radius_meters=query.radius_meters,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            post_items: list[FeedListItem] = [
                PostListItem.model_validate(item, from_attributes=True) for item in post_page.items
            ]

            if query.cursor is not None or query.filter_by not in {
                FeedFilter.RECENT,
                FeedFilter.NEARBY,
            }:
                return GenericListResponse[FeedListItem](
                    items=post_items,
                    next_cursor=post_page.next_cursor,
                    limit=post_page.limit,
                )

            lost_pet_repository = self.lost_pet_repository_factory(session)
            lost_pet_page = lost_pet_repository.list_public(
                limit=query.limit,
                latitude=query.latitude if query.filter_by == FeedFilter.NEARBY else None,
                longitude=query.longitude if query.filter_by == FeedFilter.NEARBY else None,
                radius_meters=query.radius_meters if query.filter_by == FeedFilter.NEARBY else None,
            )
            lost_pet_items: list[FeedListItem] = [
                LostPetListItem.model_validate(item, from_attributes=True)
                for item in lost_pet_page.items
            ]
            adoption_repository = self.adoption_post_repository_factory(session)
            adoption_page = adoption_repository.list_public(limit=query.limit)
            adoption_items: list[FeedListItem] = [
                AdoptionPostListItem.model_validate(item, from_attributes=True)
                for item in adoption_page.items
            ]
            merged = sorted(
                [*post_items, *lost_pet_items, *adoption_items],
                key=lambda item: item.created_at,
                reverse=True,
            )[: query.limit]
            return GenericListResponse[FeedListItem](
                items=merged,
                next_cursor=post_page.next_cursor,
                limit=query.limit,
            )
