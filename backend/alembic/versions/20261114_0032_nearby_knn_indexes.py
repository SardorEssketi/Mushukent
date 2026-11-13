"""Geography GiST indexes for the nearest-first `nearby` feed (load audit FIX-2).

The feed orders by ``geography(location) <-> point``; these expression indexes let PostgreSQL
read only the rows a page needs instead of computing a distance for every post in the radius.
The expression and the partial predicate (``deleted_at IS NULL``) match the query exactly.

Built CONCURRENTLY (no write lock on posts/lost_pets), so each statement runs outside the
migration transaction. Additive only: older application code ignores the indexes.

Revision ID: 20261114_0032
Revises: 20261110_0031
"""

from alembic import op

revision = "20261114_0032"
down_revision = "20261110_0031"
branch_labels = None
depends_on = None

INDEXES = (
    ("idx_posts_location_geography_knn", "posts", "geography(location)"),
    ("idx_lost_pets_location_geography_knn", "lost_pets", "geography(last_seen_location)"),
)


def upgrade() -> None:
    with op.get_context().autocommit_block():
        for name, table, expression in INDEXES:
            op.execute(
                f"CREATE INDEX CONCURRENTLY IF NOT EXISTS {name} ON {table} "
                f"USING gist (({expression})) WHERE deleted_at IS NULL"
            )


def downgrade() -> None:
    with op.get_context().autocommit_block():
        for name, _table, _expression in reversed(INDEXES):
            op.execute(f"DROP INDEX CONCURRENTLY IF EXISTS {name}")
