"""Add contact reveal log and contact consent version columns.

Additive only: old application code ignores the new table and columns, so rolling the application
back does not require a schema rollback.

Revision ID: 20261015_0027
Revises: 20261013_0026
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261015_0027"
down_revision = "20261013_0026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "contact_reveals",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("post_kind", sa.Text(), nullable=False),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("owner_id", postgresql.UUID(as_uuid=True)),
        sa.Column("mode", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["owner_id"], ["users.id"], ondelete="SET NULL"),
        sa.UniqueConstraint("user_id", "post_kind", "post_id", name="uq_contact_reveals_user_post"),
        sa.CheckConstraint("post_kind IN ('lost_pet', 'adoption')", name="ck_contact_reveals_kind"),
        sa.CheckConstraint("mode IN ('explicit', 'legacy_detail')", name="ck_contact_reveals_mode"),
    )
    op.create_index(
        "idx_contact_reveals_user_created", "contact_reveals", ["user_id", "created_at"]
    )
    for table in ("lost_pets", "adoption_posts"):
        op.add_column(table, sa.Column("contact_consent_version", sa.SmallInteger()))
        op.add_column(table, sa.Column("contact_consent_at", sa.DateTime(timezone=True)))


def downgrade() -> None:
    for table in ("lost_pets", "adoption_posts"):
        op.drop_column(table, "contact_consent_at")
        op.drop_column(table, "contact_consent_version")
    op.drop_index("idx_contact_reveals_user_created", table_name="contact_reveals")
    op.drop_table("contact_reveals")
