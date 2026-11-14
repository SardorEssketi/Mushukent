from __future__ import annotations

from collections.abc import Generator

from fastapi import Depends, Header, Request
from sqlalchemy.orm import Session

from app.core.auth import AuthenticatedPrincipal
from app.core.container import AppContainer
from app.core.rbac import AuthorizationService, RoleBasedAuthorizationService
from app.core.request_auth import decode_access_token_once
from app.core.security import api_error, get_bearer_token, get_optional_bearer_token
from app.core.storage import ObjectStorage
from app.features.adoption_posts.application.service import AdoptionPostsService
from app.features.adoption_posts.infrastructure.repositories import SqlAlchemyAdoptionPostRepository
from app.features.auth.application.service import AuthService
from app.features.auth.infrastructure.email import AccountDeletionConfirmationSender
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.repositories import SqlAlchemyAuthUserRepository
from app.features.auth.infrastructure.tokens import (
    GoogleOAuthIdTokenVerifier,
    JoseAccessTokenService,
    JoseAccountDeletionTokenService,
)
from app.features.cats.application.service import CatsService
from app.features.cats.infrastructure.repositories import SqlAlchemyCatRepository
from app.features.comments.application.service import CommentsService
from app.features.comments.infrastructure.repositories import SqlAlchemyCommentRepository
from app.features.feed.application.service import FeedService
from app.features.feed.infrastructure.repositories import SqlAlchemyFeedRepository
from app.features.feedback.application.service import FeedbackService
from app.features.feedback.infrastructure.repository import SqlAlchemyFeedbackRepository
from app.features.feedback.infrastructure.telegram import TelegramFeedbackNotifier
from app.features.leaderboards.application.service import LeaderboardService
from app.features.leaderboards.infrastructure.repositories import SqlAlchemyLeaderboardRepository
from app.features.likes.application.service import LikesService
from app.features.likes.infrastructure.repositories import SqlAlchemyLikeRepository
from app.features.lost_pets.application.service import LostPetsService
from app.features.lost_pets.infrastructure.repositories import SqlAlchemyLostPetRepository
from app.features.moderation.application.service import ModerationService
from app.features.notifications.application.service import NotificationService
from app.features.notifications.infrastructure.repository import NotificationRepository
from app.features.places.application.service import PlacesService
from app.features.places.infrastructure.repositories import SqlAlchemyPlaceRepository
from app.features.posts.application.service import PostsService
from app.features.posts.infrastructure.repositories import SqlAlchemyPostRepository
from app.features.reports.application.service import ReportsService
from app.features.reports.infrastructure.repositories import SqlAlchemyReportRepository
from app.features.users.application.service import UsersService
from app.features.users.infrastructure.repositories import SqlAlchemyUserProfileRepository
from app.features.views.application.service import ViewsService
from app.features.views.infrastructure.repositories import SqlAlchemyPostViewRepository
from app.infrastructure.storage.service import MediaStorageService

# Providers that only build objects from the container or check a flag do no I/O, so they are
# ``async``: FastAPI then runs them on the event loop instead of a thread-pool round trip each
# (load audit step 2: thread-pool hand-offs were ~20% of the API's CPU). Providers that touch the
# database (sessions, user lookups) and the auth/Google services stay synchronous. Providers reused
# by other providers call the private synchronous builders below.


def _container(request: Request) -> AppContainer:
    return request.app.state.container


def _access_token_service(request: Request) -> JoseAccessTokenService:
    return JoseAccessTokenService(_container(request).settings)


async def get_container(request: Request) -> AppContainer:
    return _container(request)


def get_db_session(request: Request) -> Generator[Session]:
    container = _container(request)
    db = container.db_session_manager.create_session()
    try:
        yield db
    finally:
        db.close()


async def get_password_hasher() -> PasslibPasswordHasher:
    return PasslibPasswordHasher()


async def get_access_token_service(request: Request) -> JoseAccessTokenService:
    return _access_token_service(request)


def get_google_token_verifier(request: Request) -> GoogleOAuthIdTokenVerifier:
    return GoogleOAuthIdTokenVerifier(_container(request).settings)


async def get_authorization_service() -> AuthorizationService:
    return RoleBasedAuthorizationService()


def get_auth_service(request: Request) -> AuthService:
    container = _container(request)
    return AuthService(
        settings=container.settings,
        db_session_manager=container.db_session_manager,
        password_hasher=PasslibPasswordHasher(),
        access_token_service=JoseAccessTokenService(container.settings),
        google_token_verifier=GoogleOAuthIdTokenVerifier(container.settings),
        repository_factory=SqlAlchemyAuthUserRepository,
    )


async def get_users_service(request: Request) -> UsersService:
    container = _container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return UsersService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyUserProfileRepository,
        media_storage_service=media_storage_service,
        account_deletion_token_service=JoseAccountDeletionTokenService(container.settings),
        account_deletion_email_sender=AccountDeletionConfirmationSender(container.settings),
    )


async def get_cats_service(request: Request) -> CatsService:
    container = _container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return CatsService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyCatRepository,
        media_storage_service=media_storage_service,
    )


def _posts_service(request: Request) -> PostsService:
    container = _container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return PostsService(
        db_session_manager=container.db_session_manager,
        post_repository_factory=SqlAlchemyPostRepository,
        cat_repository_factory=SqlAlchemyCatRepository,
        user_repository_factory=SqlAlchemyUserProfileRepository,
        media_storage_service=media_storage_service,
        notification_repository_factory=NotificationRepository,
    )


async def get_posts_service(request: Request) -> PostsService:
    return _posts_service(request)


async def get_feed_service(request: Request) -> FeedService:
    container = _container(request)
    return FeedService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyFeedRepository,
        lost_pet_repository_factory=SqlAlchemyLostPetRepository,
        adoption_post_repository_factory=SqlAlchemyAdoptionPostRepository,
    )


async def get_likes_service(request: Request) -> LikesService:
    container = _container(request)
    return LikesService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyLikeRepository,
    )


async def get_views_service(request: Request) -> ViewsService:
    container = _container(request)
    return ViewsService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyPostViewRepository,
        post_repository_factory=SqlAlchemyPostRepository,
        lost_pet_repository_factory=SqlAlchemyLostPetRepository,
        adoption_post_repository_factory=SqlAlchemyAdoptionPostRepository,
        guest_key_secret=container.settings.jwt_secret_key,
    )


async def get_comments_service(request: Request) -> CommentsService:
    container = _container(request)
    return CommentsService(
        settings=container.settings,
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyCommentRepository,
        user_repository_factory=SqlAlchemyUserProfileRepository,
        notification_repository_factory=NotificationRepository,
    )


def _reports_service(request: Request) -> ReportsService:
    container = _container(request)
    return ReportsService(
        db_session_manager=container.db_session_manager,
        report_repository_factory=SqlAlchemyReportRepository,
        post_repository_factory=SqlAlchemyPostRepository,
        comment_repository_factory=SqlAlchemyCommentRepository,
        cat_repository_factory=SqlAlchemyCatRepository,
        lost_pet_repository_factory=SqlAlchemyLostPetRepository,
        adoption_post_repository_factory=SqlAlchemyAdoptionPostRepository,
        user_repository_factory=SqlAlchemyUserProfileRepository,
        notification_repository_factory=NotificationRepository,
    )


async def get_reports_service(request: Request) -> ReportsService:
    return _reports_service(request)


async def get_feedback_service(request: Request) -> FeedbackService:
    container = _container(request)
    settings = container.settings
    return FeedbackService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyFeedbackRepository,
        notifier=TelegramFeedbackNotifier(
            bot_token=settings.telegram_bot_token,
            chat_id=settings.telegram_feedback_chat_id,
        ),
        max_per_hour=settings.feedback_rate_limit_per_hour,
    )


async def get_moderation_service(request: Request) -> ModerationService:
    return ModerationService(
        reports_service=_reports_service(request),
        posts_service_factory=lambda: _posts_service(request),
    )


async def get_leaderboard_service(request: Request) -> LeaderboardService:
    container = _container(request)
    return LeaderboardService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyLeaderboardRepository,
    )


async def get_places_service(request: Request) -> PlacesService:
    container = _container(request)
    return PlacesService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyPlaceRepository,
    )


async def get_lost_pets_service(request: Request) -> LostPetsService:
    container = _container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return LostPetsService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyLostPetRepository,
        media_storage_service=media_storage_service,
        notification_repository_factory=NotificationRepository,
    )


async def get_adoption_posts_service(request: Request) -> AdoptionPostsService:
    container = _container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return AdoptionPostsService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyAdoptionPostRepository,
        media_storage_service=media_storage_service,
        notification_repository_factory=NotificationRepository,
    )


async def get_notification_service(request: Request) -> NotificationService:
    container = _container(request)
    return NotificationService(container.db_session_manager, container.settings)


def _object_storage(request: Request) -> ObjectStorage:
    container = _container(request)
    if container.object_storage is None:
        raise api_error(
            500,
            "STORAGE_NOT_CONFIGURED",
            "Image storage is not configured.",
        )
    return container.object_storage


async def get_object_storage(request: Request) -> ObjectStorage:
    return _object_storage(request)


async def get_media_storage_service(request: Request) -> MediaStorageService:
    storage = _object_storage(request)
    return MediaStorageService(storage=storage)


async def get_current_principal(
    request: Request,
    token: str = Depends(get_bearer_token),
) -> AuthenticatedPrincipal:
    return decode_access_token_once(request.scope, _access_token_service(request), token)


def get_optional_current_principal(
    request: Request,
    authorization: str | None = Header(default=None),
) -> AuthenticatedPrincipal | None:
    token = get_optional_bearer_token(authorization)
    if token is None:
        return None
    return decode_access_token_once(request.scope, _access_token_service(request), token)


def get_current_user(
    request: Request,
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
):
    # The repository returns a detached AuthUser value. Release the connection
    # before parsing bodies, waiting for the upload limiter, or calling storage.
    with _container(request).db_session_manager.create_session() as db:
        user = SqlAlchemyAuthUserRepository(db).get_by_id(principal.user_id)
    if user is None:
        raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")
    if not user.is_active:
        raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")
    return user


def get_optional_current_user(
    request: Request,
    authorization: str | None = Header(default=None),
):
    principal = get_optional_current_principal(request, authorization)
    if principal is None:
        return None
    with _container(request).db_session_manager.create_session() as db:
        user = SqlAlchemyAuthUserRepository(db).get_by_id(principal.user_id)
    if user is None:
        raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")
    if not user.is_active:
        raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")
    return user


async def get_current_active_user(user=Depends(get_current_user)):
    return user


async def require_moderator(user=Depends(get_current_user)) -> object:
    if not user.is_moderator:
        raise api_error(403, "FORBIDDEN", "You do not have permission to perform this action.")
    return user
