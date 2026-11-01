from uuid import UUID

from fastapi import APIRouter, Depends, Request

from app.core.dependencies import get_current_active_user
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.infrastructure.publication_operations import PublicationOperations

router = APIRouter(prefix="/publication-operations")


@router.get("/{key}")
def publication_status(
    key: UUID, request: Request, user: AuthUser = Depends(get_current_active_user)
):
    operations = PublicationOperations(request.app.state.container.db_session_manager)
    return ApiSuccess(data=operations.status(user.id, key))
