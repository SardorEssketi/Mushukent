"""Add comment edit metadata and deletion actors.

Revision ID: 20260920_0018
Revises: 20260919_0017
Create Date: 2026-09-20
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260920_0018"
down_revision: str | None = "20260919_0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "comments",
        sa.Column("edited_at", sa.DateTime(timezone=True), nullable=True),
    )
    op.add_column(
        "comments",
        sa.Column("deleted_by_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_comments_deleted_by_id_users",
        "comments",
        "users",
        ["deleted_by_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "idx_comments_deleted_by_id",
        "comments",
        ["deleted_by_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_comments_deleted_by_id", table_name="comments")
    op.drop_constraint(
        "fk_comments_deleted_by_id_users",
        "comments",
        type_="foreignkey",
    )
    op.drop_column("comments", "deleted_by_id")
    op.drop_column("comments", "edited_at")
