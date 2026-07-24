from fastapi import FastAPI

from app.api.v1.router import api_v1_router
from app.core.container import build_container
from app.core.errors import register_error_handlers
from app.core.logging import configure_logging


def create_app() -> FastAPI:
    configure_logging()

    app = FastAPI(
        title="Mushukent API",
        version="1.0.0",
        docs_url="/docs",
        redoc_url="/redoc",
    )

    app.state.container = build_container()
    register_error_handlers(app)
    app.include_router(api_v1_router, prefix="/api/v1")

    return app


app = create_app()
