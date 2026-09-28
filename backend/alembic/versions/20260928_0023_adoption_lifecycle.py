"""Persist adoption contact events and in-app owner follow-ups.

Revision ID: 20260928_0023
Revises: 20260928_0022
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20260928_0023"
down_revision = "20260928_0022"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "adoption_posts",
        sa.Column("is_resolved", sa.Boolean(), nullable=False, server_default=sa.text("false")),
    )
    op.create_table(
        "adoption_contact_events",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "adoption_post_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adoption_posts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
        ),
        sa.Column(
            "contacting_user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
    )
    op.create_index(
        "idx_adoption_contacts_post_id", "adoption_contact_events", ["adoption_post_id"]
    )
    op.create_table(
        "adoption_follow_ups",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "adoption_post_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("adoption_posts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "owner_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
        ),
        sa.Column("due_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("completed_at", sa.DateTime(timezone=True)),
        sa.Column("answer_yes", sa.Boolean()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.CheckConstraint(
            "(completed_at IS NULL AND answer_yes IS NULL) OR "
            "(completed_at IS NOT NULL AND answer_yes IS NOT NULL)",
            name="adoption_follow_ups_answer_state",
        ),
    )
    op.create_index(
        "uq_adoption_follow_ups_pending",
        "adoption_follow_ups",
        ["adoption_post_id"],
        unique=True,
        postgresql_where=sa.text("completed_at IS NULL"),
    )
    op.create_index(
        "idx_adoption_follow_ups_owner_due", "adoption_follow_ups", ["owner_id", "due_at"]
    )


def downgrade() -> None:
    op.drop_index("idx_adoption_follow_ups_owner_due", table_name="adoption_follow_ups")
    op.drop_index("uq_adoption_follow_ups_pending", table_name="adoption_follow_ups")
    op.drop_table("adoption_follow_ups")
    op.drop_index("idx_adoption_contacts_post_id", table_name="adoption_contact_events")
    op.drop_table("adoption_contact_events")
    op.drop_column("adoption_posts", "is_resolved")
