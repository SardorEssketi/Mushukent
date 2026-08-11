from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import api_v1_router
from app.core.container import build_container
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging
from app.core.rate_limit import add_rate_limit_middleware


def create_app() -> FastAPI:
    configure_logging()
    container = build_container()
    settings = container.settings

    app = FastAPI(
        title=settings.app_name,
        version="1.0.0",
        debug=settings.app_debug,
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
    app.include_router(api_v1_router, prefix="/api/v1")

    return app


app = create_app()
