"""Shared rule for which comments a viewer can see, and how many.

A comment is visible to a viewer when it is not soft-deleted and no block exists between the
viewer and the comment's author in either direction (``blocking.exclude_blocked``). Comments of
deleted accounts are soft-deleted by account deletion, so they are excluded by the first rule.
Anonymous viewers are not affected by blocks.

The comment lists (``GET .../comments``) and every ``comment_count`` returned with a publication
use this one rule, so the number on a card always equals the number of comments the same viewer
gets when paging through the whole comment list (top-level comments and replies; the list is
flat). See docs/BLOCKING.md, "Comment counts".

The stored ``comment_count`` columns are global (not viewer-specific) and are no longer read for
API responses; they are still maintained on write.
"""

from __future__ import annotations

from collections.abc import Iterable
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import InstrumentedAttribute, Session

from app.infrastructure.db.models import schema
from app.infrastructure.repositories.blocking import exclude_blocked


def apply_comment_visibility(statement, viewer_user_id: UUID | None):
    """Restrict a statement selecting from ``comments`` to the comments the viewer can see."""
    statement = statement.where(schema.Comment.deleted_at.is_(None))
    return exclude_blocked(statement, viewer_user_id, schema.Comment.user_id)


def visible_comment_count(
    target_column: InstrumentedAttribute,
    publication_id_column: InstrumentedAttribute,
    viewer_user_id: UUID | None,
):
    """Correlated scalar subquery: visible comments on the outer query's publication row.

    ``target_column`` is the comment foreign key (for example ``Comment.post_id``) and
    ``publication_id_column`` the outer primary key (``Post.id``). It uses the comment target
    index. PostgreSQL evaluates it only for rows that survive the outer ``LIMIT`` when it is not
    used for sorting, so feed pages cost one index probe per returned item, not per scanned row.
    """
    statement = select(func.count(schema.Comment.id)).where(target_column == publication_id_column)
    statement = apply_comment_visibility(statement, viewer_user_id)
    return statement.correlate_except(schema.Comment).scalar_subquery()


def visible_comment_counts(
    session: Session,
    target_column: InstrumentedAttribute,
    publication_ids: Iterable[UUID],
    viewer_user_id: UUID | None,
) -> dict[UUID, int]:
    """Visible comment counts for many publications in one grouped query.

    Publications without visible comments are absent from the result (count 0).
    """
    ids = list(dict.fromkeys(publication_ids))
    if not ids:
        return {}
    statement = (
        select(target_column, func.count(schema.Comment.id))
        .where(target_column.in_(ids))
        .group_by(target_column)
    )
    statement = apply_comment_visibility(statement, viewer_user_id)
    return {publication_id: int(count) for publication_id, count in session.execute(statement)}
