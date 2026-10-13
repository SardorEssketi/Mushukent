import atexit
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from posthog import Posthog, identify_context, new_context

from app.api.v1.router import api_v1_router
from app.core.container import build_container
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging
from app.core.posthog_logging import (
    configure_posthog_log_export,
    shutdown_posthog_log_export,
)
from app.core.rate_limit import add_rate_limit_middleware
from app.features.auth.infrastructure.tokens import JoseAccessTokenService


def _missing_posthog_setting_error(setting_name: str) -> RuntimeError:
    return RuntimeError(
        f"{setting_name} variable required by PostHog is missing or un-configured, "
        f"this causes events to be silently missed. This error stops appearing once "
        f"{setting_name} is configured"
    )


class PostHogContextMiddleware:
    """Bind the authenticated user to the PostHog context for each request."""

    def __init__(self, app) -> None:
        self.app = app

    async def __call__(self, scope, receive, send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        app = scope["app"]
        posthog_client = getattr(app.state, "posthog_client", None)
        if posthog_client is None:
            await self.app(scope, receive, send)
            return

        authorization = dict(scope.get("headers", [])).get(b"authorization", b"").decode("latin-1")
        _, _, token = authorization.partition(" ")
        try:
            principal = (
                JoseAccessTokenService(app.state.container.settings).decode_access_token(token)
                if authorization.lower().startswith("bearer ") and token
                else None
            )
        except HTTPException:
            # Route dependencies retain responsibility for rejecting invalid credentials.
            principal = None

        with new_context():
            if principal is not None:
                identify_context(str(principal.user_id))
            await self.app(scope, receive, send)


def create_app() -> FastAPI:
    configure_logging()
    container = build_container()
    settings = container.settings

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        posthog_client: Posthog | None = None
        posthog_logger = None
        if settings.posthog_project_token and settings.posthog_host:
            posthog_client = Posthog(
                project_api_key=settings.posthog_project_token,
                host=settings.posthog_host,
                enable_exception_autocapture=True,
            )
            atexit.register(posthog_client.shutdown)
            posthog_logger = configure_posthog_log_export(
                settings.posthog_project_token,
                settings.posthog_host,
            )
            posthog_logger.info("posthog_log_export_started", extra={"component": "api"})
        elif settings.app_debug or not settings.is_production_like:
            missing_setting = (
                "POSTHOG_PROJECT_TOKEN"
                if not settings.posthog_project_token
                else "POSTHOG_HOST"
            )
            raise _missing_posthog_setting_error(missing_setting)

        app.state.posthog_client = posthog_client
        yield

        if posthog_logger is not None:
            posthog_logger.info("posthog_log_export_stopping", extra={"component": "api"})
            shutdown_posthog_log_export()
        if posthog_client is not None:
            posthog_client.flush()

    app = FastAPI(
        title=settings.app_name,
        version="1.0.0",
        debug=settings.app_debug,
        lifespan=lifespan,
        docs_url="/docs" if settings.enable_api_docs or not settings.is_production_like else None,
        redoc_url="/redoc" if settings.enable_api_docs or not settings.is_production_like else None,
        openapi_url=(
            "/openapi.json" if settings.enable_api_docs or not settings.is_production_like else None
        ),
    )

    app.state.container = container
    add_rate_limit_middleware(app, settings=settings)
    object_storage = getattr(container, "object_storage", None)
    media_root = getattr(object_storage, "root_dir", None)
    if media_root is not None:
        app.mount("/media", StaticFiles(directory=str(media_root)), name="media")
    register_error_handlers(app)
    cors_kwargs: dict[str, object]
    if settings.is_production_like:
        cors_kwargs = {"allow_origins": settings.allowed_cors_origins}
    else:
        cors_kwargs = {
            "allow_origin_regex": (
                r"^https?://"
                r"(localhost|127\.0\.0\.1|10\.0\.2\.2|192\.168\.\d{1,3}\.\d{1,3})"
                r"(:\d+)?$"
            )
        }
    app.add_middleware(
        CORSMiddleware,
        **cors_kwargs,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(PostHogContextMiddleware)
    app.include_router(api_v1_router, prefix="/api/v1")

    return app


app = create_app()
