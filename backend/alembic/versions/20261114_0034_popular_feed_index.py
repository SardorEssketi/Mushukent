"""Index for the `popular` feed order (load audit FIX-11, audit F-21).

The popular feed orders by (like_count DESC, created_at DESC, id DESC); without a matching index
every page scans and sorts all posts. The predicate is `deleted_at IS NULL` only, so the
author's own private posts (visible to them in the feed) are covered too.

Built CONCURRENTLY outside the migration transaction. Additive only.

Revision ID: 20261114_0034
Revises: 20261114_0033
"""

from alembic import op

revision = "20261114_0034"
down_revision = "20261114_0033"
branch_labels = None
depends_on = None

NAME = "idx_posts_popular"


def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(
            f"CREATE INDEX CONCURRENTLY IF NOT EXISTS {NAME} ON posts "
            "(like_count DESC, created_at DESC, id DESC) WHERE deleted_at IS NULL"
        )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(f"DROP INDEX CONCURRENTLY IF EXISTS {NAME}")
