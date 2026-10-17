"""The test harness itself must be safe: explicit APP_ENV=test and no destructive fixture access
to anything that is not clearly a local, disposable test database."""

from __future__ import annotations

import os

import pytest
from db_safety import UnsafeTestDatabaseError, assert_safe_test_database

from app.core.config import get_settings


def test_harness_runs_with_an_explicit_test_environment() -> None:
    assert os.environ["APP_ENV"] == "test"
    settings = get_settings()
    assert settings.app_env == "test"
    assert settings.allows_dev_diagnostics and not settings.is_production_like
    assert os.environ["RATE_LIMIT_ENABLED"] == "false"


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+psycopg://u:p@localhost:5432/mushukistan_test",
        "postgresql+psycopg://u:p@127.0.0.1:55432/audit_test",
        "postgresql+psycopg://u:p@localhost/bf_test2",
        "postgresql+psycopg://u:p@[::1]:5432/test_mushukistan",
        "postgresql+psycopg://u:p@localhost/TEST",
    ],
)
def test_clearly_local_test_databases_are_allowed(url: str) -> None:
    assert_safe_test_database(url)


@pytest.mark.parametrize(
    "url",
    [
        "postgresql+psycopg://u:p@db:5432/mushukistan",  # the compose development database
        "postgresql+psycopg://u:p@localhost:5432/mushukistan",  # local but not a test name
        "postgresql+psycopg://u:p@localhost:5432/mushukistan_prod",
        "postgresql+psycopg://u:p@localhost:5432/latest",  # contains "test" only as a substring
        "postgresql+psycopg://u:p@prod-db.example.com:5432/app_test",  # remote host
        "postgresql+psycopg://u:p@10.0.0.5:5432/app_test",
        "postgresql+psycopg://u:p@/app_test",  # no host at all (unix socket)
        "postgresql+psycopg://u:p@localhost:5432/",
    ],
)
def test_development_production_and_remote_databases_are_refused(url: str) -> None:
    with pytest.raises(UnsafeTestDatabaseError) as error:
        assert_safe_test_database(url)
    assert "Refusing to run destructive integration tests" in str(error.value)
    assert "p@" not in str(error.value)  # credentials never appear in the message


def test_explicitly_allow_listed_ci_hosts_are_accepted() -> None:
    url = "postgresql+psycopg://u:p@postgis:5432/app_test"
    with pytest.raises(UnsafeTestDatabaseError):
        assert_safe_test_database(url)
    assert_safe_test_database(url, extra_hosts=frozenset({"postgis"}))


def test_allow_list_does_not_relax_the_database_name_rule() -> None:
    with pytest.raises(UnsafeTestDatabaseError):
        assert_safe_test_database(
            "postgresql+psycopg://u:p@postgis:5432/mushukistan", extra_hosts=frozenset({"postgis"})
        )
