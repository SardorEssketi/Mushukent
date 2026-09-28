"""Store lost-pet contact events and owner follow-ups.

Revision ID: 20260928_0022
Revises: 20260926_0021
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20260928_0022"
down_revision = "20260926_0021"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "lost_pet_contact_events",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "lost_pet_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("lost_pets.id", ondelete="CASCADE"),
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
    op.create_index("idx_lost_pet_contacts_lost_pet_id", "lost_pet_contact_events", ["lost_pet_id"])
    op.create_table(
        "lost_pet_follow_ups",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "lost_pet_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("lost_pets.id", ondelete="CASCADE"),
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
            "(completed_at IS NULL AND answer_yes IS NULL) OR (completed_at IS NOT NULL AND answer_yes IS NOT NULL)",
            name="lost_pet_follow_ups_answer_state",
        ),
    )
    op.create_index(
        "uq_lost_pet_follow_ups_pending",
        "lost_pet_follow_ups",
        ["lost_pet_id"],
        unique=True,
        postgresql_where=sa.text("completed_at IS NULL"),
    )
    op.create_index(
        "idx_lost_pet_follow_ups_owner_due", "lost_pet_follow_ups", ["owner_id", "due_at"]
    )


def downgrade() -> None:
    op.drop_index("idx_lost_pet_follow_ups_owner_due", table_name="lost_pet_follow_ups")
    op.drop_index("uq_lost_pet_follow_ups_pending", table_name="lost_pet_follow_ups")
    op.drop_table("lost_pet_follow_ups")
    op.drop_index("idx_lost_pet_contacts_lost_pet_id", table_name="lost_pet_contact_events")
    op.drop_table("lost_pet_contact_events")
