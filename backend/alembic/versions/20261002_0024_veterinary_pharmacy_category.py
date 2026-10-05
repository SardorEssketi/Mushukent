"""Add veterinary pharmacy as a distinct place category.

Revision ID: 20261002_0024
Revises: 20260928_0023
"""

from alembic import op
from sqlalchemy import text

revision = "20261002_0024"
down_revision = "20260928_0023"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("ALTER TYPE place_category ADD VALUE IF NOT EXISTS 'veterinary_pharmacy'")


def downgrade() -> None:
    bind = op.get_bind()
    count = bind.execute(text("""
        SELECT (SELECT count(*) FROM places WHERE category = 'veterinary_pharmacy')
             + (SELECT count(*) FROM place_category_links WHERE category = 'veterinary_pharmacy')
    """)).scalar_one()
    if count:
        raise RuntimeError("Remove or recategorize veterinary pharmacy places before downgrading")
    op.execute("ALTER TYPE place_category RENAME TO place_category_old")
    op.execute("CREATE TYPE place_category AS ENUM ('pet_shop', 'veterinary', 'shelter')")
    op.execute("ALTER TABLE places ALTER COLUMN category TYPE place_category USING category::text::place_category")
    op.execute("ALTER TABLE place_category_links ALTER COLUMN category TYPE place_category USING category::text::place_category")
    op.execute("DROP TYPE place_category_old")
