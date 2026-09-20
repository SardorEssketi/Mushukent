"""Add durable post edit and deletion history.

Revision ID: 20260919_0017
Revises: 20260914_0016
Create Date: 2026-09-19
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260919_0017"
down_revision: str | None = "20260914_0016"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "post_history",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("actor_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("action", sa.Text(), nullable=False),
        sa.Column("before", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column("after", postgresql.JSONB(astext_type=sa.Text()), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint("action IN ('edited', 'deleted')", name="post_history_action_valid"),
        sa.ForeignKeyConstraint(["actor_id"], ["users.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["post_id"], ["posts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_post_history_post_id_created_at",
        "post_history",
        ["post_id", "created_at"],
        unique=False,
    )
    op.create_index(
        "idx_post_history_actor_id",
        "post_history",
        ["actor_id"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_post_history_actor_id", table_name="post_history")
    op.drop_index("idx_post_history_post_id_created_at", table_name="post_history")
    op.drop_table("post_history")
