from __future__ import annotations

from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID, uuid4

from structlog import get_logger

from app.core.phone import UzbekPhoneNumberError, normalize_uzbek_phone_number
from app.core.security import api_error
from app.core.storage import (
    StorageConfigurationError,
    StorageOperationError,
    StorageValidationError,
)
from app.features.adoption_posts.application.schemas import (
    AdoptionFollowUpAnswer,
    AdoptionFollowUpItem,
    AdoptionPostCreateRequest,
    AdoptionPostListItem,
    AdoptionPostResponse,
    AdoptionPostUpdateRequest,
    AdoptionResolutionRequest,
    to_adoption_post_page_response,
    to_adoption_post_response,
)
from app.features.adoption_posts.domain.models import (
    AdoptionPostCreateDraft,
    AdoptionPostPhotoDraft,
    AdoptionPostUpdateDraft,
)
from app.features.adoption_posts.domain.repositories import AdoptionPostRepository
from app.features.auth.domain.models import AuthUser
from app.features.posts.application.schemas import GenericListResponse
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.storage.service import MediaStorageService, UploadPurpose

logger = get_logger(__name__)


class AdoptionPostRepositoryFactory(Protocol):
    def __call__(self, session) -> AdoptionPostRepository: ...


class AdoptionPostsService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: AdoptionPostRepositoryFactory,
        media_storage_service: MediaStorageService | None = None,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.media_storage_service = media_storage_service

    def create_adoption_post(
        self,
        user: AuthUser,
        payload: AdoptionPostCreateRequest,
        *,
        photos: list[tuple[bytes, str | None, str | None]],
    ) -> AdoptionPostResponse:
        phone = user.phone_number.strip() if user.phone_number else ""
        if not phone:
            raise api_error(
                403,
                "PHONE_NUMBER_REQUIRED",
                "Add a phone number to your profile before posting an adoption.",
            )
        try:
            phone = normalize_uzbek_phone_number(phone)
        except UzbekPhoneNumberError as exc:
            raise api_error(
                422,
                "INVALID_PHONE_NUMBER",
                "Use Uzbekistan phone format: +998 XX XXX XXXX.",
            ) from exc
        if not photos:
            raise api_error(400, "INVALID_PAYLOAD", "At least one photo is required.")
        if len(photos) > 5:
            raise api_error(400, "INVALID_PAYLOAD", "Adoption posts can include up to 5 photos.")

        adoption_post_id = uuid4()
        uploaded_keys: list[str] = []
        photo_drafts: list[AdoptionPostPhotoDraft] = []
        try:
            for index, (content, content_type, filename) in enumerate(photos):
                photo_id = uuid4()
                photo_url, thumb_url, keys = self._upload_photo(
                    entity_id=photo_id,
                    content=content,
                    content_type=content_type,
                    filename=filename,
                )
                uploaded_keys.extend(keys)
                photo_drafts.append(
                    AdoptionPostPhotoDraft(
                        id=photo_id,
                        photo_url=photo_url,
                        thumb_url=thumb_url,
                        position=index,
                    )
                )

            with self.db_session_manager.session_scope() as session:
                repository = self.repository_factory(session)
                created = repository.create(
                    AdoptionPostCreateDraft(
                        id=adoption_post_id,
                        user_id=user.id,
                        pet_name=payload.pet_name.strip(),
                        owner_phone_number=phone,
                        owner_telegram_username=user.telegram_username,
                        owner_phone_publication_consent=True,
                        additional_info=(
                            payload.additional_info.strip() if payload.additional_info else None
                        ),
                        photos=photo_drafts,
                    )
                )
                return to_adoption_post_response(created)
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

    def get_adoption_post(
        self, adoption_post_id: UUID, user: AuthUser | None = None
    ) -> AdoptionPostResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            item = repository.get_by_id(adoption_post_id)
            if item is None:
                raise api_error(404, "ADOPTION_POST_NOT_FOUND", "Adoption post not found.")
            response = to_adoption_post_response(item)
            if item.is_resolved and (user is None or user.id != item.user_id):
                return response.model_copy(
                    update={"owner_phone_number": None, "owner_telegram_username": None}
                )
            return response

    def update_adoption_post(
        self,
        adoption_post_id: UUID,
        user: AuthUser,
        payload: AdoptionPostUpdateRequest,
        *,
        photos: list[tuple[bytes, str | None, str | None]] | None = None,
    ) -> AdoptionPostResponse:
        photo_payloads = list(photos or [])
        if len(photo_payloads) > 5:
            raise api_error(400, "INVALID_PAYLOAD", "Adoption posts can include up to 5 photos.")
        uploaded_keys: list[str] = []
        replacement_photos: list[AdoptionPostPhotoDraft] | None = None
        try:
            with self.db_session_manager.session_scope() as session:
                existing = self.repository_factory(session).get_by_id(adoption_post_id)
                self._require_owner(existing, user)
            assert existing is not None

            for index, (content, content_type, filename) in enumerate(photo_payloads):
                photo_id = uuid4()
                photo_url, thumb_url, keys = self._upload_photo(
                    entity_id=photo_id,
                    content=content,
                    content_type=content_type,
                    filename=filename,
                )
                uploaded_keys.extend(keys)
                if replacement_photos is None:
                    replacement_photos = []
                replacement_photos.append(
                    AdoptionPostPhotoDraft(
                        id=photo_id,
                        photo_url=photo_url,
                        thumb_url=thumb_url,
                        position=index,
                    )
                )

            phone = existing.owner_phone_number
            if "owner_phone_number" in payload.model_fields_set:
                try:
                    phone = normalize_uzbek_phone_number(payload.owner_phone_number or "")
                except UzbekPhoneNumberError as exc:
                    raise api_error(
                        422,
                        "INVALID_PHONE_NUMBER",
                        "Use Uzbekistan phone format: +998 XX XXX XXXX.",
                    ) from exc
            telegram = existing.owner_telegram_username
            if "owner_telegram_username" in payload.model_fields_set:
                telegram = (
                    payload.owner_telegram_username.removeprefix("@") or None
                    if payload.owner_telegram_username is not None
                    else None
                )
            pet_name = (
                payload.pet_name if "pet_name" in payload.model_fields_set else existing.pet_name
            )
            additional_info = (
                payload.additional_info or None
                if "additional_info" in payload.model_fields_set
                else existing.additional_info
            )

            with self.db_session_manager.session_scope() as session:
                repository = self.repository_factory(session)
                current = repository.get_by_id(adoption_post_id, for_update=True)
                self._require_owner(current, user)
                updated = repository.update(
                    adoption_post_id,
                    AdoptionPostUpdateDraft(
                        pet_name=pet_name,
                        owner_phone_number=phone,
                        owner_telegram_username=telegram,
                        additional_info=additional_info,
                        photos=replacement_photos,
                        updated_at=datetime.now(UTC),
                    ),
                )
                return to_adoption_post_response(updated)
        except StorageValidationError as exc:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise api_error(422, "INVALID_IMAGE", "Invalid image file.") from exc
        except StorageConfigurationError as exc:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise api_error(
                500, "STORAGE_NOT_CONFIGURED", "Image storage is not configured."
            ) from exc
        except StorageOperationError as exc:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise api_error(502, "IMAGE_UPLOAD_FAILED", "Image upload failed.") from exc
        except Exception:
            self._cleanup_uploaded_objects(uploaded_keys)
            raise

    def delete_adoption_post(self, adoption_post_id: UUID, user: AuthUser) -> None:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(adoption_post_id, for_update=True, include_deleted=True)
            self._require_owner(current, user)
            assert current is not None
            if current.deleted_at is None:
                repository.soft_delete(adoption_post_id, datetime.now(UTC))

    def set_resolution(
        self, adoption_post_id: UUID, user: AuthUser, payload: AdoptionResolutionRequest
    ) -> AdoptionPostResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(adoption_post_id, for_update=True)
            self._require_owner(current, user)
            updated = repository.set_resolution(
                adoption_post_id,
                is_resolved=payload.is_resolved,
                changed_at=datetime.now(UTC),
            )
            return to_adoption_post_response(updated)

    def contact_owner(self, adoption_post_id: UUID, user: AuthUser) -> None:
        with self.db_session_manager.session_scope() as session:
            try:
                recorded = self.repository_factory(session).record_contact(
                    adoption_post_id, user.id
                )
            except PermissionError as exc:
                raise api_error(
                    403, "CONTACT_OWNER_FORBIDDEN", "You own this adoption post."
                ) from exc
            if not recorded:
                raise api_error(404, "ADOPTION_POST_NOT_ACTIVE", "Active adoption post not found.")

    def list_due_follow_ups(self, user: AuthUser) -> list[AdoptionFollowUpItem]:
        with self.db_session_manager.session_scope() as session:
            records = self.repository_factory(session).list_due_follow_ups(
                user.id, datetime.now(UTC)
            )
            return [
                AdoptionFollowUpItem.model_validate(item, from_attributes=True) for item in records
            ]

    def answer_follow_up(
        self, follow_up_id: UUID, user: AuthUser, payload: AdoptionFollowUpAnswer
    ) -> AdoptionPostResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            result, post_id = repository.answer_follow_up(
                follow_up_id, user.id, payload.answer == "yes", datetime.now(UTC)
            )
            if result == "not_found":
                raise api_error(404, "FOLLOW_UP_NOT_FOUND", "Adoption follow-up not found.")
            if result == "forbidden":
                raise api_error(
                    403, "FOLLOW_UP_FORBIDDEN", "Only the owner can answer this follow-up."
                )
            if result == "completed":
                raise api_error(409, "FOLLOW_UP_COMPLETED", "This follow-up was already answered.")
            if result == "not_due":
                raise api_error(409, "FOLLOW_UP_NOT_DUE", "This follow-up is not due yet.")
            if result != "answered" or post_id is None:
                raise api_error(
                    409, "ADOPTION_POST_NOT_ACTIVE", "Adoption post is no longer active."
                )
            item = repository.get_by_id(post_id)
            if item is None:
                raise RuntimeError("Answered adoption post could not be loaded.")
            return to_adoption_post_response(item)

    def list_my_adoption_posts(
        self, user: AuthUser, *, limit: int = 20, cursor: str | None = None
    ) -> GenericListResponse[AdoptionPostListItem]:
        with self.db_session_manager.session_scope() as session:
            try:
                page = self.repository_factory(session).list_owned(
                    user.id, limit=limit, cursor=cursor
                )
            except ValueError as exc:
                raise api_error(422, "VALIDATION_ERROR", "Invalid cursor.") from exc
            return to_adoption_post_page_response(page)

    @staticmethod
    def _require_owner(item, user: AuthUser) -> None:
        if item is None:
            raise api_error(404, "ADOPTION_POST_NOT_FOUND", "Adoption post not found.")
        if item.user_id != user.id:
            raise api_error(403, "ADOPTION_POST_FORBIDDEN", "Only the owner may change this post.")

    def list_adoption_posts(
        self,
        *,
        limit: int = 20,
        cursor: str | None = None,
    ) -> GenericListResponse[AdoptionPostListItem]:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            try:
                page = repository.list_public(limit=limit, cursor=cursor)
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_adoption_post_page_response(page)

    def _upload_photo(
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
            purpose=UploadPurpose.ADOPTION,
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
            except Exception:  # pragma: no cover
                logger.warning("adoption_post_upload_cleanup_failed", key=key)
