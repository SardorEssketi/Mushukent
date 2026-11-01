"""Durable, account-scoped publication operation keys and media manifests.

Additive; migration 0029 is unchanged. Old clients need not send a key.
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261102_0030"
down_revision = "20261101_0029"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "publication_operations",
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("key", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("target_kind", sa.Text(), nullable=False),
        sa.Column("fingerprint", sa.Text(), nullable=False),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_token", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "media_keys", postgresql.JSONB(), nullable=False, server_default=sa.text("'[]'::jsonb")
        ),
        sa.CheckConstraint(
            "state IN ('pending', 'completed', 'failed')", name="publication_operation_state"
        ),
        sa.CheckConstraint(
            "target_kind IN ('post', 'lost_pet', 'adoption_post')",
            name="publication_operation_kind",
        ),
    )


def downgrade():
    op.drop_table("publication_operations")
