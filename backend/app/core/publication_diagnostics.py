from time import perf_counter
from uuid import UUID, uuid4

from structlog import get_logger
from structlog.contextvars import bind_contextvars, reset_contextvars

logger = get_logger(__name__)


class PublicationDiagnosticsMiddleware:
    """Correlate publication traffic without logging headers, bodies or user identities."""

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        path = scope.get("path", "")
        if scope["type"] != "http" or not (
            (
                scope.get("method") == "POST"
                and path in {"/api/v1/posts", "/api/v1/lost-pets", "/api/v1/adoption-posts"}
            )
            or path.startswith("/api/v1/publication-operations/")
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

        async def correlated_send(message):
            nonlocal status
            if message["type"] == "http.response.start":
                status = message["status"]
                message["headers"] = [
                    *message.get("headers", []),
                    (b"x-request-id", request_id.encode("ascii")),
                ]
            await send(message)

        tokens = bind_contextvars(request_id=request_id)
        try:
            await self.app(scope, receive, correlated_send)
        finally:
            logger.info(
                "publication_request_finished",
                request_id=request_id,
                method=scope["method"],
                route="status" if "publication-operations" in path else path,
                status=status,
                duration_ms=round((perf_counter() - started) * 1000),
            )
            reset_contextvars(**tokens)
