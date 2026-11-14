"""Covering index for visible comment counts (load audit FIX-5 follow-up).

Every feed card and detail page counts the comments its viewer can see (not deleted, author not
blocked). For popular posts that read hundreds of comment rows from the heap per card (574 heap
blocks for one hot post; about 28 ms each on the production-sized host with a cold cache). With
(post_id, user_id) WHERE deleted_at IS NULL the count is an index-only scan; user_id covers the
block check for signed-in viewers.

Built CONCURRENTLY outside the migration transaction. Additive only.

Revision ID: 20261114_0035
Revises: 20261114_0034
"""

from alembic import op

revision = "20261114_0035"
down_revision = "20261114_0034"
branch_labels = None
depends_on = None

NAME = "idx_comments_post_visible"


def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(
            f"CREATE INDEX CONCURRENTLY IF NOT EXISTS {NAME} ON comments "
            "(post_id, user_id) WHERE deleted_at IS NULL"
        )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(f"DROP INDEX CONCURRENTLY IF EXISTS {NAME}")
