from __future__ import annotations

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
from app.features.auth.domain.models import AuthUser
from app.features.lost_pets.application.schemas import (
    LostPetCreateRequest,
    LostPetListItem,
    LostPetResponse,
    to_lost_pet_page_response,
    to_lost_pet_response,
)
from app.features.lost_pets.domain.models import LostPetCreateDraft, LostPetPhotoDraft
from app.features.lost_pets.domain.repositories import LostPetRepository
from app.features.posts.application.schemas import GenericListResponse
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.storage.service import MediaStorageService, UploadPurpose

logger = get_logger(__name__)


class LostPetRepositoryFactory(Protocol):
    def __call__(self, session) -> LostPetRepository: ...


class LostPetsService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: LostPetRepositoryFactory,
        media_storage_service: MediaStorageService | None = None,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.media_storage_service = media_storage_service

    def create_lost_pet(
        self,
        user: AuthUser,
        payload: LostPetCreateRequest,
        *,
        photos: list[tuple[bytes, str | None, str | None]],
    ) -> LostPetResponse:
        phone = user.phone_number.strip() if user.phone_number else ""
        if not phone:
            raise api_error(
                403,
                "PHONE_NUMBER_REQUIRED",
                "Add a phone number to your profile before posting a lost pet.",
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
            raise api_error(400, "INVALID_PAYLOAD", "Lost pet posts can include up to 5 photos.")
        if not payload.owner_phone_publication_consent:
            raise api_error(
                422,
                "PHONE_PUBLICATION_CONSENT_REQUIRED",
                "Confirm that your phone number may be shown publicly for this lost pet post.",
            )

        lost_pet_id = uuid4()
        uploaded_keys: list[str] = []
        photo_drafts: list[LostPetPhotoDraft] = []
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
                    LostPetPhotoDraft(
                        id=photo_id,
                        photo_url=photo_url,
                        thumb_url=thumb_url,
                        position=index,
                    )
                )

            with self.db_session_manager.session_scope() as session:
                repository = self.repository_factory(session)
                created = repository.create(
                    LostPetCreateDraft(
                        id=lost_pet_id,
                        user_id=user.id,
                        pet_name=payload.pet_name.strip(),
                        owner_phone_number=phone,
                        owner_telegram_username=user.telegram_username,
                        owner_phone_publication_consent=True,
                        last_seen_latitude=payload.last_seen_location.latitude,
                        last_seen_longitude=payload.last_seen_location.longitude,
                        additional_info=(
                            payload.additional_info.strip() if payload.additional_info else None
                        ),
                        photos=photo_drafts,
                    )
                )
                return to_lost_pet_response(created)
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

    def get_lost_pet(self, lost_pet_id: UUID) -> LostPetResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            item = repository.get_by_id(lost_pet_id)
            if item is None:
                raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")
            return to_lost_pet_response(item)

    def list_lost_pets(
        self,
        *,
        limit: int = 20,
        cursor: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        valid_for_map: bool = False,
    ) -> GenericListResponse[LostPetListItem]:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            try:
                page = repository.list_public(
                    limit=limit,
                    cursor=cursor,
                    latitude=latitude,
                    longitude=longitude,
                    radius_meters=radius_meters,
                    valid_for_map=valid_for_map,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_lost_pet_page_response(page)

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
            purpose=UploadPurpose.LOST_PET,
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
                logger.warning("lost_pet_upload_cleanup_failed", key=key)
