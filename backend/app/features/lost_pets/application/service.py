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
from app.features.auth.domain.models import AuthUser
from app.features.lost_pets.application.schemas import (
    LostPetCreateRequest,
    LostPetFollowUpAnswer,
    LostPetFollowUpItem,
    LostPetListItem,
    LostPetMapListItem,
    LostPetResolutionRequest,
    LostPetResponse,
    LostPetUpdateRequest,
    to_lost_pet_map_page_response,
    to_lost_pet_page_response,
    to_lost_pet_response,
)
from app.features.lost_pets.domain.models import (
    LostPetCreateDraft,
    LostPetPhotoDraft,
    LostPetUpdateDraft,
)
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
        notification_repository_factory=None,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.media_storage_service = media_storage_service
        self.notification_repository_factory = notification_repository_factory

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
                if self.notification_repository_factory is not None:
                    notifications = self.notification_repository_factory(session)
                    recipients = notifications.nearby_recipients(
                        latitude=payload.last_seen_location.latitude,
                        longitude=payload.last_seen_location.longitude,
                        owner_id=user.id,
                    )
                    notifications.create_nearby_events(
                        lost_pet_id=created.id, recipient_ids=recipients
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

    def get_lost_pet(self, lost_pet_id: UUID, user: AuthUser | None = None) -> LostPetResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            item = repository.get_by_id(lost_pet_id)
            if item is None:
                raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")
            response = to_lost_pet_response(item)
            if item.is_resolved and (user is None or user.id != item.user_id):
                return response.model_copy(
                    update={
                        "owner_phone_number": None,
                        "owner_telegram_username": None,
                        "last_seen_location": None,
                    }
                )
            return response

    def update_lost_pet(
        self,
        lost_pet_id: UUID,
        user: AuthUser,
        payload: LostPetUpdateRequest,
        *,
        photos: list[tuple[bytes, str | None, str | None]] | None = None,
    ) -> LostPetResponse:
        photo_payloads = list(photos or [])
        if len(photo_payloads) > 5:
            raise api_error(400, "INVALID_PAYLOAD", "Lost pet posts can include up to 5 photos.")

        uploaded_keys: list[str] = []
        replacement_photos: list[LostPetPhotoDraft] | None = None
        try:
            with self.db_session_manager.session_scope() as session:
                existing = self.repository_factory(session).get_by_id(lost_pet_id)
                self._require_owner(existing, user)

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
                    LostPetPhotoDraft(
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
                    payload.owner_telegram_username.strip().removeprefix("@") or None
                    if payload.owner_telegram_username is not None
                    else None
                )

            location = payload.last_seen_location or existing.last_seen_location
            pet_name = (
                payload.pet_name.strip()
                if "pet_name" in payload.model_fields_set and payload.pet_name is not None
                else existing.pet_name
            )
            additional_info = (
                payload.additional_info.strip() or None
                if "additional_info" in payload.model_fields_set
                and payload.additional_info is not None
                else (
                    None
                    if "additional_info" in payload.model_fields_set
                    else existing.additional_info
                )
            )

            with self.db_session_manager.session_scope() as session:
                repository = self.repository_factory(session)
                current = repository.get_by_id(lost_pet_id, for_update=True)
                self._require_owner(current, user)
                assert current is not None
                updated = repository.update(
                    lost_pet_id,
                    LostPetUpdateDraft(
                        pet_name=pet_name,
                        owner_phone_number=phone,
                        owner_telegram_username=telegram,
                        last_seen_latitude=location.latitude,
                        last_seen_longitude=location.longitude,
                        additional_info=additional_info,
                        photos=replacement_photos,
                        updated_at=datetime.now(UTC),
                    ),
                )
                return to_lost_pet_response(updated)
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

    def delete_lost_pet(self, lost_pet_id: UUID, user: AuthUser) -> None:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(lost_pet_id, for_update=True, include_deleted=True)
            self._require_owner(current, user)
            if current.deleted_at is not None:
                return
            repository.soft_delete(lost_pet_id, datetime.now(UTC))

    def set_resolution(
        self, lost_pet_id: UUID, user: AuthUser, payload: LostPetResolutionRequest
    ) -> LostPetResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(lost_pet_id, for_update=True)
            self._require_owner(current, user)
            updated = repository.set_resolution(
                lost_pet_id,
                is_resolved=payload.is_resolved,
                changed_at=datetime.now(UTC),
            )
            return to_lost_pet_response(updated)

    def contact_owner(self, lost_pet_id: UUID, user: AuthUser) -> None:
        with self.db_session_manager.session_scope() as session:
            try:
                recorded = self.repository_factory(session).record_contact(lost_pet_id, user.id)
            except PermissionError as exc:
                raise api_error(
                    403, "CONTACT_OWNER_FORBIDDEN", "You own this lost pet post."
                ) from exc
            if not recorded:
                raise api_error(404, "LOST_PET_NOT_ACTIVE", "Active lost pet post not found.")

    def list_due_follow_ups(self, user: AuthUser) -> list[LostPetFollowUpItem]:
        with self.db_session_manager.session_scope() as session:
            records = self.repository_factory(session).list_due_follow_ups(
                user.id, datetime.now(UTC)
            )
            return [
                LostPetFollowUpItem.model_validate(item, from_attributes=True) for item in records
            ]

    def answer_follow_up(
        self, follow_up_id: UUID, user: AuthUser, payload: LostPetFollowUpAnswer
    ) -> LostPetResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            result, lost_pet_id = repository.answer_follow_up(
                follow_up_id, user.id, payload.answer == "yes", datetime.now(UTC)
            )
            if result == "not_found":
                raise api_error(404, "FOLLOW_UP_NOT_FOUND", "Lost pet follow-up not found.")
            if result == "forbidden":
                raise api_error(
                    403, "FOLLOW_UP_FORBIDDEN", "Only the owner can answer this follow-up."
                )
            if result == "completed":
                raise api_error(409, "FOLLOW_UP_COMPLETED", "This follow-up was already answered.")
            if result == "not_due":
                raise api_error(409, "FOLLOW_UP_NOT_DUE", "This follow-up is not due yet.")
            if result != "answered" or lost_pet_id is None:
                raise api_error(409, "LOST_PET_NOT_ACTIVE", "Lost pet post is no longer active.")
            item = repository.get_by_id(lost_pet_id)
            if item is None:
                raise RuntimeError("Answered lost pet could not be loaded.")
            return to_lost_pet_response(item)

    def list_my_lost_pets(
        self, user: AuthUser, *, limit: int = 20, cursor: str | None = None
    ) -> GenericListResponse[LostPetListItem]:
        with self.db_session_manager.session_scope() as session:
            try:
                page = self.repository_factory(session).list_owned(
                    user.id, limit=limit, cursor=cursor
                )
            except ValueError as exc:
                raise api_error(422, "VALIDATION_ERROR", "Invalid cursor.") from exc
            return to_lost_pet_page_response(page)

    def list_lost_pets(
        self,
        *,
        limit: int = 20,
        cursor: str | None = None,
        latitude: float | None = None,
        longitude: float | None = None,
        radius_meters: int | None = None,
        valid_for_map: bool = False,
        bbox: str | None = None,
    ) -> GenericListResponse[LostPetListItem]:
        parsed_bbox = self._parse_bbox(bbox)
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
                    bbox=parsed_bbox,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_lost_pet_page_response(page)

    def list_map_markers(
        self,
        *,
        limit: int,
        bbox: str,
    ) -> GenericListResponse[LostPetMapListItem]:
        parsed_bbox = self._parse_bbox(bbox)
        if parsed_bbox is None:
            raise api_error(422, "VALIDATION_ERROR", "Map markers require a bounding box.")
        with self.db_session_manager.session_scope() as session:
            page = self.repository_factory(session).list_map_markers(
                limit=limit,
                bbox=parsed_bbox,
            )
            return to_lost_pet_map_page_response(page)

    @staticmethod
    def _parse_bbox(bbox: str | None) -> tuple[float, float, float, float] | None:
        if bbox is None:
            return None
        parts = [part.strip() for part in bbox.split(",") if part.strip()]
        if len(parts) != 4:
            raise api_error(
                422, "VALIDATION_ERROR", "Validation failed.", details={"bbox": ["invalid"]}
            )
        try:
            min_lon, min_lat, max_lon, max_lat = (float(part) for part in parts)
        except ValueError as exc:
            raise api_error(
                422, "VALIDATION_ERROR", "Validation failed.", details={"bbox": ["invalid"]}
            ) from exc
        if not (
            -180 <= min_lon <= 180
            and -180 <= max_lon <= 180
            and -90 <= min_lat <= 90
            and -90 <= max_lat <= 90
        ):
            raise api_error(
                422, "VALIDATION_ERROR", "Validation failed.", details={"bbox": ["out_of_range"]}
            )
        if min_lon >= max_lon or min_lat >= max_lat:
            raise api_error(
                422, "VALIDATION_ERROR", "Validation failed.", details={"bbox": ["invalid_bounds"]}
            )
        return (min_lon, min_lat, max_lon, max_lat)

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

    @staticmethod
    def _require_owner(item, user: AuthUser) -> None:
        if item is None:
            raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")
        if item.user_id != user.id:
            raise api_error(
                403,
                "FORBIDDEN",
                "You do not have permission to perform this action.",
            )
