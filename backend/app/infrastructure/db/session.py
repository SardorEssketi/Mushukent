from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import contextmanager
from time import perf_counter

from sqlalchemy import create_engine
from sqlalchemy import exc as sa_exc
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session, sessionmaker
from sqlalchemy.pool import QueuePool
from structlog import get_logger

logger = get_logger(__name__)


class CommitOutcomeUnknownError(RuntimeError):
    """The connection did not establish whether COMMIT succeeded."""


PoolWaitObserver = Callable[[float, bool], None]


def timed_queue_pool(observer: PoolWaitObserver) -> type[QueuePool]:
    """A QueuePool that reports how long each checkout waited, and whether it timed out.

    Used by the API's ops metrics (LT-20). It wraps ``QueuePool._do_get``, which SQLAlchemy calls
    once per checkout from the pool; a test pins this so an upgrade that changes it fails loudly.
    """

    class _TimedQueuePool(QueuePool):
        def _do_get(self):  # type: ignore[override]
            start = perf_counter()
            timed_out = False
            try:
                return super()._do_get()
            except sa_exc.TimeoutError:
                timed_out = True
                raise
            finally:
                try:
                    observer((perf_counter() - start) * 1000, timed_out)
                except Exception:  # noqa: BLE001 - observation must never break a checkout
                    pass

    return _TimedQueuePool


class DatabaseSessionManager:
    """Engine + session factory.

    Request limits are opt-in. The API passes them (see ``build_container``) so that a saturated
    database turns into quick, retryable failures instead of 30 s pool waits and queries that keep
    running after the client gave up (load audit LT-02). Migrations, maintenance scripts and the
    notification worker construct managers without limits.
    """

    def __init__(
        self,
        database_url: str,
        *,
        pool_timeout: float = 30,
        statement_timeout_ms: int | None = None,
        lock_timeout_ms: int | None = None,
        idle_in_transaction_timeout_ms: int | None = None,
        pool_wait_observer: PoolWaitObserver | None = None,
    ) -> None:
        options = " ".join(
            f"-c {name}={value}"
            for name, value in (
                ("statement_timeout", statement_timeout_ms),
                ("lock_timeout", lock_timeout_ms),
                ("idle_in_transaction_session_timeout", idle_in_transaction_timeout_ms),
            )
            if value is not None
        )
        engine_kwargs: dict[str, object] = {"pool_pre_ping": True}
        if make_url(database_url).get_backend_name() != "sqlite":  # unit tests use SQLite
            engine_kwargs.update(pool_size=5, max_overflow=10, pool_timeout=pool_timeout)
            if options:
                engine_kwargs["connect_args"] = {"options": options}
            if pool_wait_observer is not None:
                engine_kwargs["poolclass"] = timed_queue_pool(pool_wait_observer)
        self.engine = create_engine(database_url, **engine_kwargs)
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
                logger.warning("database_commit_outcome_unknown", error_type=type(exc).__name__)
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
