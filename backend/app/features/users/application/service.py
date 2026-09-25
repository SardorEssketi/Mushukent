from __future__ import annotations

from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

from sqlalchemy import Text, cast, delete, func, or_, select, update
from structlog import get_logger

from app.core.phone import UzbekPhoneNumberError, normalize_uzbek_phone_number
from app.core.security import api_error
from app.core.storage import (
    StorageConfigurationError,
    StorageOperationError,
    StorageValidationError,
)
from app.features.auth.domain.models import AuthUser
from app.features.auth.infrastructure.email import AccountDeletionConfirmationSender
from app.features.auth.infrastructure.tokens import JoseAccountDeletionTokenService
from app.features.users.application.schemas import UserProfile, UserPublic, UserUpdate
from app.features.users.domain.repositories import UserProfileRepository
from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager
from app.infrastructure.storage.service import MediaStorageService, UploadPurpose

logger = get_logger(__name__)


class UserProfileRepositoryFactory(Protocol):
    def __call__(self, session) -> UserProfileRepository: ...


class UsersService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        repository_factory: UserProfileRepositoryFactory,
        media_storage_service: MediaStorageService | None = None,
        account_deletion_token_service: JoseAccountDeletionTokenService | None = None,
        account_deletion_email_sender: AccountDeletionConfirmationSender | None = None,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.repository_factory = repository_factory
        self.media_storage_service = media_storage_service
        self.account_deletion_token_service = account_deletion_token_service
        self.account_deletion_email_sender = account_deletion_email_sender

    def get_me(self, user: AuthUser) -> UserProfile:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            profile = repository.get_by_id(user.id)
            if profile is None or not profile.is_active:
                raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")

            return self._build_self_profile(repository, profile)

    def get_public_profile(self, user_id: UUID) -> UserPublic:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_id(user_id)
            if user is None or not user.is_active:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")

            observation_count = repository.count_observations(user.id)
            return UserPublic(
                id=user.id,
                name=user.name,
                avatar_url=user.avatar_url,
                registered_at=user.registered_at,
                observation_count=observation_count,
                comment_count=repository.count_comments(user.id),
                allow_public_activity_view=user.allow_public_activity_view,
            )

    def update_me(self, user: AuthUser, payload: UserUpdate) -> UserProfile:
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(user.id)
            if current is None or not current.is_active:
                raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")

            if payload.name is not None:
                current.name = payload.name.strip()
            if payload.bio is not None:
                current.bio = payload.bio.strip()
            if payload.phone_number is not None:
                try:
                    current.phone_number = (
                        normalize_uzbek_phone_number(payload.phone_number)
                        if payload.phone_number.strip()
                        else None
                    )
                except UzbekPhoneNumberError as exc:
                    raise api_error(
                        422,
                        "INVALID_PHONE_NUMBER",
                        "Use Uzbekistan phone format: +998 XX XXX XXXX.",
                    ) from exc
            if payload.telegram_username is not None:
                current.telegram_username = (
                    payload.telegram_username.strip().removeprefix("@") or None
                )
            if payload.preferred_language is not None:
                current.preferred_language = payload.preferred_language
            if payload.allow_public_activity_view is not None:
                current.allow_public_activity_view = payload.allow_public_activity_view
            if payload.avatar_url is not None:
                current.avatar_url = str(payload.avatar_url)

            updated = repository.save(current)
            return self._build_self_profile(repository, updated)

    def delete_me(self, user: AuthUser) -> None:
        media_urls: list[str | None] = []
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            current = repository.get_by_id(user.id)
            if current is None or not current.is_active:
                raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")

            now = datetime.now(UTC)
            media_urls.append(current.avatar_url)
            user_model = session.get(schema.User, user.id)
            if user_model is None:
                raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")

            post_rows = session.scalars(
                select(schema.Post).where(schema.Post.user_id == user.id)
            ).all()
            owned_post_ids = {post.id for post in post_rows}
            for post in post_rows:
                media_urls.extend([post.photo_url, post.thumb_url])
                media_urls.extend(photo.photo_url for photo in post.photos)
                media_urls.extend(photo.thumb_url for photo in post.photos)
                post.user_id = None
                post.description = None
                post.photo_url = f"deleted://post/{post.id}"
                post.thumb_url = None
                post.is_public = False
                post.deleted_at = post.deleted_at or now
                for photo in post.photos:
                    photo.photo_url = f"deleted://post-photo/{photo.id}"
                    photo.thumb_url = None

            history_filter = schema.PostHistory.actor_id == user.id
            if owned_post_ids:
                history_filter = or_(
                    history_filter,
                    schema.PostHistory.post_id.in_(owned_post_ids),
                )
            history_rows = session.scalars(select(schema.PostHistory).where(history_filter)).all()
            for history in history_rows:
                if history.post_id in owned_post_ids:
                    media_urls.extend(self._history_photo_urls(history.before))
                    media_urls.extend(self._history_photo_urls(history.after))
                    history.before = self._redact_post_history_snapshot(history.before)
                    history.after = self._redact_post_history_snapshot(history.after)
                if history.actor_id == user.id:
                    history.actor_id = None

            comment_rows = session.scalars(
                select(schema.Comment).where(schema.Comment.user_id == user.id)
            ).all()
            for comment in comment_rows:
                comment.user_id = None
                comment.content = "[deleted]"
                comment.deleted_at = comment.deleted_at or now
            session.execute(
                schema.Comment.__table__.update()
                .where(schema.Comment.deleted_by_id == user.id)
                .values(deleted_by_id=None)
            )

            lost_pet_rows = session.scalars(
                select(schema.LostPet).options().where(schema.LostPet.user_id == user.id)
            ).all()
            for lost_pet in lost_pet_rows:
                media_urls.extend(photo.photo_url for photo in lost_pet.photos)
                media_urls.extend(photo.thumb_url for photo in lost_pet.photos)
                lost_pet.user_id = None
                lost_pet.owner_phone_number = "[deleted]"
                lost_pet.owner_telegram_username = None
                lost_pet.owner_phone_publication_consent = False
                lost_pet.additional_info = None
                lost_pet.is_public = False
                lost_pet.deleted_at = lost_pet.deleted_at or now
                for photo in lost_pet.photos:
                    photo.photo_url = f"deleted://lost-pet/{photo.id}"
                    photo.thumb_url = None

            adoption_post_rows = session.scalars(
                select(schema.AdoptionPost).where(schema.AdoptionPost.user_id == user.id)
            ).all()
            for adoption_post in adoption_post_rows:
                media_urls.extend(photo.photo_url for photo in adoption_post.photos)
                media_urls.extend(photo.thumb_url for photo in adoption_post.photos)
                adoption_post.user_id = None
                adoption_post.owner_phone_number = "[deleted]"
                adoption_post.owner_telegram_username = None
                adoption_post.owner_phone_publication_consent = False
                adoption_post.additional_info = None
                adoption_post.is_public = False
                adoption_post.deleted_at = adoption_post.deleted_at or now
                for photo in adoption_post.photos:
                    photo.photo_url = f"deleted://adoption-post/{photo.id}"
                    photo.thumb_url = None

            liked_post_counts = session.execute(
                select(schema.Like.post_id, func.count(schema.Like.id))
                .where(schema.Like.user_id == user.id)
                .group_by(schema.Like.post_id)
            ).all()
            for post_id, like_count in liked_post_counts:
                post = session.get(schema.Post, post_id)
                if post is not None:
                    post.like_count = max(0, post.like_count - int(like_count))
            session.execute(delete(schema.Like).where(schema.Like.user_id == user.id))
            session.execute(
                delete(schema.UserBlock).where(
                    or_(
                        schema.UserBlock.blocker_id == user.id,
                        schema.UserBlock.blocked_id == user.id,
                    )
                )
            )
            session.execute(
                delete(schema.LeaderboardCache).where(
                    cast(schema.LeaderboardCache.data, Text).contains(str(user.id))
                )
            )
            session.execute(
                update(schema.AuthRefreshSession)
                .where(
                    schema.AuthRefreshSession.user_id == user.id,
                    schema.AuthRefreshSession.revoked_at.is_(None),
                )
                .values(revoked_at=now)
            )
            session.execute(
                schema.Cat.__table__.update()
                .where(schema.Cat.created_by == user.id)
                .values(created_by=None)
            )
            session.execute(
                schema.Report.__table__.update()
                .where(schema.Report.reporter_id == user.id)
                .values(reporter_id=None, reason=None, metadata=None)
            )
            session.execute(
                schema.Report.__table__.update()
                .where(schema.Report.handled_by == user.id)
                .values(handled_by=None)
            )

            user_model.email = f"deleted+{user.id}@mushukistan.invalid"
            user_model.email_verified = False
            user_model.password_hash = None
            user_model.name = None
            user_model.avatar_url = None
            user_model.phone_number = None
            user_model.telegram_username = None
            user_model.preferred_language = "en"
            user_model.bio = None
            user_model.allow_public_activity_view = False
            user_model.accepted_terms_version = None
            user_model.accepted_privacy_version = None
            user_model.accepted_legal_at = None
            user_model.is_active = False
            user_model.is_moderator = False
            user_model.last_login_at = None

            current.is_active = False
            session.flush()

        self._delete_media_urls(media_urls, actor_id=user.id)

    def request_external_account_deletion(self, email: str) -> None:
        normalized_email = email.strip().casefold()
        if (
            self.account_deletion_token_service is None
            or self.account_deletion_email_sender is None
        ):
            logger.warning("account_deletion_email_not_configured")
            return

        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_email(normalized_email)
            if user is None or not user.is_active:
                return
            token = self.account_deletion_token_service.issue_token(
                user_id=user.id,
                email=user.email,
            )
            recipient = user.email

        try:
            self.account_deletion_email_sender.send_confirmation_email(
                email=recipient,
                token=token,
            )
        except Exception:  # pragma: no cover - preserves anti-enumeration behavior
            logger.warning(
                "account_deletion_email_delivery_failed",
                email_domain=recipient.rsplit("@", 1)[-1],
            )

    def confirm_external_account_deletion(self, token: str) -> None:
        if self.account_deletion_token_service is None:
            raise api_error(
                500,
                "ACCOUNT_DELETION_NOT_CONFIGURED",
                "Account deletion confirmation is not configured.",
            )

        claims = self.account_deletion_token_service.decode_token(token)
        with self.db_session_manager.session_scope() as session:
            repository = self.repository_factory(session)
            user = repository.get_by_id(claims.user_id)
            if user is None or user.email.casefold() != claims.email.casefold():
                raise api_error(
                    401,
                    "INVALID_ACCOUNT_DELETION_TOKEN",
                    "Invalid or expired account deletion token.",
                )
            if not user.is_active:
                raise api_error(
                    410,
                    "ACCOUNT_ALREADY_DELETED",
                    "This account is already deleted or inactive.",
                )

        self.delete_me(user)

    def _delete_media_urls(self, urls: list[str | None], *, actor_id: UUID) -> None:
        if self.media_storage_service is None:
            return
        for url in set(urls):
            try:
                self.media_storage_service.delete_media_url(url)
            except Exception:  # pragma: no cover
                logger.warning("account_delete_media_cleanup_failed", actor_id=str(actor_id))

    @staticmethod
    def _history_photo_urls(snapshot: dict[str, object]) -> list[str]:
        photo_urls = snapshot.get("photo_urls")
        if not isinstance(photo_urls, list):
            return []
        return [url for url in photo_urls if isinstance(url, str)]

    @staticmethod
    def _redact_post_history_snapshot(snapshot: dict[str, object]) -> dict[str, object]:
        redacted = dict(snapshot)
        if "description" in redacted:
            redacted["description"] = None
        if "location" in redacted:
            redacted["location"] = None
        if "photo_urls" in redacted:
            redacted["photo_urls"] = []
        return redacted

    def update_avatar(
        self,
        user: AuthUser,
        *,
        content: bytes,
        content_type: str | None,
        filename: str | None,
    ) -> UserProfile:
        if self.media_storage_service is None:
            raise api_error(500, "STORAGE_NOT_CONFIGURED", "Image storage is not configured.")

        try:
            media = self.media_storage_service.upload_image(
                purpose=UploadPurpose.USER_AVATAR,
                entity_id=user.id,
                content=content,
                content_type=content_type,
                original_filename=filename,
            )
        except StorageValidationError as exc:
            raise api_error(422, "INVALID_IMAGE", "Invalid image file.") from exc
        except StorageConfigurationError as exc:
            raise api_error(
                500,
                "STORAGE_NOT_CONFIGURED",
                "Image storage is not configured.",
            ) from exc
        except StorageOperationError as exc:
            raise api_error(502, "IMAGE_UPLOAD_FAILED", "Image upload failed.") from exc

        previous_avatar_url: str | None = None
        try:
            with self.db_session_manager.session_scope() as session:
                repository = self.repository_factory(session)
                current = repository.get_by_id(user.id)
                if current is None or not current.is_active:
                    raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")

                previous_avatar_url = current.avatar_url
                current.avatar_url = media.canonical.url
                updated = repository.save(current)
                profile = self._build_self_profile(repository, updated)
        except Exception:
            try:
                self.media_storage_service.delete_object(media.canonical.key)
            except Exception:  # pragma: no cover - best-effort cleanup
                logger.warning("avatar_upload_cleanup_failed", key=media.canonical.key)
            raise

        if previous_avatar_url and previous_avatar_url != media.canonical.url:
            try:
                self.media_storage_service.delete_media_url(previous_avatar_url)
            except Exception:  # pragma: no cover - best-effort cleanup
                logger.warning("previous_avatar_cleanup_failed", user_id=str(user.id))
        return profile

    def block_user(self, user: AuthUser, blocked_user_id: UUID) -> None:
        if user.id == blocked_user_id:
            raise api_error(422, "VALIDATION_ERROR", "You cannot block your own account.")
        with self.db_session_manager.session_scope() as session:
            blocked = session.get(schema.User, blocked_user_id)
            if blocked is None or not blocked.is_active:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")
            exists = session.scalar(
                select(schema.UserBlock).where(
                    schema.UserBlock.blocker_id == user.id,
                    schema.UserBlock.blocked_id == blocked_user_id,
                )
            )
            if exists is None:
                session.add(schema.UserBlock(blocker_id=user.id, blocked_id=blocked_user_id))

    def unblock_user(self, user: AuthUser, blocked_user_id: UUID) -> None:
        with self.db_session_manager.session_scope() as session:
            session.execute(
                delete(schema.UserBlock).where(
                    schema.UserBlock.blocker_id == user.id,
                    schema.UserBlock.blocked_id == blocked_user_id,
                )
            )

    def _build_self_profile(
        self,
        repository: UserProfileRepository,
        user: AuthUser,
    ) -> UserProfile:
        return UserProfile(
            id=user.id,
            email=user.email,
            name=user.name,
            avatar_url=user.avatar_url,
            phone_number=user.phone_number,
            telegram_username=user.telegram_username,
            preferred_language=user.preferred_language,
            allow_public_activity_view=user.allow_public_activity_view,
            bio=user.bio,
            registered_at=user.registered_at,
            observation_count=repository.count_observations(user.id),
            total_likes_received=repository.count_likes_received(user.id),
            comment_count=repository.count_comments(user.id),
            is_moderator=user.is_moderator,
        )
