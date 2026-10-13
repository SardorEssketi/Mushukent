from datetime import UTC, datetime

from fastapi import APIRouter

from app.core.posthog_logging import get_posthog_logger

router = APIRouter(prefix="/health")


@router.get("", summary="Health check")
def health_check() -> dict[str, object]:
    posthog_logger = get_posthog_logger()
    if posthog_logger is not None:
        posthog_logger.info("health_check_completed", extra={"component": "api"})
    return {
        "success": True,
        "data": {
            "status": "ok",
            "service": "mushukistan-backend",
            "timestamp": datetime.now(UTC).isoformat(),
        },
    }
