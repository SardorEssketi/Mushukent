from __future__ import annotations

import base64
import json
from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

from app.core.security import api_error
from app.features.adoption_posts.application.schemas import AdoptionPostListItem
from app.features.adoption_posts.domain.repositories import AdoptionPostRepository
from app.features.auth.domain.models import AuthUser
from app.features.feed.application.schemas import FeedListItem, FeedQuery
from app.features.feed.domain.models import (
    FeedCursorPosition,
    FeedFilter,
    FeedItemKey,
    FeedItemType,
)
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
            if query.filter_by in {FeedFilter.RECENT, FeedFilter.NEARBY}:
                try:
                    cursor = self._decode_mixed_cursor(query.cursor, query=query)
                    key_page = repository.list_mixed_feed_keys(
                        limit=query.limit,
                        cursor=cursor,
                        filter_by=query.filter_by.value,
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

                post_ids = [
                    item.item_id
                    for item in key_page.items
                    if item.item_type == FeedItemType.OBSERVATION
                ]
                lost_pet_ids = [
                    item.item_id
                    for item in key_page.items
                    if item.item_type == FeedItemType.LOST_PET
                ]
                adoption_ids = [
                    item.item_id
                    for item in key_page.items
                    if item.item_type == FeedItemType.ADOPTION
                ]

                posts = repository.get_feed_posts_by_ids(
                    post_ids,
                    viewer_user_id=viewer_user_id,
                    viewer_is_moderator=viewer_is_moderator,
                )
                lost_pets = self.lost_pet_repository_factory(session).get_by_ids(lost_pet_ids)
                adoption_posts = self.adoption_post_repository_factory(session).get_by_ids(
                    adoption_ids
                )
                item_by_key: dict[tuple[FeedItemType, UUID], FeedListItem] = {
                    **{
                        (FeedItemType.OBSERVATION, item.id): PostListItem.model_validate(
                            item,
                            from_attributes=True,
                        )
                        for item in posts
                    },
                    **{
                        (FeedItemType.LOST_PET, item.id): LostPetListItem.model_validate(
                            item,
                            from_attributes=True,
                        )
                        for item in lost_pets
                    },
                    **{
                        (FeedItemType.ADOPTION, item.id): AdoptionPostListItem.model_validate(
                            item,
                            from_attributes=True,
                        )
                        for item in adoption_posts
                    },
                }
                items = [
                    item_by_key[(key.item_type, key.item_id)]
                    for key in key_page.items
                    if (key.item_type, key.item_id) in item_by_key
                ]
                next_cursor = (
                    self._encode_mixed_cursor(key_page.items[-1], query=query)
                    if key_page.has_next and key_page.items
                    else None
                )
                return GenericListResponse[FeedListItem](
                    items=items,
                    next_cursor=next_cursor,
                    limit=query.limit,
                )

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
            return GenericListResponse[FeedListItem](
                items=post_items,
                next_cursor=post_page.next_cursor,
                limit=post_page.limit,
            )

    @staticmethod
    def _decode_mixed_cursor(
        cursor: str | None,
        *,
        query: FeedQuery,
    ) -> FeedCursorPosition | None:
        if cursor is None:
            return None
        try:
            raw = base64.urlsafe_b64decode(cursor.encode("utf-8")).decode("utf-8")
            payload = json.loads(raw)
            if payload.get("v") != 1 or payload.get("filter") != query.filter_by.value:
                raise ValueError
            if query.filter_by == FeedFilter.NEARBY and (
                payload.get("lat") != query.latitude
                or payload.get("lon") != query.longitude
                or payload.get("radius_meters") != query.radius_meters
            ):
                raise ValueError
            created_at = datetime.fromisoformat(str(payload["created_at"]).replace("Z", "+00:00"))
            item_type = FeedItemType(str(payload["item_type"]))
            item_id = UUID(str(payload["id"]))
            distance_meters = payload.get("distance_meters")
            return FeedCursorPosition(
                created_at=created_at,
                item_type=item_type,
                item_id=item_id,
                distance_meters=(float(distance_meters) if distance_meters is not None else None),
            )
        except Exception as exc:
            raise ValueError("Invalid mixed feed cursor.") from exc

    @staticmethod
    def _encode_mixed_cursor(item: FeedItemKey, *, query: FeedQuery) -> str:
        payload: dict[str, object] = {
            "v": 1,
            "filter": query.filter_by.value,
            "created_at": item.created_at.astimezone(UTC).isoformat().replace("+00:00", "Z"),
            "item_type": item.item_type.value,
            "id": str(item.item_id),
        }
        if query.filter_by == FeedFilter.NEARBY:
            payload.update(
                {
                    "lat": query.latitude,
                    "lon": query.longitude,
                    "radius_meters": query.radius_meters,
                    "distance_meters": item.distance_meters,
                }
            )
        raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        return base64.urlsafe_b64encode(raw).decode("utf-8")
