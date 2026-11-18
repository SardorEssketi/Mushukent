import json

import psycopg
from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy.exc import DBAPIError
from sqlalchemy.exc import TimeoutError as PoolTimeoutError
from structlog import get_logger

logger = get_logger(__name__)


def _json_safe(value: object) -> object:
    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}
    if isinstance(value, list):
        return [_json_safe(item) for item in value]
    if isinstance(value, tuple):
        return [_json_safe(item) for item in value]
    if isinstance(value, set):
        return [_json_safe(item) for item in value]
    if isinstance(value, BaseException):
        return str(value)

    try:
        json.dumps(value)
        return value
    except TypeError:
        return str(value)


def _build_error_response(
    status_code: int,
    code: str,
    message: str,
    details: object | None = None,
) -> JSONResponse:
    error_payload: dict[str, object] = {
        "code": code,
        "message": message,
    }
    if details is not None:
        error_payload["details"] = details

    payload: dict[str, object] = {
        "success": False,
        "error": error_payload,
    }
    return JSONResponse(status_code=status_code, content=payload)


_BUSY_ERRORS = (
    psycopg.errors.QueryCanceled,  # statement_timeout
    psycopg.errors.LockNotAvailable,  # lock_timeout
    psycopg.errors.IdleInTransactionSessionTimeout,
)
_DEFAULT_RETRY_AFTER_SECONDS = 5


def _service_busy(request: Request, reason: str) -> JSONResponse:
    """Overload, not a bug: a short 503 the client can retry after ``Retry-After`` seconds."""
    container = getattr(request.app.state, "container", None)
    settings = getattr(container, "settings", None)
    retry_after = getattr(
        settings, "service_busy_retry_after_seconds", _DEFAULT_RETRY_AFTER_SECONDS
    )
    logger.warning("service_busy", reason=reason, method=request.method, path=request.url.path)
    response = _build_error_response(
        503,
        "SERVICE_BUSY",
        "The service is busy. Please try again shortly.",
    )
    response.headers["Retry-After"] = str(retry_after)
    return response


def register_error_handlers(app: FastAPI) -> None:
    @app.exception_handler(PoolTimeoutError)
    async def pool_timeout_handler(request: Request, _: PoolTimeoutError) -> JSONResponse:
        return _service_busy(request, "pool_timeout")

    @app.exception_handler(DBAPIError)
    async def database_error_handler(request: Request, exc: DBAPIError) -> JSONResponse:
        if isinstance(exc.orig, _BUSY_ERRORS):
            return _service_busy(request, type(exc.orig).__name__)
        # Anything else is a real failure: log it like every other unhandled exception.
        return await unhandled_exception_handler(request, exc)

    @app.exception_handler(HTTPException)
    async def http_exception_handler(_: Request, exc: HTTPException) -> JSONResponse:
        if isinstance(exc.detail, dict) and "success" in exc.detail:
            return JSONResponse(
                status_code=exc.status_code,
                content=exc.detail,
                headers=exc.headers,
            )

        message = str(exc.detail) if exc.detail else "Request failed."
        return _build_error_response(exc.status_code, "HTTP_ERROR", message)

    @app.exception_handler(RequestValidationError)
    async def validation_exception_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
        return _build_error_response(
            422,
            "VALIDATION_ERROR",
            "Validation failed.",
            details=_json_safe(exc.errors()),
        )

    @app.exception_handler(Exception)
    async def unhandled_exception_handler(request: Request, exc: Exception) -> JSONResponse:
        publication = request.url.path in {
            "/api/v1/posts",
            "/api/v1/lost-pets",
            "/api/v1/adoption-posts",
        } or request.url.path.startswith("/api/v1/publication-operations/")
        if publication:
            # SQL exceptions may embed post text/contact parameters in their repr.
            logger.error(
                "publication_unhandled_exception",
                error_type=type(exc).__name__,
                request_id=getattr(request.state, "request_id", None),
            )
        else:
            logger.error(
                "unhandled_exception",
                method=request.method,
                path=request.url.path,
                exc_info=(type(exc), exc, exc.__traceback__),
            )
        response = _build_error_response(
            500,
            "INTERNAL_SERVER_ERROR",
            "An unexpected error occurred.",
        )
        if publication and getattr(request.state, "request_id", None):
            response.headers["X-Request-ID"] = request.state.request_id
        return response
