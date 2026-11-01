from time import perf_counter
from uuid import UUID

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

    def execute():
        started = perf_counter()
        context = None
        try:
            context = operations.reserve(
                user.id, key, kind, publication_fingerprint(kind, payload, photos)
            )
            if isinstance(context, UUID):
                request.state.publication_replayed = True
                logger.info("publication_replayed", operation_id=str(key), kind=kind)
                return read(context)
            result = create(user, payload, photos=photos, publication_context=context, **kwargs)
            logger.info(
                "publication_completed",
                operation_id=str(key),
                kind=kind,
                duration_ms=round((perf_counter() - started) * 1000),
            )
            return result
        except Exception as exc:
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
            raise

    return await run_upload_processing(execute)
