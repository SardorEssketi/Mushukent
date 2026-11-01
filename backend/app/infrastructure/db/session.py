from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager

from sqlalchemy import create_engine
from sqlalchemy.orm import Session, sessionmaker
from structlog import get_logger

logger = get_logger(__name__)


class CommitOutcomeUnknownError(RuntimeError):
    """The connection did not establish whether COMMIT succeeded."""


class DatabaseSessionManager:
    def __init__(self, database_url: str) -> None:
        self.engine = create_engine(database_url, pool_pre_ping=True)
        self.session_factory = sessionmaker(
            bind=self.engine,
            class_=Session,
            expire_on_commit=False,
            autoflush=False,
            autocommit=False,
        )

    def create_session(self) -> Session:
        return self.session_factory()

    @contextmanager
    def session_scope(self) -> Iterator[Session]:
        session = self.create_session()
        try:
            yield session
            try:
                session.commit()
            except Exception as exc:
                # ROLLBACK cannot undo a COMMIT the server already acknowledged internally.
                raise CommitOutcomeUnknownError("Database commit outcome is unknown.") from exc
        except Exception:
            try:
                session.rollback()
            except Exception as exc:
                logger.warning("database_rollback_failed", error_type=type(exc).__name__)
            raise
        finally:
            try:
                session.close()
            except Exception as exc:
                # A connection cleanup failure must not turn a committed operation into a retry.
                logger.warning("database_session_close_failed", error_type=type(exc).__name__)

    def dispose(self) -> None:
        self.engine.dispose()
