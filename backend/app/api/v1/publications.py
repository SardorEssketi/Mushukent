from time import perf_counter
from uuid import UUID

from anyio import to_thread
from fastapi import HTTPException, Request
from structlog import get_logger

from app.api.v1.uploads import run_upload_processing
from app.core.security import api_error
from app.infrastructure.db.session import CommitOutcomeUnknownError
from app.infrastructure.publication_operations import (
    PublicationContext,
    PublicationOperations,
    publication_fingerprint,
)

logger = get_logger(__name__)


async def publish(request: Request, user, payload, photos, *, kind, create, read, **kwargs):
    raw_key = request.headers.get("idempotency-key")
    if raw_key is None:
        return await run_upload_processing(create, user, payload, photos=photos, **kwargs)
    try:
        key = UUID(raw_key)
    except ValueError as exc:
        raise api_error(422, "INVALID_PUBLICATION_KEY", "Idempotency-Key must be a UUID.") from exc
    operations = PublicationOperations(request.app.state.container.db_session_manager)
    started = perf_counter()

    def recover(exc: Exception, context) -> object:
        """Shared failure handling for both phases (unchanged from the single-phase version)."""
        uncertain = isinstance(exc, CommitOutcomeUnknownError) or (
            isinstance(exc, HTTPException)
            and isinstance(exc.detail, dict)
            and exc.detail.get("error", {}).get("code") == "PUBLICATION_OUTCOME_UNKNOWN"
        )
        if uncertain:
            # A fresh connection may establish that the final transaction committed.
            try:
                status = operations.status(user.id, key)
            except Exception:
                status = None
            if status and status["state"] == "completed":
                request.state.publication_replayed = True
                return read(UUID(status["target_id"]))
            logger.warning("publication_outcome_unknown", operation_id=str(key), kind=kind)
            raise api_error(
                503, "PUBLICATION_OUTCOME_UNKNOWN", "Check publication status before retrying."
            ) from exc
        if isinstance(context, PublicationContext):
            try:
                context.fail()
            except Exception:
                logger.warning("publication_failure_record_unresolved", operation_id=str(key))
        raise exc

    # Phase 1, outside the image-processing slot: reserve the key, or replay a completed one.
    # A duplicate or concurrent attempt is answered at once (409/replay) instead of queueing
    # behind other users' image work (load audit FIX-6 made that slot single).
    def reserve():
        try:
            context = operations.reserve(
                user.id, key, kind, publication_fingerprint(kind, payload, photos)
            )
            if isinstance(context, UUID):
                request.state.publication_replayed = True
                logger.info("publication_replayed", operation_id=str(key), kind=kind)
                return context, read(context)
            return context, None
        except Exception as exc:
            return None, recover(exc, None)

    context, replayed = await to_thread.run_sync(reserve)
    if context is None or isinstance(context, UUID):
        return replayed

    # Phase 2, in the single image-processing slot: decode, store and commit.
    def execute():
        try:
            result = create(user, payload, photos=photos, publication_context=context, **kwargs)
        except Exception as exc:
            return recover(exc, context)
        logger.info(
            "publication_completed",
            operation_id=str(key),
            kind=kind,
            duration_ms=round((perf_counter() - started) * 1000),
        )
        return result

    return await run_upload_processing(execute)
