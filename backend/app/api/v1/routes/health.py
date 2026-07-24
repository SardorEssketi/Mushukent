from datetime import UTC, datetime

from fastapi import APIRouter

router = APIRouter(prefix="/health")


@router.get("", summary="Health check")
def health_check() -> dict[str, object]:
    return {
        "success": True,
        "data": {
            "status": "ok",
            "service": "mushukent-backend",
            "timestamp": datetime.now(UTC).isoformat(),
        },
    }
