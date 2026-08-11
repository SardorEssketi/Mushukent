from fastapi import APIRouter, Depends

from app.core.dependencies import get_leaderboard_service
from app.features.auth.application.schemas import ApiSuccess
from app.features.leaderboards.application.schemas import LeaderboardEntry, LeaderboardQuery
from app.features.leaderboards.application.service import LeaderboardService
from app.features.leaderboards.domain.models import LeaderboardType

router = APIRouter(prefix="/leaderboards")


@router.get(
    "/{type}",
    response_model=ApiSuccess[list[LeaderboardEntry]],
    response_model_exclude_none=True,
)
def get_leaderboard(
    type: LeaderboardType,
    query: LeaderboardQuery = Depends(),
    leaderboard_service: LeaderboardService = Depends(get_leaderboard_service),
) -> ApiSuccess[list[LeaderboardEntry]]:
    return ApiSuccess(data=leaderboard_service.get_leaderboard(type, query))
