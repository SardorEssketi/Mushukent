"""Add product feedback submissions.

Revision ID: 20261013_0026
Revises: 20261007_0025
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261013_0026"
down_revision = "20261007_0025"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "feedback",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True)),
        sa.Column("category", sa.Text(), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("platform", sa.Text()),
        sa.Column("app_version", sa.Text()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.CheckConstraint(
            "category IN ('bug', 'suggestion', 'other')",
            name="feedback_category_valid",
        ),
        sa.CheckConstraint(
            "char_length(message) BETWEEN 10 AND 2000",
            name="feedback_message_length",
        ),
    )
    op.create_index("idx_feedback_user_created", "feedback", ["user_id", "created_at"])


def downgrade() -> None:
    op.drop_index("idx_feedback_user_created", table_name="feedback")
    op.drop_table("feedback")
