"""add compliance consent fields

Revision ID: 20260801_0010
Revises: 20260731_0009
Create Date: 2026-08-01
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "20260801_0010"
down_revision = "20260731_0009"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("accepted_terms_version", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("accepted_privacy_version", sa.Text(), nullable=True))
    op.add_column(
        "users", sa.Column("accepted_legal_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.add_column(
        "lost_pets",
        sa.Column(
            "owner_phone_publication_consent",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
    )
    op.create_table(
        "user_blocks",
        sa.Column("id", sa.UUID(), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("blocker_id", sa.UUID(), nullable=False),
        sa.Column("blocked_id", sa.UUID(), nullable=False),
        sa.ForeignKeyConstraint(["blocked_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["blocker_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("blocker_id", "blocked_id", name="uq_user_blocks_blocker_blocked"),
        sa.CheckConstraint("blocker_id <> blocked_id", name="user_blocks_not_self"),
    )
    op.create_index("idx_user_blocks_blocker_id", "user_blocks", ["blocker_id"])
    op.create_index("idx_user_blocks_blocked_id", "user_blocks", ["blocked_id"])


def downgrade() -> None:
    op.drop_index("idx_user_blocks_blocked_id", table_name="user_blocks")
    op.drop_index("idx_user_blocks_blocker_id", table_name="user_blocks")
    op.drop_table("user_blocks")
    op.drop_column("lost_pets", "owner_phone_publication_consent")
    op.drop_column("users", "accepted_legal_at")
    op.drop_column("users", "accepted_privacy_version")
    op.drop_column("users", "accepted_terms_version")
