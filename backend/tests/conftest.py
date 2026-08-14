from __future__ import annotations

import os
from collections.abc import Iterator
from uuid import uuid4

import pytest
from sqlalchemy import create_engine, text
from sqlalchemy.engine import Engine
from sqlalchemy.orm import Session, sessionmaker

from app.infrastructure.db.models import schema
from app.infrastructure.db.session import DatabaseSessionManager

os.environ["APP_ENV"] = "development"


def _integration_enabled() -> bool:
    return os.getenv("RUN_DB_INTEGRATION_TESTS") == "1"


def _database_url() -> str | None:
    return os.getenv("TEST_DATABASE_URL") or os.getenv("DATABASE_URL")


@pytest.fixture(scope="session")
def integration_database_url() -> str:
    if not _integration_enabled():
        pytest.skip("Set RUN_DB_INTEGRATION_TESTS=1 to enable live database tests.")

    database_url = _database_url()
    if not database_url:
        pytest.skip("Set TEST_DATABASE_URL or DATABASE_URL to point at a live test database.")

    return database_url


@pytest.fixture(scope="session")
def integration_engine(integration_database_url: str) -> Iterator[Engine]:
    engine = create_engine(integration_database_url, pool_pre_ping=True)

    try:
        with engine.begin() as connection:
            connection.execute(text("CREATE EXTENSION IF NOT EXISTS postgis"))
            connection.execute(text("CREATE EXTENSION IF NOT EXISTS pgcrypto"))

            available_extensions = {
                row[0] for row in connection.execute(text("SELECT extname FROM pg_extension"))
            }
            missing_extensions = {"postgis", "pgcrypto"} - available_extensions
            if missing_extensions:
                pytest.skip(
                    "Required database extensions are missing: "
                    + ", ".join(sorted(missing_extensions))
                )

            schema.Base.metadata.create_all(connection)
    except Exception as exc:  # pragma: no cover - exercised only in a live DB environment
        engine.dispose()
        pytest.skip(f"Live database validation is unavailable: {exc}")

    try:
        yield engine
    finally:
        if os.getenv("DROP_DB_AFTER_TESTS") == "1":
            with engine.begin() as connection:
                schema.Base.metadata.drop_all(connection)
        engine.dispose()


@pytest.fixture(autouse=True)
def clean_integration_database(request: pytest.FixtureRequest) -> Iterator[None]:
    if not _integration_enabled():
        yield
        return

    integration_engine = request.getfixturevalue("integration_engine")
    table_names = [
        table.name
        for table in schema.Base.metadata.sorted_tables
        if table.name != "alembic_version"
    ]

    if table_names:
        quoted_tables = ", ".join(f'"{table_name}"' for table_name in table_names)
        with integration_engine.begin() as connection:
            connection.execute(text(f"TRUNCATE TABLE {quoted_tables} RESTART IDENTITY CASCADE"))

    yield

    if table_names:
        with integration_engine.begin() as connection:
            connection.execute(text(f"TRUNCATE TABLE {quoted_tables} RESTART IDENTITY CASCADE"))


@pytest.fixture()
def db_session_manager(integration_database_url: str) -> DatabaseSessionManager:
    return DatabaseSessionManager(integration_database_url)


@pytest.fixture()
def integration_session(integration_engine: Engine) -> Iterator[Session]:
    session_factory = sessionmaker(
        bind=integration_engine,
        class_=Session,
        expire_on_commit=False,
        autoflush=False,
        autocommit=False,
    )
    session = session_factory()
    try:
        yield session
    finally:
        session.rollback()
        session.close()


def unique_email(prefix: str) -> str:
    return f"{prefix}-{uuid4().hex}@example.com"
