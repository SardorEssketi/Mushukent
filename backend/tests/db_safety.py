"""Guard that keeps the destructive integration-test fixtures away from real databases.

``tests/conftest.py`` truncates every table before and after each integration test. That must
never reach a development or production database, so the URL is validated before any engine is
created: the host must be local (or explicitly allow-listed) and the database name must contain
the word ``test``.
"""

from __future__ import annotations

import os
import re

from sqlalchemy.engine import make_url

LOCAL_HOSTS = frozenset({"localhost", "127.0.0.1", "::1"})
_TEST_NAME = re.compile(r"(?:^|[_-])test(?:[_-]|\d*$)", re.IGNORECASE)


class UnsafeTestDatabaseError(RuntimeError):
    """Raised when a destructive test would target a database that is not clearly a test one."""


def assert_safe_test_database(url: str, *, extra_hosts: frozenset[str] | None = None) -> None:
    parsed = make_url(url)
    hosts = LOCAL_HOSTS | (extra_hosts or frozenset())
    host = (parsed.host or "").lower()
    name = parsed.database or ""
    problems = []
    if host not in hosts:
        problems.append(
            f"host {host or '<none>'!r} is not local (allowed: {', '.join(sorted(hosts))})"
        )
    if not _TEST_NAME.search(name):
        problems.append(f"database name {name!r} must contain the word 'test' (e.g. app_test)")
    if problems:
        raise UnsafeTestDatabaseError(
            "Refusing to run destructive integration tests: "
            + "; ".join(problems)
            + ". Point TEST_DATABASE_URL at a disposable local database."
        )


def allowed_extra_hosts() -> frozenset[str]:
    """Hosts opted in via TEST_DATABASE_ALLOWED_HOSTS (e.g. a Docker network alias)."""
    raw = os.getenv("TEST_DATABASE_ALLOWED_HOSTS", "")
    return frozenset(part.strip().lower() for part in raw.split(",") if part.strip())
