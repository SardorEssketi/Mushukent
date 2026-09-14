"""Extend report targets for lost pet and adoption posts.

Revision ID: 20260824_0014
Revises: 20260818_0013
Create Date: 2026-08-24
"""

from collections.abc import Sequence

from alembic import op

revision: str = "20260824_0014"
down_revision: str | None = "20260818_0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.execute("ALTER TYPE report_target_type ADD VALUE IF NOT EXISTS 'lost_pet'")
    op.execute("ALTER TYPE report_target_type ADD VALUE IF NOT EXISTS 'adoption_post'")


def downgrade() -> None:
    op.execute("ALTER TYPE report_target_type RENAME TO report_target_type_old")
    op.execute(
        "CREATE TYPE report_target_type AS ENUM ('post', 'comment', 'user', 'cat')"
    )
    op.execute(
        """
        ALTER TABLE reports
        ALTER COLUMN target_type TYPE report_target_type
        USING target_type::text::report_target_type
        """
    )
    op.execute("DROP TYPE report_target_type_old")
