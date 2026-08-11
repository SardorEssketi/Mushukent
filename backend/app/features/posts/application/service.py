from __future__ import annotations

from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID, uuid4

from structlog import get_logger

from app.core.security import api_error
from app.core.storage import (
    StorageConfigurationError,
    StorageOperationError,
    StorageValidationError,
)
from app.features.auth.domain.models import AuthUser
from app.features.cats.domain.models import CatRecord
from app.features.cats.domain.repositories import CatRepository
from app.features.posts.application.schemas import (
    GenericListResponse,
    PostCreateJSONRequest,
    PostCreateMultipartRequest,
    PostListItem,
    PostResponse,
    to_post_page_response,
    to_post_response,
)
from app.features.posts.domain.models import CatObservationStats, PostDetailRecord, PostSortOrder
from app.features.posts.domain.repositories import PostCreateDraft, PostPhotoDraft, PostRepository
from app.features.users.domain.repositories import UserProfileRepository
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.storage.service import MediaStorageService, UploadPurpose

logger = get_logger(__name__)


class PostRepositoryFactory(Protocol):
    def __call__(self, session) -> PostRepository: ...


class CatRepositoryFactory(Protocol):
    def __call__(self, session) -> CatRepository: ...


class UserProfileRepositoryFactory(Protocol):
    def __call__(self, session) -> UserProfileRepository: ...


class PostsService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        post_repository_factory: PostRepositoryFactory,
        cat_repository_factory: CatRepositoryFactory,
        user_repository_factory: UserProfileRepositoryFactory,
        media_storage_service: MediaStorageService | None = None,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.post_repository_factory = post_repository_factory
        self.cat_repository_factory = cat_repository_factory
        self.user_repository_factory = user_repository_factory
        self.media_storage_service = media_storage_service

    def create_post(
        self,
        user: AuthUser,
        payload: PostCreateJSONRequest | PostCreateMultipartRequest,
        *,
        photo_content: bytes | None = None,
        photo_content_type: str | None = None,
        photo_filename: str | None = None,
        photos: list[tuple[bytes, str | None, str | None]] | None = None,
    ) -> PostResponse:
        photo_payloads = list(photos or [])
        if photo_content is not None:
            photo_payloads.insert(0, (photo_content, photo_content_type, photo_filename))
        self._validate_photo_inputs(payload.photo_url, photo_payloads)

        post_id = uuid4()
        uploaded_keys: list[str] = []
        photo_url: str | None = str(payload.photo_url) if payload.photo_url is not None else None
        thumb_url: str | None = None
        photo_drafts: list[PostPhotoDraft] = []

        try:
            if photo_payloads:
                if len(photo_payloads) > 5:
                    raise api_error(
                        400,
                        "INVALID_PAYLOAD",
                        "Observation posts can include up to 5 photos.",
                    )
                for index, (content, content_type, filename) in enumerate(photo_payloads):
                    photo_id = uuid4()
                    uploaded_url, uploaded_thumb_url, keys = self._upload_post_photo(
                        entity_id=photo_id,
                        content=content,
                        content_type=content_type,
                        filename=filename,
                    )
                    uploaded_keys.extend(keys)
                    if index == 0:
                        photo_url = uploaded_url
                        thumb_url = uploaded_thumb_url
                    photo_drafts.append(
                        PostPhotoDraft(
                            id=photo_id,
                            photo_url=uploaded_url,
                            thumb_url=uploaded_thumb_url,
                            position=index,
                        )
                    )
            elif photo_url is not None:
                photo_drafts.append(
                    PostPhotoDraft(
                        id=uuid4(),
                        photo_url=photo_url,
                        thumb_url=None,
                        position=0,
                    )
                )

            with self.db_session_manager.session_scope() as session:
                post_repository = self.post_repository_factory(session)
                cat_repository = self.cat_repository_factory(session)
                location = payload.location

                cat = self._resolve_cat_for_create(cat_repository, user, payload)
                if payload.new_cat is not None:
                    cat = cat_repository.create(
                        cat=CatRecord(
                            id=cat.id,
                            name=payload.new_cat.name.strip() if payload.new_cat.name else None,
                            status=payload.new_cat.status,
                            approximate_age_smallyears=None,
                            cover_photo_url=None,
                            canonical_location=payload.new_cat.canonical_location,
                            first_seen_at=None,
                            last_seen_at=None,
                            total_observations=0,
                            total_contributors=0,
                            total_likes=0,
                            created_by=user.id,
                            is_active=True,
                        )
                    )

                created = post_repository.create(
                    PostCreateDraft(
                        id=post_id,
                        cat_id=cat.id,
                        user_id=user.id,
                        photo_url=photo_url or "",
                        thumb_url=thumb_url,
                        photos=photo_drafts,
                        description=payload.description.strip() if payload.description else None,
                        location_latitude=location.latitude if location is not None else None,
                        location_longitude=location.longitude if location is not None else None,
                        status=(
                            payload.status or (payload.new_cat.status if payload.new_cat else None)
                        ),
                        is_public=payload.is_public,
                    )
                )

                stats = post_repository.recalculate_cat_stats(cat.id)
                self._apply_cat_stats(cat_repository, cat, stats)
                detail = post_repository.get_by_id(created.id, viewer_user_id=user.id)
                if detail is None:
                    raise RuntimeError("Created post could not be loaded.")
                return to_post_response(detail)
        except StorageValidationError as exc:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise api_error(422, "INVALID_IMAGE", "Invalid image file.") from exc
        except StorageConfigurationError as exc:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise api_error(
                500,
                "STORAGE_NOT_CONFIGURED",
                "Image storage is not configured.",
            ) from exc
        except StorageOperationError as exc:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise api_error(502, "IMAGE_UPLOAD_FAILED", "Image upload failed.") from exc
        except Exception:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise

    def get_post(
        self,
        post_id: UUID,
        *,
        current_user: AuthUser | None = None,
    ) -> PostResponse:
        with self.db_session_manager.session_scope() as session:
            post_repository = self.post_repository_factory(session)
            detail = post_repository.get_by_id(
                post_id,
                include_deleted=False,
                viewer_user_id=current_user.id if current_user is not None else None,
            )
            if detail is None or not self._can_view_post(detail, current_user):
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")
            return to_post_response(detail)

    def delete_post(self, post_id: UUID, user: AuthUser) -> None:
        with self.db_session_manager.session_scope() as session:
            post_repository = self.post_repository_factory(session)
            cat_repository = self.cat_repository_factory(session)
            current = post_repository.get_by_id(
                post_id,
                include_deleted=True,
                viewer_user_id=user.id,
            )
            if current is None:
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")

            if current.deleted_at is not None:
                if user.is_moderator or current.user_id == user.id:
                    return
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")

            if not user.is_moderator and current.user_id != user.id:
                raise api_error(
                    403,
                    "FORBIDDEN",
                    "You do not have permission to perform this action.",
                )

            deleted = post_repository.mark_deleted(
                post_id,
                deleted_at=datetime.now(UTC),
                deleted_by=user.id,
            )
            if not deleted:
                return

            stats = post_repository.recalculate_cat_stats(current.cat_id)
            cat = cat_repository.get_by_id(current.cat.id)
            if cat is None:
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")
            self._apply_cat_stats(cat_repository, cat, stats)
            logger.info(
                "post_deleted",
                post_id=str(post_id),
                actor_id=str(user.id),
                moderator=user.is_moderator,
            )

    def list_posts_by_user(
        self,
        user_id: UUID,
        *,
        current_user: AuthUser | None = None,
        limit: int = 20,
        cursor: str | None = None,
        sort: PostSortOrder = PostSortOrder.LATEST,
    ) -> GenericListResponse[PostListItem]:
        with self.db_session_manager.session_scope() as session:
            user_repository = self.user_repository_factory(session)
            target_user = user_repository.get_by_id(user_id)
            if target_user is None or not target_user.is_active:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")

            is_owner_or_moderator = bool(
                current_user is not None
                and (current_user.is_moderator or current_user.id == user_id)
            )
            if not is_owner_or_moderator and not target_user.allow_public_activity_view:
                raise api_error(
                    403,
                    "ACTIVITY_PRIVATE",
                    "This user does not allow public activity viewing.",
                )

            include_private = bool(
                current_user is not None
                and (current_user.is_moderator or current_user.id == user_id)
            )
            post_repository = self.post_repository_factory(session)
            page = post_repository.list_for_user(
                user_id,
                limit=limit,
                cursor=cursor,
                sort=sort,
                include_private=include_private,
                require_visible_cat=not include_private,
                viewer_user_id=current_user.id if current_user is not None else None,
            )
            return to_post_page_response(page)

    def list_posts_by_cat(
        self,
        cat_id: UUID,
        *,
        current_user: AuthUser | None = None,
        limit: int = 20,
        cursor: str | None = None,
        sort: PostSortOrder = PostSortOrder.LATEST,
    ) -> GenericListResponse[PostListItem]:
        with self.db_session_manager.session_scope() as session:
            cat_repository = self.cat_repository_factory(session)
            cat = cat_repository.get_by_id(cat_id)
            if (
                cat is None
                or cat.deleted_at is not None
                or not cat.is_active
                or cat.merged_into is not None
            ):
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")

            include_private = bool(current_user is not None and current_user.is_moderator)
            post_repository = self.post_repository_factory(session)
            page = post_repository.list_for_cat(
                cat_id,
                limit=limit,
                cursor=cursor,
                sort=sort,
                include_private=include_private,
                require_visible_cat=not include_private,
                viewer_user_id=current_user.id if current_user is not None else None,
            )
            return to_post_page_response(page)

    def _resolve_cat_for_create(
        self,
        cat_repository: CatRepository,
        user: AuthUser,
        payload: PostCreateJSONRequest | PostCreateMultipartRequest,
    ) -> CatRecord:
        if payload.cat_id is not None:
            cat = cat_repository.get_by_id(payload.cat_id)
            if (
                cat is None
                or cat.deleted_at is not None
                or not cat.is_active
                or cat.merged_into is not None
            ):
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")
            return cat

        if payload.new_cat is None:
            raise api_error(400, "INVALID_PAYLOAD", "Either cat_id or new_cat must be provided.")

        return CatRecord(
            id=uuid4(),
            name=payload.new_cat.name.strip() if payload.new_cat.name else None,
            status=payload.new_cat.status,
            approximate_age_smallyears=None,
            cover_photo_url=None,
            canonical_location=payload.new_cat.canonical_location,
            first_seen_at=None,
            last_seen_at=None,
            total_observations=0,
            total_contributors=0,
            total_likes=0,
            created_by=user.id,
            is_active=True,
        )

    def _apply_cat_stats(
        self,
        cat_repository: CatRepository,
        cat: CatRecord,
        stats: CatObservationStats,
    ) -> None:
        cat.first_seen_at = stats.first_seen_at
        cat.last_seen_at = stats.last_seen_at
        cat.total_observations = stats.total_observations
        cat.total_contributors = stats.total_contributors
        cat.total_likes = stats.total_likes
        cat_repository.save(cat)

    def _validate_photo_inputs(
        self,
        photo_url: object | None,
        photos: list[tuple[bytes, str | None, str | None]],
    ) -> None:
        if photo_url is not None and photos:
            raise api_error(
                400,
                "INVALID_PAYLOAD",
                "Provide either photo uploads or photo_url, not both.",
            )
        if photo_url is None and not photos:
            raise api_error(
                400,
                "INVALID_PAYLOAD",
                "At least one photo or photo_url must be provided.",
            )

    def _upload_post_photo(
        self,
        *,
        entity_id: UUID,
        content: bytes,
        content_type: str | None,
        filename: str | None,
    ) -> tuple[str, str | None, list[str]]:
        if self.media_storage_service is None:
            raise api_error(500, "STORAGE_NOT_CONFIGURED", "Image storage is not configured.")

        media = self.media_storage_service.upload_image(
            purpose=UploadPurpose.POST_OBSERVATION,
            entity_id=entity_id,
            content=content,
            content_type=content_type,
            original_filename=filename,
        )
        uploaded_keys = [media.canonical.key]
        thumb_url = None
        if media.thumbnail is not None:
            uploaded_keys.append(media.thumbnail.key)
            thumb_url = media.thumbnail.url
        return media.canonical.url, thumb_url, uploaded_keys

    def _cleanup_uploaded_objects(self, keys: list[str]) -> None:
        if self.media_storage_service is None:
            return
        for key in keys:
            try:
                self.media_storage_service.delete_object(key)
            except Exception:  # pragma: no cover - best-effort cleanup
                logger.warning("post_upload_cleanup_failed", key=key)

    @staticmethod
    def _can_view_post(post: PostDetailRecord, current_user: AuthUser | None) -> bool:
        if current_user is not None and current_user.is_moderator:
            return True
        if current_user is not None and post.user_id == current_user.id:
            return True

        cat_visible = (
            post.cat.deleted_at is None and post.cat.is_active and post.cat.merged_into is None
        )
        return post.is_public and cat_visible
