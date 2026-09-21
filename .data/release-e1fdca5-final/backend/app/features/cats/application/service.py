from __future__ import annotations

from typing import Protocol
from uuid import UUID, uuid4

from app.core.security import api_error
from app.core.storage import (
    StorageConfigurationError,
    StorageOperationError,
    StorageValidationError,
)
from app.features.auth.domain.models import AuthUser
from app.features.cats.application.schemas import (
    CatCreateRequest,
    CatDetailResponse,
    CatListItem,
    CatListQuery,
    CatResponse,
    CatUpdateRequest,
    GenericListResponse,
    to_cat_detail_response,
    to_cat_list_response,
    to_cat_response,
)
from app.features.cats.domain.models import (
    CatRecord,
    ObservationSortOrder,
)
from app.features.cats.domain.repositories import CatRepository
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.storage.service import MediaStorageService, UploadPurpose


class CatRepositoryFactory(Protocol):
    def __call__(self, session) -> CatRepository: ...


class CatsService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: CatRepositoryFactory,
        media_storage_service: MediaStorageService | None = None,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.media_storage_service = media_storage_service

    def create_cat(
        self,
        user: AuthUser,
        payload: CatCreateRequest,
        *,
        cover_photo_content: bytes | None = None,
        cover_photo_content_type: str | None = None,
        cover_photo_filename: str | None = None,
    ) -> CatResponse:
        self._validate_cover_photo_inputs(payload.cover_photo_url, cover_photo_content)

        cat_id = uuid4()
        uploaded_key: str | None = None
        cover_photo_url = str(payload.cover_photo_url) if payload.cover_photo_url else None

        if cover_photo_content is not None:
            cover_photo_url, uploaded_key = self._upload_cover_photo(
                entity_id=cat_id,
                content=cover_photo_content,
                content_type=cover_photo_content_type,
                filename=cover_photo_filename,
            )

        try:
            with self.db_session_manager.session_scope() as session:
                repository = self.repository_factory(session)
                created = repository.create(
                    cat=CatRecord(
                        id=cat_id,
                        name=payload.name.strip() if payload.name is not None else None,
                        status=payload.status,
                        approximate_age_smallyears=payload.approximate_age_smallyears,
                        cover_photo_url=cover_photo_url,
                        canonical_location=payload.canonical_location,
                        first_seen_at=None,
                        last_seen_at=None,
                        total_observations=0,
                        total_contributors=0,
                        total_likes=0,
                        created_by=user.id,
                        is_active=True,
                    )
                )
                return to_cat_response(created)
        except Exception:
            if uploaded_key is not None:
                self._cleanup_uploaded_object(uploaded_key)
            raise

    def update_cat(
        self,
        user: AuthUser,
        cat_id: UUID,
        payload: CatUpdateRequest,
        *,
        cover_photo_content: bytes | None = None,
        cover_photo_content_type: str | None = None,
        cover_photo_filename: str | None = None,
    ) -> CatResponse:
        self._validate_cover_photo_inputs(payload.cover_photo_url, cover_photo_content)

        uploaded_key: str | None = None
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(cat_id)
            if current is None or current.deleted_at is not None or not current.is_active:
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")
            if current.merged_into is not None and not user.is_moderator:
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")

            if payload.merged_into is not None and not user.is_moderator:
                raise api_error(
                    403, "FORBIDDEN", "You do not have permission to perform this action."
                )
            if payload.status is not None and not user.is_moderator:
                raise api_error(
                    403, "FORBIDDEN", "You do not have permission to perform this action."
                )
            if payload.merged_into is not None:
                if payload.merged_into == current.id:
                    raise api_error(
                        400,
                        "INVALID_PAYLOAD",
                        "A cat cannot be merged into itself.",
                    )
                merged_target = repository.get_by_id(payload.merged_into)
                if (
                    merged_target is None
                    or merged_target.deleted_at is not None
                    or not merged_target.is_active
                ):
                    raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")

            cover_photo_url = current.cover_photo_url
            if cover_photo_content is not None:
                cover_photo_url, uploaded_key = self._upload_cover_photo(
                    entity_id=current.id,
                    content=cover_photo_content,
                    content_type=cover_photo_content_type,
                    filename=cover_photo_filename,
                )

            try:
                saved = repository.save(
                    CatRecord(
                        id=current.id,
                        name=payload.name.strip() if payload.name is not None else current.name,
                        status=payload.status or current.status,
                        approximate_age_smallyears=(
                            payload.approximate_age_smallyears
                            if payload.approximate_age_smallyears is not None
                            else current.approximate_age_smallyears
                        ),
                        cover_photo_url=cover_photo_url,
                        canonical_location=(
                            payload.canonical_location
                            if payload.canonical_location is not None
                            else current.canonical_location
                        ),
                        first_seen_at=current.first_seen_at,
                        last_seen_at=current.last_seen_at,
                        total_observations=current.total_observations,
                        total_contributors=current.total_contributors,
                        total_likes=current.total_likes,
                        created_at=current.created_at,
                        updated_at=current.updated_at,
                        created_by=current.created_by,
                        is_active=current.is_active,
                        merged_into=(
                            payload.merged_into if user.is_moderator else current.merged_into
                        ),
                        deleted_at=current.deleted_at,
                    )
                )
                return to_cat_response(saved)
            except Exception:
                if uploaded_key is not None:
                    self._cleanup_uploaded_object(uploaded_key)
                raise

    def get_cat(
        self,
        cat_id: UUID,
        *,
        limit: int = 20,
        cursor: str | None = None,
        order: ObservationSortOrder = ObservationSortOrder.LATEST,
    ) -> CatDetailResponse:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            detail = repository.get_detail(cat_id)
            if (
                detail is None
                or detail.deleted_at is not None
                or not detail.is_active
                or detail.merged_into is not None
            ):
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")

            try:
                history_page = repository.list_history(
                    cat_id=cat_id,
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
            return to_cat_detail_response(
                detail,
                history=history_page.items,
                next_cursor=history_page.next_cursor,
                limit=history_page.limit,
            )

    def list_cats(self, query: CatListQuery) -> GenericListResponse[CatListItem]:
        bbox = self._parse_bbox(query.bbox)
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            try:
                page = repository.list_cats(
                    filter_by=query.filter_by,
                    limit=query.limit,
                    cursor=query.cursor,
                    latitude=query.latitude,
                    longitude=query.longitude,
                    radius_meters=query.radius_meters,
                    bbox=bbox,
                )
            except ValueError as exc:
                raise api_error(
                    422,
                    "VALIDATION_ERROR",
                    "Validation failed.",
                    details={"cursor": ["invalid"]},
                ) from exc
            return to_cat_list_response(page.items, next_cursor=page.next_cursor, limit=page.limit)

    def _validate_cover_photo_inputs(
        self,
        cover_photo_url: object | None,
        cover_photo_content: bytes | None,
    ) -> None:
        if cover_photo_url is not None and cover_photo_content is not None:
            raise api_error(
                400,
                "INVALID_PAYLOAD",
                "Provide either cover_photo_url or cover_photo, not both.",
            )

    def _upload_cover_photo(
        self,
        *,
        entity_id: UUID,
        content: bytes,
        content_type: str | None,
        filename: str | None,
    ) -> tuple[str, str]:
        if self.media_storage_service is None:
            raise api_error(500, "STORAGE_NOT_CONFIGURED", "Image storage is not configured.")
        try:
            stored = self.media_storage_service.upload_image(
                purpose=UploadPurpose.CAT_COVER,
                entity_id=entity_id,
                content=content,
                content_type=content_type,
                original_filename=filename,
            )
        except StorageValidationError as exc:
            raise api_error(422, "INVALID_IMAGE", "Invalid image upload.") from exc
        except StorageConfigurationError as exc:
            raise api_error(
                500, "STORAGE_NOT_CONFIGURED", "Image storage is not configured."
            ) from exc
        except StorageOperationError as exc:
            raise api_error(502, "IMAGE_UPLOAD_FAILED", "Image upload failed.") from exc

        return stored.canonical.url, stored.canonical.key

    def _cleanup_uploaded_object(self, key: str) -> None:
        if self.media_storage_service is None:
            return
        try:
            self.media_storage_service.delete_object(key)
        except StorageOperationError:
            return

    @staticmethod
    def _parse_bbox(bbox: str | None) -> tuple[float, float, float, float] | None:
        if bbox is None:
            return None
        parts = [part.strip() for part in bbox.split(",") if part.strip()]
        if len(parts) != 4:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["invalid"]},
            )
        try:
            min_lon, min_lat, max_lon, max_lat = (float(part) for part in parts)
        except ValueError as exc:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["invalid"]},
            ) from exc
        if not (
            -180 <= min_lon <= 180
            and -180 <= max_lon <= 180
            and -90 <= min_lat <= 90
            and -90 <= max_lat <= 90
        ):
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["out_of_range"]},
            )
        if min_lon >= max_lon or min_lat >= max_lat:
            raise api_error(
                422,
                "VALIDATION_ERROR",
                "Validation failed.",
                details={"bbox": ["invalid_bounds"]},
            )
        return (min_lon, min_lat, max_lon, max_lat)
