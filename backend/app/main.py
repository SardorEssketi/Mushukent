from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from posthog import identify_context, new_context
from structlog import get_logger

from app.api.v1.router import api_v1_router
from app.core.analytics import Analytics
from app.core.container import build_container
from app.core.errors import register_error_handlers
from app.core.load_shedding import LoadSheddingMiddleware
from app.core.logging import configure_logging
from app.core.ops_metrics import (
    AlertThresholds,
    OpsAlerter,
    OpsMetricsMiddleware,
    OpsReporter,
    TelegramOpsNotifier,
)
from app.core.publication_diagnostics import PublicationDiagnosticsMiddleware
from app.core.rate_limit import add_rate_limit_middleware, client_address
from app.core.request_auth import decode_access_token_once
from app.core.upload_guard import UploadSingleFlightMiddleware, verified_user_identifier
from app.features.auth.infrastructure.tokens import JoseAccessTokenService
from app.infrastructure.storage.public_media import configure_public_media_storage

logger = get_logger(__name__)


class PostHogContextMiddleware:
    """Bind the authenticated user to the PostHog context for each request."""

    def __init__(self, app) -> None:
        self.app = app
        self._token_service: JoseAccessTokenService | None = None

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
        if self._token_service is None:
            self._token_service = JoseAccessTokenService(app.state.container.settings)
        try:
            principal = (
                decode_access_token_once(scope, self._token_service, token)
                if authorization.lower().startswith("bearer ") and token
                else None
            )
        except HTTPException:
            # Route dependencies retain responsibility for rejecting invalid credentials.
            principal = None

        # Binding the user to the analytics context is best effort; only analytics errors are
        # swallowed here, never errors raised by the application itself.
        context = None
        try:
            context = new_context()
            context.__enter__()
            if principal is not None:
                identify_context(str(principal.user_id))
        except Exception as exc:
            logger.warning("analytics_context_failed", error_type=type(exc).__name__)
        try:
            await self.app(scope, receive, send)
        finally:
            if context is not None:
                try:
                    context.__exit__(None, None, None)
                except Exception as exc:
                    logger.warning("analytics_context_failed", error_type=type(exc).__name__)


def _build_ops_reporter(settings, metrics, analytics_client) -> OpsReporter | None:
    if metrics is None:
        return None
    alerter = None
    if settings.ops_alerts_enabled:
        notifier = TelegramOpsNotifier(
            bot_token=settings.telegram_bot_token,
            chat_id=settings.telegram_ops_chat_id or settings.telegram_feedback_chat_id,
        )
        if notifier.enabled:
            thresholds = AlertThresholds(
                feed_p95_ms=settings.ops_alert_feed_p95_ms,
                map_p95_ms=settings.ops_alert_map_p95_ms,
                active_users=settings.ops_alert_active_users,
                requests_per_s=settings.ops_alert_requests_per_second,
            )
            alerter = OpsAlerter(notifier, thresholds, label=f"Mushukistan {settings.app_env}")
        else:
            logger.info("ops_alerts_disabled", reason="telegram_not_configured")
    return OpsReporter(
        metrics,
        interval_seconds=settings.ops_metrics_interval_seconds,
        analytics_client=analytics_client,
        alerter=alerter,
        release=settings.app_release or "unknown",
    )


def create_app() -> FastAPI:
    configure_logging()
    container = build_container()
    settings = container.settings

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        analytics = Analytics()
        app.state.posthog_client = analytics.start(settings)
        reporter = _build_ops_reporter(settings, container.ops_metrics, app.state.posthog_client)
        if reporter is not None:
            reporter.start()
        try:
            yield
        finally:
            if reporter is not None:
                await reporter.stop()
            analytics.stop()

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
    configure_public_media_storage(container.object_storage)
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
    # Added before CORS so its 409 carries CORS headers for the web app.
    app.add_middleware(
        UploadSingleFlightMiddleware,
        identify=verified_user_identifier(JoseAccessTokenService(settings)),
    )
    # In-flight cap: added after the upload guard (so it wraps it) and before CORS (so its 503
    # carries CORS headers).
    app.add_middleware(
        LoadSheddingMiddleware,
        max_in_flight=settings.max_in_flight_requests,
        retry_after=settings.service_busy_retry_after_seconds,
    )
    app.add_middleware(
        CORSMiddleware,
        **cors_kwargs,
        allow_credentials=False,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    app.add_middleware(PostHogContextMiddleware)
    app.add_middleware(PublicationDiagnosticsMiddleware)
    if container.ops_metrics is not None:
        # Added last, so it is the outermost layer: it also times shed (503) and limited (429)
        # requests and everything the inner middleware does.
        app.add_middleware(
            OpsMetricsMiddleware,
            metrics=container.ops_metrics,
            client_address=lambda request: client_address(request, settings),
        )
    app.include_router(api_v1_router, prefix="/api/v1")

    return app


app = create_app()
