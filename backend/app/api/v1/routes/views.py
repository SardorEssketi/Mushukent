from uuid import UUID

from fastapi import APIRouter, Depends, Header

from app.core.dependencies import get_optional_current_user, get_views_service
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.views.application.schemas import PostViewResponse
from app.features.views.application.service import ViewsService

router = APIRouter()


def _guest_id(value: str | None) -> UUID | None:
    """A guest's random per-install id; anything that is not a UUID is ignored."""
    if not value:
        return None
    try:
        return UUID(value)
    except ValueError:
        return None


@router.post("/posts/{post_id}/views", response_model=ApiSuccess[PostViewResponse])
def record_post_view(
    post_id: UUID,
    viewer_id: str | None = Header(default=None, alias="X-Viewer-Id"),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    views_service: ViewsService = Depends(get_views_service),
) -> ApiSuccess[PostViewResponse]:
    return ApiSuccess(
        data=views_service.record_post_view(post_id, current_user, _guest_id(viewer_id))
    )


@router.post("/lost-pets/{lost_pet_id}/views", response_model=ApiSuccess[PostViewResponse])
def record_lost_pet_view(
    lost_pet_id: UUID,
    viewer_id: str | None = Header(default=None, alias="X-Viewer-Id"),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    views_service: ViewsService = Depends(get_views_service),
) -> ApiSuccess[PostViewResponse]:
    return ApiSuccess(
        data=views_service.record_lost_pet_view(lost_pet_id, current_user, _guest_id(viewer_id))
    )


@router.post(
    "/adoption-posts/{adoption_post_id}/views", response_model=ApiSuccess[PostViewResponse]
)
def record_adoption_post_view(
    adoption_post_id: UUID,
    viewer_id: str | None = Header(default=None, alias="X-Viewer-Id"),
    current_user: AuthUser | None = Depends(get_optional_current_user),
    views_service: ViewsService = Depends(get_views_service),
) -> ApiSuccess[PostViewResponse]:
    return ApiSuccess(
        data=views_service.record_adoption_post_view(
            adoption_post_id, current_user, _guest_id(viewer_id)
        )
    )
