from __future__ import annotations

from datetime import UTC, datetime
from typing import Protocol
from uuid import UUID

from structlog import get_logger

from app.core.security import api_error
from app.features.adoption_posts.domain.repositories import AdoptionPostRepository
from app.features.auth.domain.models import AuthUser
from app.features.cats.domain.repositories import CatRepository
from app.features.comments.domain.repositories import CommentRepository
from app.features.lost_pets.domain.repositories import LostPetRepository
from app.features.posts.domain.models import PostDetailRecord
from app.features.posts.domain.repositories import PostRepository
from app.features.reports.application.schemas import (
    GenericListResponse,
    ReportCreate,
    ReportHandleRequest,
    ReportListQuery,
    ReportResponse,
    to_report_page_response,
    to_report_response,
)
from app.features.reports.domain.models import (
    ReportAction,
    ReportCreateDraft,
    ReportRecord,
    ReportStatus,
    ReportTargetPreview,
    ReportTargetType,
)
from app.features.reports.domain.repositories import ReportRepository
from app.features.users.domain.repositories import UserProfileRepository
from app.infrastructure.db.session import DatabaseSessionManager

logger = get_logger(__name__)


class ReportRepositoryFactory(Protocol):
    def __call__(self, session) -> ReportRepository: ...


class PostRepositoryFactory(Protocol):
    def __call__(self, session) -> PostRepository: ...


class CommentRepositoryFactory(Protocol):
    def __call__(self, session) -> CommentRepository: ...


class CatRepositoryFactory(Protocol):
    def __call__(self, session) -> CatRepository: ...


class LostPetRepositoryFactory(Protocol):
    def __call__(self, session) -> LostPetRepository: ...


class AdoptionPostRepositoryFactory(Protocol):
    def __call__(self, session) -> AdoptionPostRepository: ...


class UserProfileRepositoryFactory(Protocol):
    def __call__(self, session) -> UserProfileRepository: ...


class ReportsService:
    def __init__(
        self,
        *,
        db_session_manager: DatabaseSessionManager,
        report_repository_factory: ReportRepositoryFactory,
        post_repository_factory: PostRepositoryFactory,
        comment_repository_factory: CommentRepositoryFactory,
        cat_repository_factory: CatRepositoryFactory,
        lost_pet_repository_factory: LostPetRepositoryFactory,
        adoption_post_repository_factory: AdoptionPostRepositoryFactory,
        user_repository_factory: UserProfileRepositoryFactory,
    ) -> None:
        self.db_session_manager = db_session_manager
        self.report_repository_factory = report_repository_factory
        self.post_repository_factory = post_repository_factory
        self.comment_repository_factory = comment_repository_factory
        self.cat_repository_factory = cat_repository_factory
        self.lost_pet_repository_factory = lost_pet_repository_factory
        self.adoption_post_repository_factory = adoption_post_repository_factory
        self.user_repository_factory = user_repository_factory

    def create_report(self, user: AuthUser, payload: ReportCreate) -> ReportResponse:
        with self.db_session_manager.session_scope() as session:
            report_repository = self.report_repository_factory(session)
            target = self._resolve_target(
                session=session,
                user=user,
                target_type=payload.target_type,
                target_id=payload.target_id,
            )

            duplicate = report_repository.find_open_duplicate(
                reporter_id=user.id,
                target_type=payload.target_type,
                target_id=payload.target_id,
            )
            if duplicate is not None:
                logger.info(
                    "report_duplicate",
                    report_id=str(duplicate.id),
                    reporter_id=str(user.id),
                    target_type=payload.target_type.value,
                    target_id=str(payload.target_id),
                )
                return to_report_response(duplicate, target=target)

            created = report_repository.create(
                ReportCreateDraft(
                    reporter_id=user.id,
                    target_type=payload.target_type,
                    target_id=payload.target_id,
                    reason=payload.reason.strip() if payload.reason is not None else None,
                    metadata=(
                        payload.metadata.model_dump(exclude_none=True)
                        if payload.metadata is not None
                        else None
                    ),
                )
            )
            logger.info(
                "report_created",
                report_id=str(created.id),
                reporter_id=str(user.id),
                target_type=payload.target_type.value,
                target_id=str(payload.target_id),
            )
            return to_report_response(created, target=target)

    def list_reports(
        self,
        query: ReportListQuery,
        *,
        user: AuthUser,
    ) -> GenericListResponse[ReportResponse]:
        with self.db_session_manager.session_scope() as session:
            report_repository = self.report_repository_factory(session)
            try:
                page = report_repository.list_reports(
                    status=query.status,
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

            target_map = self._load_target_previews(session, page.items, current_user=user)
            return to_report_page_response(page, target_by_report_id=target_map)

    def handle_report(
        self,
        report_id: UUID,
        user: AuthUser,
        payload: ReportHandleRequest,
    ) -> ReportResponse:
        with self.db_session_manager.session_scope() as session:
            report_repository = self.report_repository_factory(session)
            report = report_repository.get_by_id(report_id, for_update=True)
            if report is None:
                raise api_error(404, "REPORT_NOT_FOUND", "Report not found.")
            if report.status != ReportStatus.OPEN:
                raise api_error(
                    409,
                    "REPORT_ALREADY_HANDLED",
                    "Report has already been handled.",
                )

            target = self._resolve_target(
                session=session,
                user=user,
                target_type=report.target_type,
                target_id=report.target_id,
                allow_missing=True,
            )

            self._apply_moderation_action(
                session, user, report.target_type, report.target_id, payload
            )
            handled = report_repository.resolve(
                report.id,
                status=payload.status,
                handled_by=user.id,
                handled_at=datetime.now(UTC),
            )
            if handled is None:
                raise api_error(404, "REPORT_NOT_FOUND", "Report not found.")

            logger.info(
                "report_handled",
                report_id=str(report_id),
                actor_id=str(user.id),
                target_type=report.target_type.value,
                target_id=str(report.target_id),
                action=(payload.action.value if payload.action is not None else None),
                status=payload.status.value,
            )
            return to_report_response(handled, target=target)

    def _apply_moderation_action(
        self,
        session,
        user: AuthUser,
        target_type: ReportTargetType,
        target_id: UUID,
        payload,
    ) -> None:
        if payload.action is None:
            return

        if payload.action == ReportAction.SOFT_DELETE_POST:
            if target_type != ReportTargetType.POST:
                raise api_error(400, "INVALID_PAYLOAD", "Action does not match report target.")
            post_repository = self.post_repository_factory(session)
            post = post_repository.get_by_id(
                target_id, include_deleted=True, viewer_user_id=user.id
            )
            if post is not None and post.deleted_at is None:
                if post_repository.mark_deleted(
                    target_id, deleted_at=datetime.now(UTC), deleted_by=user.id
                ):
                    stats = post_repository.recalculate_cat_stats(post.cat_id)
                    cat_repository = self.cat_repository_factory(session)
                    cat = cat_repository.get_by_id(post.cat.id)
                    if cat is not None:
                        cat.first_seen_at = stats.first_seen_at
                        cat.last_seen_at = stats.last_seen_at
                        cat.total_observations = stats.total_observations
                        cat.total_contributors = stats.total_contributors
                        cat.total_likes = stats.total_likes
                        cat_repository.save(cat)
            return

        if payload.action == ReportAction.SOFT_DELETE_COMMENT:
            if target_type != ReportTargetType.COMMENT:
                raise api_error(400, "INVALID_PAYLOAD", "Action does not match report target.")
            comment_repository = self.comment_repository_factory(session)
            current = comment_repository.get_by_id(target_id, include_deleted=True)
            if current is not None and current.deleted_at is None:
                if comment_repository.mark_deleted(target_id, deleted_at=datetime.now(UTC)):
                    if current.post_id is not None:
                        post_repository = self.post_repository_factory(session)
                        post = post_repository.get_by_id(
                            current.post_id,
                            include_deleted=True,
                            viewer_user_id=user.id,
                        )
                        if post is not None:
                            comment_repository.decrement_post_comment_count(post.id)
                    elif current.lost_pet_id is not None:
                        comment_repository.decrement_lost_pet_comment_count(current.lost_pet_id)
                    elif current.adoption_post_id is not None:
                        comment_repository.decrement_adoption_post_comment_count(
                            current.adoption_post_id
                        )
            return

        if payload.action == ReportAction.SUSPEND_USER:
            if target_type != ReportTargetType.USER:
                raise api_error(400, "INVALID_PAYLOAD", "Action does not match report target.")
            user_repository = self.user_repository_factory(session)
            target_user = user_repository.get_by_id(target_id)
            if target_user is not None and target_user.is_active:
                target_user.is_active = False
                user_repository.save(target_user)
            return

        raise api_error(400, "INVALID_PAYLOAD", "Unsupported moderation action.")

    def _load_target_previews(
        self,
        session,
        reports: list[ReportRecord],
        *,
        current_user: AuthUser | None,
    ) -> dict[UUID, ReportTargetPreview | None]:
        previews: dict[UUID, ReportTargetPreview | None] = {}
        for report in reports:
            try:
                previews[report.id] = self._resolve_target(
                    session=session,
                    user=current_user,
                    target_type=report.target_type,
                    target_id=report.target_id,
                    allow_missing=True,
                )
            except Exception:
                previews[report.id] = None
        return previews

    def _resolve_target(
        self,
        *,
        session,
        user: AuthUser | None,
        target_type: ReportTargetType,
        target_id: UUID,
        allow_missing: bool = False,
    ) -> ReportTargetPreview | None:
        post_repository = self.post_repository_factory(session)
        comment_repository = self.comment_repository_factory(session)
        cat_repository = self.cat_repository_factory(session)
        lost_pet_repository = self.lost_pet_repository_factory(session)
        adoption_post_repository = self.adoption_post_repository_factory(session)
        user_repository = self.user_repository_factory(session)

        if target_type == ReportTargetType.POST:
            target = post_repository.get_by_id(
                target_id,
                include_deleted=True,
                viewer_user_id=user.id if user is not None else None,
            )
            if target is None:
                if allow_missing:
                    return None
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")
            if not allow_missing and (
                target.deleted_at is not None or not self._can_view_post(target, user)
            ):
                raise api_error(404, "POST_NOT_FOUND", "Post not found.")
            return ReportTargetPreview(
                id=target.id,
                target_type=target_type,
                title=target.description[:120] if target.description else None,
                subtitle=target.author.name if target.author is not None else None,
                status=target.status.value if target.status is not None else None,
                is_public=target.is_public,
                is_active=target.deleted_at is None,
                deleted_at=target.deleted_at,
            )

        if target_type == ReportTargetType.COMMENT:
            comment = comment_repository.get_by_id(target_id, include_deleted=True)
            if comment is None:
                if allow_missing:
                    return None
                raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")
            if comment.deleted_at is not None and not allow_missing:
                raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")
            if comment.post_id is not None:
                post = post_repository.get_by_id(
                    comment.post_id,
                    include_deleted=True,
                    viewer_user_id=user.id if user is not None else None,
                )
                if post is None:
                    if allow_missing:
                        return None
                    raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")
                if not allow_missing and not self._can_view_post(post, user):
                    raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")
                subtitle = f"post:{comment.post_id}"
                is_public = post.is_public
            elif comment.lost_pet_id is not None:
                if not allow_missing and not comment_repository.lost_pet_exists(
                    comment.lost_pet_id
                ):
                    raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")
                subtitle = f"lost_pet:{comment.lost_pet_id}"
                is_public = True
            elif comment.adoption_post_id is not None:
                if not allow_missing and not comment_repository.adoption_post_exists(
                    comment.adoption_post_id
                ):
                    raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")
                subtitle = f"adoption_post:{comment.adoption_post_id}"
                is_public = True
            else:
                if allow_missing:
                    return None
                raise api_error(404, "COMMENT_NOT_FOUND", "Comment not found.")
            return ReportTargetPreview(
                id=comment.id,
                target_type=target_type,
                title=comment.content[:120],
                subtitle=subtitle,
                status=None,
                is_public=is_public,
                is_active=comment.deleted_at is None,
                deleted_at=comment.deleted_at,
            )

        if target_type == ReportTargetType.USER:
            target_user = user_repository.get_by_id(target_id)
            if target_user is None:
                if allow_missing:
                    return None
                raise api_error(404, "USER_NOT_FOUND", "User not found.")
            if not allow_missing and not target_user.is_active:
                raise api_error(404, "USER_NOT_FOUND", "User not found.")
            return ReportTargetPreview(
                id=target_user.id,
                target_type=target_type,
                title=target_user.name,
                subtitle=target_user.avatar_url,
                status=None,
                is_public=True,
                is_active=target_user.is_active,
                deleted_at=None,
            )

        if target_type == ReportTargetType.CAT:
            target_cat = cat_repository.get_by_id(target_id)
            if target_cat is None:
                if allow_missing:
                    return None
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")
            if not allow_missing and (
                target_cat.deleted_at is not None
                or not target_cat.is_active
                or target_cat.merged_into is not None
            ):
                raise api_error(404, "CAT_NOT_FOUND", "Cat not found.")
            return ReportTargetPreview(
                id=target_cat.id,
                target_type=target_type,
                title=target_cat.name,
                subtitle=target_cat.cover_photo_url,
                status=target_cat.status.value,
                is_public=None,
                is_active=target_cat.is_active,
                deleted_at=target_cat.deleted_at,
            )

        if target_type == ReportTargetType.LOST_PET:
            lost_pet = lost_pet_repository.get_by_id(target_id)
            if lost_pet is None:
                if allow_missing:
                    return None
                raise api_error(404, "LOST_PET_NOT_FOUND", "Lost pet post not found.")
            return ReportTargetPreview(
                id=lost_pet.id,
                target_type=target_type,
                title=lost_pet.pet_name,
                subtitle=lost_pet.additional_info[:120] if lost_pet.additional_info else None,
                status="resolved" if lost_pet.is_resolved else None,
                is_public=lost_pet.is_public,
                is_active=lost_pet.deleted_at is None,
                deleted_at=lost_pet.deleted_at,
            )

        if target_type == ReportTargetType.ADOPTION_POST:
            adoption_post = adoption_post_repository.get_by_id(target_id)
            if adoption_post is None:
                if allow_missing:
                    return None
                raise api_error(
                    404, "ADOPTION_POST_NOT_FOUND", "Adoption post not found."
                )
            return ReportTargetPreview(
                id=adoption_post.id,
                target_type=target_type,
                title=adoption_post.pet_name,
                subtitle=(
                    adoption_post.additional_info[:120]
                    if adoption_post.additional_info
                    else None
                ),
                status=None,
                is_public=adoption_post.is_public,
                is_active=adoption_post.deleted_at is None,
                deleted_at=adoption_post.deleted_at,
            )

        if allow_missing:
            return None
        raise api_error(400, "INVALID_PAYLOAD", "Unsupported report target type.")

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
