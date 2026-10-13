from fastapi import APIRouter, BackgroundTasks, Depends, status

from app.core.dependencies import get_current_active_user, get_feedback_service
from app.features.auth.application.schemas import ApiSuccess
from app.features.auth.domain.models import AuthUser
from app.features.feedback.application.schemas import FeedbackCreate, FeedbackResponse
from app.features.feedback.application.service import FeedbackService

router = APIRouter()


@router.post(
    "/feedback",
    response_model=ApiSuccess[FeedbackResponse],
    status_code=status.HTTP_201_CREATED,
)
def create_feedback(
    payload: FeedbackCreate,
    background_tasks: BackgroundTasks,
    current_user: AuthUser = Depends(get_current_active_user),
    feedback_service: FeedbackService = Depends(get_feedback_service),
) -> ApiSuccess[FeedbackResponse]:
    response, notification = feedback_service.submit(current_user, payload)
    # Runs after the response is sent, so Telegram latency/outages cannot affect it.
    background_tasks.add_task(feedback_service.notify, notification)
    return ApiSuccess(data=response)
