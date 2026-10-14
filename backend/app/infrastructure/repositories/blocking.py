"""Shared user-blocking predicates.

Blocking semantics (see docs/BLOCKING.md): a block is *symmetric in effect*. When a
``user_blocks`` row exists in either direction between two users, neither user can see
the other's content or interact with it. Rows are only created and removed through the
users service, so unblocking restores everything that blocking hid; nothing is deleted.

Every read path that exposes user-authored content builds its filter from these helpers so
the rule lives in one place and pagination stays correct (the filter is part of the SQL,
not applied to a fetched page).
"""

from __future__ import annotations

from uuid import UUID

from sqlalchemy import ColumnElement, and_, exists, false, or_, select
from sqlalchemy.orm import Session

from app.infrastructure.db.models import schema


def _block_exists(blocker, blocked) -> ColumnElement[bool]:
    block = schema.UserBlock
    return exists(select(1).where(block.blocker_id == blocker, block.blocked_id == blocked))


def blocked_between(user_id: UUID | None, author_column) -> ColumnElement[bool]:
    """SQL predicate: TRUE when ``user_id`` and the row's author block each other."""
    if user_id is None:
        return false()
    return or_(_block_exists(user_id, author_column), _block_exists(author_column, user_id))


def exclude_blocked(statement, viewer_user_id: UUID | None, author_column):
    """Restrict ``statement`` to rows whose author has no block with the viewer.

    Anonymous viewers and rows without an author (deleted accounts) are never filtered.

    The two directions are two separate ``NOT EXISTS`` conditions on purpose: PostgreSQL turns
    each into an index-friendly anti join, whereas one ``NOT (a OR b)`` or an ``OR`` inside one
    subquery falls back to a per-row subplan/filter (measured 150-240 ms vs ~35 ms on a
    200,000-post feed, see docs/BLOCKING.md).
    """
    if viewer_user_id is None:
        return statement
    return statement.where(
        ~_block_exists(viewer_user_id, author_column),
        ~_block_exists(author_column, viewer_user_id),
    )


def users_are_blocked(session: Session, user_a: UUID | None, user_b: UUID | None) -> bool:
    """True when a block exists between the two users in either direction.

    Missing users (anonymous viewer, deleted author) are never blocked.
    """
    if user_a is None or user_b is None or user_a == user_b:
        return False
    block = schema.UserBlock
    return (
        session.scalar(
            select(1).where(
                or_(
                    and_(block.blocker_id == user_a, block.blocked_id == user_b),
                    and_(block.blocker_id == user_b, block.blocked_id == user_a),
                )
            )
        )
        is not None
    )
