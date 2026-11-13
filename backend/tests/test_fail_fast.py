"""Fail fast under overload (load audit LT-02, FIX-1).

A saturated database must turn into quick 503 responses that the client can retry, not into
30 s waits for a pool connection followed by a 500, and never into queries that keep running
after their client gave up.
"""

from __future__ import annotations

import time

import psycopg
import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import text
from sqlalchemy.exc import OperationalError, ProgrammingError
from sqlalchemy.exc import TimeoutError as PoolTimeoutError

from app.core.config import Settings
from app.core.errors import register_error_handlers
from app.infrastructure.db.session import DatabaseSessionManager


def _app_raising(exc: Exception) -> TestClient:
    app = FastAPI()
    register_error_handlers(app)

    @app.get("/busy")
    def busy() -> None:
        raise exc

    return TestClient(app, raise_server_exceptions=False)


def _assert_service_busy(response) -> None:
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "SERVICE_BUSY"
    assert int(response.headers["Retry-After"]) >= 1


def test_pool_timeout_becomes_service_busy() -> None:
    exc = PoolTimeoutError("QueuePool limit of size 5 overflow 10 reached")
    _assert_service_busy(_app_raising(exc).get("/busy"))


@pytest.mark.parametrize(
    "orig",
    [
        psycopg.errors.QueryCanceled("canceling statement due to statement timeout"),
        psycopg.errors.LockNotAvailable("canceling statement due to lock timeout"),
        psycopg.errors.IdleInTransactionSessionTimeout("terminating connection"),
    ],
)
def test_database_timeouts_become_service_busy(orig: Exception) -> None:
    exc = OperationalError("SELECT 1", {}, orig)
    _assert_service_busy(_app_raising(exc).get("/busy"))


def test_other_database_errors_stay_internal_errors() -> None:
    exc = ProgrammingError("SELECT * FROM missing", {}, psycopg.errors.UndefinedTable("missing"))
    response = _app_raising(exc).get("/busy")
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "INTERNAL_SERVER_ERROR"


def test_api_settings_have_request_limits_by_default() -> None:
    settings = Settings(_env_file=None, APP_ENV="test")
    assert settings.db_pool_timeout_seconds == 3
    assert settings.db_statement_timeout_ms == 15_000
    assert settings.db_lock_timeout_ms == 3_000
    assert settings.db_idle_in_transaction_timeout_ms == 15_000
    assert settings.service_busy_retry_after_seconds >= 1


def test_session_manager_applies_request_limits(integration_database_url: str) -> None:
    manager = DatabaseSessionManager(
        integration_database_url,
        pool_timeout=3,
        statement_timeout_ms=300,
        lock_timeout_ms=200,
        idle_in_transaction_timeout_ms=15_000,
    )
    try:
        with manager.session_scope() as session:
            assert session.execute(text("SHOW statement_timeout")).scalar_one() == "300ms"
            assert session.execute(text("SHOW lock_timeout")).scalar_one() == "200ms"
            assert (
                session.execute(text("SHOW idle_in_transaction_session_timeout")).scalar_one()
                == "15s"
            )
        started = time.perf_counter()
        with pytest.raises(OperationalError) as raised:
            with manager.session_scope() as session:
                session.execute(text("SELECT pg_sleep(5)"))
        assert isinstance(raised.value.orig, psycopg.errors.QueryCanceled)
        assert time.perf_counter() - started < 3
    finally:
        manager.dispose()


def test_session_manager_without_limits_keeps_server_defaults(
    integration_database_url: str,
) -> None:
    """Migrations, scripts and the notification worker build managers without limits."""
    manager = DatabaseSessionManager(integration_database_url)
    try:
        with manager.session_scope() as session:
            assert session.execute(text("SHOW statement_timeout")).scalar_one() == "0"
    finally:
        manager.dispose()


def test_pool_exhaustion_fails_within_the_pool_timeout(integration_database_url: str) -> None:
    manager = DatabaseSessionManager(integration_database_url, pool_timeout=1)
    held = []
    try:
        for _ in range(15):  # pool_size 5 + max_overflow 10
            held.append(manager.engine.connect())
        started = time.perf_counter()
        with pytest.raises(PoolTimeoutError):
            manager.engine.connect()
        assert time.perf_counter() - started < 2.5
    finally:
        for connection in held:
            connection.close()
        manager.dispose()
