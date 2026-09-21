"""Add auth refresh sessions.

Revision ID: 20260825_0015
Revises: 20260824_0014
Create Date: 2026-08-25
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260825_0015"
down_revision: str | None = "20260824_0014"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "auth_refresh_sessions",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("token_hash", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_used_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("id", postgresql.UUID(as_uuid=True), server_default=sa.text("gen_random_uuid()"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("token_hash"),
    )
    op.create_index("idx_auth_refresh_sessions_user_id", "auth_refresh_sessions", ["user_id"])
    op.create_index("idx_auth_refresh_sessions_token_hash", "auth_refresh_sessions", ["token_hash"])
    op.create_index("idx_auth_refresh_sessions_expires_at", "auth_refresh_sessions", ["expires_at"])


def downgrade() -> None:
    op.drop_index("idx_auth_refresh_sessions_expires_at", table_name="auth_refresh_sessions")
    op.drop_index("idx_auth_refresh_sessions_token_hash", table_name="auth_refresh_sessions")
    op.drop_index("idx_auth_refresh_sessions_user_id", table_name="auth_refresh_sessions")
    op.drop_table("auth_refresh_sessions")
