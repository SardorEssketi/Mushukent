"""Add nested comment replies.

Revision ID: 20260914_0016
Revises: 20260825_0015
Create Date: 2026-09-14
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260914_0016"
down_revision: str | None = "20260825_0015"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "comments",
        sa.Column("parent_comment_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_comments_parent_comment_id_comments",
        "comments",
        "comments",
        ["parent_comment_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(
        "idx_comments_parent_comment_id",
        "comments",
        ["parent_comment_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_comments_parent_comment_id", table_name="comments")
    op.drop_constraint(
        "fk_comments_parent_comment_id_comments",
        "comments",
        type_="foreignkey",
    )
    op.drop_column("comments", "parent_comment_id")
