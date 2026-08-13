from fastapi import APIRouter

from db.db_functions import check_db_connection
from schemas.response_models import HealthResponse

router = APIRouter(prefix="/health", tags=["Health"])


@router.get("", response_model=HealthResponse, summary="Service health check")
async def health_check() -> HealthResponse:
    try:
        await check_db_connection()
        return HealthResponse(status="healthy")
    except Exception:
        return HealthResponse(status="unhealthy")
