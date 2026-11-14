"""Index for the map pins' "latest public post per cat" lookup (load audit FIX-4).

`GET /cats?bbox=...` joins, for every cat in the viewport, the newest public post of the last
10 days (LATERAL ... ORDER BY created_at DESC, id DESC LIMIT 1). This index answers each probe
with one index entry instead of reading all of the cat's posts.

Built CONCURRENTLY outside the migration transaction. Additive only.

Revision ID: 20261114_0033
Revises: 20261114_0032
"""

from alembic import op

revision = "20261114_0033"
down_revision = "20261114_0032"
branch_labels = None
depends_on = None

NAME = "idx_posts_cat_public_latest"


def upgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(
            f"CREATE INDEX CONCURRENTLY IF NOT EXISTS {NAME} ON posts "
            "(cat_id, created_at DESC, id DESC) WHERE deleted_at IS NULL AND is_public IS true"
        )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        op.execute(f"DROP INDEX CONCURRENTLY IF EXISTS {NAME}")
