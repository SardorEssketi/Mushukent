"""Quota-limited, auditable reveal of a post owner's contact details.

The log (`contact_reveals`) stores who revealed which post and how, never the contact itself.
A user pays quota once per post: revealing the same post again is free, so a legitimate user can
reopen a conversation without being locked out.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select, text
from sqlalchemy.orm import Session
from structlog import get_logger

from app.core.config import Settings, get_settings
from app.core.security import api_error
from app.infrastructure.db.models import schema

logger = get_logger(__name__)

KIND_LOST_PET = "lost_pet"
KIND_ADOPTION = "adoption"
MODE_EXPLICIT = "explicit"
MODE_LEGACY_DETAIL = "legacy_detail"


CONTACT_MODE_HEADER = "x-contact-mode"


def is_reveal_mode(request) -> bool:
    """True for clients that declare they use the explicit reveal endpoint."""
    return request.headers.get(CONTACT_MODE_HEADER, "").strip().lower() == "reveal"


def mark_private(response, *, authenticated: bool) -> None:
    """Contact-bearing responses must never be stored by a shared cache."""
    response.headers["Vary"] = "Authorization"
    if authenticated:
        response.headers["Cache-Control"] = "private, no-store"


class ContactRevealLimitExceeded(Exception):
    def __init__(self, retry_after_seconds: int) -> None:
        super().__init__("contact reveal limit reached")
        self.retry_after_seconds = retry_after_seconds


@dataclass(frozen=True, slots=True)
class RevealRequest:
    user_id: UUID
    kind: str
    post_id: UUID
    owner_id: UUID | None
    mode: str


def record_reveal(
    session: Session, request: RevealRequest, *, settings: Settings | None = None
) -> bool:
    """Record a reveal, enforcing the per-user quota. Returns True when it consumed quota.

    Raises ContactRevealLimitExceeded when the user is over a limit or the account is too new.
    """
    settings = settings or get_settings()
    now = datetime.now(UTC)
    # Serialise concurrent reveals of one user so parallel requests cannot all pass the count.
    session.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:key, 0))"),
        {"key": f"contact_reveal:{request.user_id}"},
    )
    existing = session.scalar(
        select(schema.ContactReveal.id).where(
            schema.ContactReveal.user_id == request.user_id,
            schema.ContactReveal.post_kind == request.kind,
            schema.ContactReveal.post_id == request.post_id,
        )
    )
    if existing is not None:
        return False

    if settings.contact_reveal_min_account_age_hours:
        created_at = session.scalar(
            select(schema.User.registered_at).where(schema.User.id == request.user_id)
        )
        if created_at is not None:
            ready_at = created_at + timedelta(hours=settings.contact_reveal_min_account_age_hours)
            if ready_at > now:
                raise ContactRevealLimitExceeded(int((ready_at - now).total_seconds()) + 1)

    for window, limit in (
        (timedelta(days=1), settings.contact_reveal_max_per_day),
        (timedelta(days=7), settings.contact_reveal_max_per_week),
    ):
        since = now - window
        used = session.execute(
            select(func.count(), func.min(schema.ContactReveal.created_at)).where(
                schema.ContactReveal.user_id == request.user_id,
                schema.ContactReveal.created_at > since,
            )
        ).one()
        count, oldest = used
        if count >= limit:
            retry_after = int((oldest + window - now).total_seconds()) + 1 if oldest else 60
            logger.info(
                "contact_reveal_limit_reached",
                user_id=str(request.user_id),
                kind=request.kind,
                window_days=window.days,
            )
            raise ContactRevealLimitExceeded(max(retry_after, 1))

    session.add(
        schema.ContactReveal(
            user_id=request.user_id,
            post_kind=request.kind,
            post_id=request.post_id,
            owner_id=request.owner_id,
            mode=request.mode,
        )
    )
    session.flush()
    logger.info(
        "contact_revealed",
        user_id=str(request.user_id),
        kind=request.kind,
        post_id=str(request.post_id),
        mode=request.mode,
    )
    return True


def limit_exceeded_error(exc: ContactRevealLimitExceeded):
    error = api_error(
        429,
        "CONTACT_REVEAL_LIMIT",
        "You have viewed the maximum number of owner contacts for now. Try again later.",
        details={"retry_after_seconds": exc.retry_after_seconds},
    )
    error.headers = {"Retry-After": str(exc.retry_after_seconds)}
    return error


def resolve_detail_contact(
    session: Session,
    *,
    kind: str,
    post_id: UUID,
    owner_id: UUID | None,
    viewer_id: UUID | None,
    contact_available: bool,
    reveal_mode: bool,
    settings: Settings | None = None,
) -> bool:
    """Decide whether a detail response may carry the owner's contact.

    * anonymous viewers never get it;
    * the owner always sees their own (the edit form needs it);
    * clients that declared reveal mode (`X-Contact-Mode: reveal`) never get it here: they call
      the explicit reveal endpoint;
    * legacy clients (header absent) get it while the compatibility flag is on, and only within the
      same per-user quota as explicit reveals. Over the quota they simply see no contact.
    """
    if viewer_id is None:
        return False
    if owner_id is not None and viewer_id == owner_id:
        return True
    if not contact_available or reveal_mode:
        return False
    settings = settings or get_settings()
    if not settings.contact_legacy_detail_enabled:
        return False
    try:
        record_reveal(
            session,
            RevealRequest(
                user_id=viewer_id,
                kind=kind,
                post_id=post_id,
                owner_id=owner_id,
                mode=MODE_LEGACY_DETAIL,
            ),
            settings=settings,
        )
    except ContactRevealLimitExceeded:
        return False
    return True
