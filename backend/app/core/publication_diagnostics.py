from time import perf_counter
from uuid import UUID, uuid4

from starlette.responses import JSONResponse
from structlog import get_logger
from structlog.contextvars import bind_contextvars, reset_contextvars

logger = get_logger(__name__)


class PublicationResponseAborted(RuntimeError):
    """Safe replacement when a failed response has already started."""


class PublicationDiagnosticsMiddleware:
    """Correlate publication traffic without logging headers, bodies or user identities."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        path = scope.get("path", "")
        bases = {"/api/v1/posts", "/api/v1/lost-pets", "/api/v1/adoption-posts"}
        update = scope.get("method") == "PATCH" and any(
            path.startswith(base + "/") and "/" not in path[len(base) + 1 :] for base in bases
        )
        if scope["type"] != "http" or not (
            (scope.get("method") == "POST" and path in bases)
            or path.startswith("/api/v1/publication-operations/")
            or update
        ):
            return await self.app(scope, receive, send)
        headers = dict(scope.get("headers", []))
        try:
            request_id = str(UUID(headers.get(b"x-request-id", b"").decode("ascii")))
        except (ValueError, UnicodeError):
            request_id = str(uuid4())
        scope.setdefault("state", {})["request_id"] = request_id
        started = perf_counter()
        status = 500
        response_started = False

        async def correlated_send(message):
            nonlocal status, response_started
            if message["type"] == "http.response.start":
                response_started = True
                status = message["status"]
                message["headers"] = [
                    *message.get("headers", []),
                    (b"x-request-id", request_id.encode("ascii")),
                ]
            await send(message)

        tokens = bind_contextvars(request_id=request_id)
        try:
            await self.app(scope, receive, correlated_send)
        except Exception as exc:
            # Starlette's outer ServerErrorMiddleware re-raises unhandled exceptions
            # after returning 500, allowing Uvicorn to print their private messages.
            # Handle only the publication boundary here; never log repr/traceback.
            logger.error(
                "publication_unhandled_exception",
                error_type=type(exc).__name__,
                request_id=request_id,
            )
            if response_started:
                raise PublicationResponseAborted(
                    f"Publication response aborted; request_id={request_id}"
                ) from None
            response = JSONResponse(
                status_code=500,
                content={
                    "success": False,
                    "error": {
                        "code": "INTERNAL_SERVER_ERROR",
                        "message": "An unexpected error occurred.",
                    },
                },
            )
            await response(scope, receive, correlated_send)
        finally:
            logger.info(
                "publication_request_finished",
                request_id=request_id,
                method=scope["method"],
                route=(
                    "status" if "publication-operations" in path else "update" if update else path
                ),
                status=status,
                duration_ms=round((perf_counter() - started) * 1000),
            )
            reset_contextvars(**tokens)
