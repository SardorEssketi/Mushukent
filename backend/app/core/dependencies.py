from __future__ import annotations

from collections.abc import Generator

from fastapi import Depends, Header, Request
from sqlalchemy.orm import Session

from app.core.auth import AuthenticatedPrincipal
from app.core.container import AppContainer
from app.core.rbac import AuthorizationService, RoleBasedAuthorizationService
from app.core.security import api_error, get_bearer_token, get_optional_bearer_token
from app.core.storage import ObjectStorage
from app.features.adoption_posts.application.service import AdoptionPostsService
from app.features.adoption_posts.infrastructure.repositories import SqlAlchemyAdoptionPostRepository
from app.features.auth.application.service import AuthService
from app.features.auth.infrastructure.passwords import PasslibPasswordHasher
from app.features.auth.infrastructure.repositories import SqlAlchemyAuthUserRepository
from app.features.auth.infrastructure.tokens import (
    GoogleOAuthIdTokenVerifier,
    JoseAccessTokenService,
)
from app.features.cats.application.service import CatsService
from app.features.cats.infrastructure.repositories import SqlAlchemyCatRepository
from app.features.comments.application.service import CommentsService
from app.features.comments.infrastructure.repositories import SqlAlchemyCommentRepository
from app.features.feed.application.service import FeedService
from app.features.feed.infrastructure.repositories import SqlAlchemyFeedRepository
from app.features.leaderboards.application.service import LeaderboardService
from app.features.leaderboards.infrastructure.repositories import SqlAlchemyLeaderboardRepository
from app.features.likes.application.service import LikesService
from app.features.likes.infrastructure.repositories import SqlAlchemyLikeRepository
from app.features.lost_pets.application.service import LostPetsService
from app.features.lost_pets.infrastructure.repositories import SqlAlchemyLostPetRepository
from app.features.moderation.application.service import ModerationService
from app.features.places.application.service import PlacesService
from app.features.places.infrastructure.repositories import SqlAlchemyPlaceRepository
from app.features.posts.application.service import PostsService
from app.features.posts.infrastructure.repositories import SqlAlchemyPostRepository
from app.features.reports.application.service import ReportsService
from app.features.reports.infrastructure.repositories import SqlAlchemyReportRepository
from app.features.users.application.service import UsersService
from app.features.users.infrastructure.repositories import SqlAlchemyUserProfileRepository
from app.infrastructure.storage.service import MediaStorageService


def get_container(request: Request) -> AppContainer:
    return request.app.state.container


def get_db_session(request: Request) -> Generator[Session]:
    container = get_container(request)
    db = container.db_session_manager.create_session()
    try:
        yield db
    finally:
        db.close()


def get_password_hasher() -> PasslibPasswordHasher:
    return PasslibPasswordHasher()


def get_access_token_service(request: Request) -> JoseAccessTokenService:
    return JoseAccessTokenService(get_container(request).settings)


def get_google_token_verifier(request: Request) -> GoogleOAuthIdTokenVerifier:
    return GoogleOAuthIdTokenVerifier(get_container(request).settings)


def get_authorization_service() -> AuthorizationService:
    return RoleBasedAuthorizationService()


def get_auth_service(request: Request) -> AuthService:
    container = get_container(request)
    return AuthService(
        settings=container.settings,
        db_session_manager=container.db_session_manager,
        password_hasher=get_password_hasher(),
        access_token_service=JoseAccessTokenService(container.settings),
        google_token_verifier=GoogleOAuthIdTokenVerifier(container.settings),
        repository_factory=SqlAlchemyAuthUserRepository,
    )


def get_users_service(request: Request) -> UsersService:
    container = get_container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return UsersService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyUserProfileRepository,
        media_storage_service=media_storage_service,
    )


def get_cats_service(request: Request) -> CatsService:
    container = get_container(request)
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


def get_posts_service(request: Request) -> PostsService:
    container = get_container(request)
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
    )


def get_feed_service(request: Request) -> FeedService:
    container = get_container(request)
    return FeedService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyFeedRepository,
        lost_pet_repository_factory=SqlAlchemyLostPetRepository,
        adoption_post_repository_factory=SqlAlchemyAdoptionPostRepository,
    )


def get_likes_service(request: Request) -> LikesService:
    container = get_container(request)
    return LikesService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyLikeRepository,
    )


def get_comments_service(request: Request) -> CommentsService:
    container = get_container(request)
    return CommentsService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyCommentRepository,
        user_repository_factory=SqlAlchemyUserProfileRepository,
    )


def get_reports_service(request: Request) -> ReportsService:
    container = get_container(request)
    return ReportsService(
        db_session_manager=container.db_session_manager,
        report_repository_factory=SqlAlchemyReportRepository,
        post_repository_factory=SqlAlchemyPostRepository,
        comment_repository_factory=SqlAlchemyCommentRepository,
        cat_repository_factory=SqlAlchemyCatRepository,
        user_repository_factory=SqlAlchemyUserProfileRepository,
    )


def get_moderation_service(request: Request) -> ModerationService:
    return ModerationService(
        reports_service=get_reports_service(request),
        posts_service_factory=lambda: get_posts_service(request),
    )


def get_leaderboard_service(request: Request) -> LeaderboardService:
    container = get_container(request)
    return LeaderboardService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyLeaderboardRepository,
    )


def get_places_service(request: Request) -> PlacesService:
    container = get_container(request)
    return PlacesService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyPlaceRepository,
    )


def get_lost_pets_service(request: Request) -> LostPetsService:
    container = get_container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return LostPetsService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyLostPetRepository,
        media_storage_service=media_storage_service,
    )


def get_adoption_posts_service(request: Request) -> AdoptionPostsService:
    container = get_container(request)
    media_storage_service = (
        MediaStorageService(storage=container.object_storage)
        if container.object_storage is not None
        else None
    )
    return AdoptionPostsService(
        db_session_manager=container.db_session_manager,
        repository_factory=SqlAlchemyAdoptionPostRepository,
        media_storage_service=media_storage_service,
    )


def get_object_storage(request: Request) -> ObjectStorage:
    container = get_container(request)
    if container.object_storage is None:
        raise api_error(
            500,
            "STORAGE_NOT_CONFIGURED",
            "Image storage is not configured.",
        )
    return container.object_storage


def get_media_storage_service(request: Request) -> MediaStorageService:
    storage = get_object_storage(request)
    return MediaStorageService(storage=storage)


def get_current_principal(
    request: Request,
    token: str = Depends(get_bearer_token),
) -> AuthenticatedPrincipal:
    access_token_service = get_access_token_service(request)
    return access_token_service.decode_access_token(token)


def get_optional_current_principal(
    request: Request,
    authorization: str | None = Header(default=None),
) -> AuthenticatedPrincipal | None:
    token = get_optional_bearer_token(authorization)
    if token is None:
        return None
    return get_access_token_service(request).decode_access_token(token)


def get_current_user(
    request: Request,
    db: Session = Depends(get_db_session),
    principal: AuthenticatedPrincipal = Depends(get_current_principal),
):
    repository = SqlAlchemyAuthUserRepository(db)
    user = repository.get_by_id(principal.user_id)
    if user is None:
        raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")
    if not user.is_active:
        raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")
    return user


def get_optional_current_user(
    request: Request,
    db: Session = Depends(get_db_session),
    authorization: str | None = Header(default=None),
):
    principal = get_optional_current_principal(request, authorization)
    if principal is None:
        return None
    repository = SqlAlchemyAuthUserRepository(db)
    user = repository.get_by_id(principal.user_id)
    if user is None:
        raise api_error(401, "UNAUTHORIZED", "Missing or invalid Authorization header.")
    if not user.is_active:
        raise api_error(403, "ACCOUNT_DISABLED", "Account is disabled.")
    return user


def get_current_active_user(user=Depends(get_current_user)):
    return user


def require_moderator(user=Depends(get_current_user)) -> object:
    if not user.is_moderator:
        raise api_error(403, "FORBIDDEN", "You do not have permission to perform this action.")
    return user
