"""Add media_deletion_jobs: R2 objects to delete after an account deletion.

Account deletion used to delete every photo from R2 inside the request, after the database commit.
A large account took longer than the app's 15 s timeout, and a restart or an R2 error during that
loop left photos in R2 with nothing pointing at them. Now the request records the object keys in
this table in the same transaction as the anonymisation and returns; the notification worker
deletes them with retries.

The table holds storage keys only (no user id, no URL). Additive only: old application code ignores
the new table, so rolling the application back does not require a schema rollback (rows written by
the new code would then wait until the new code runs again).

Revision ID: 20261123_0036
Revises: 20261114_0035
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261123_0036"
down_revision = "20261114_0035"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "media_deletion_jobs",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("object_key", sa.Text(), nullable=False),
        sa.Column("reason", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default=sa.text("'pending'")),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column(
            "next_attempt_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("lease_until", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_error_code", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint("object_key", name="uq_media_deletion_jobs_object_key"),
        sa.CheckConstraint(
            "status IN ('pending', 'deleting', 'done', 'failed')",
            name="media_deletion_jobs_status_valid",
        ),
        sa.CheckConstraint("attempts >= 0", name="media_deletion_jobs_attempts_valid"),
    )
    op.create_index(
        "idx_media_deletion_jobs_due",
        "media_deletion_jobs",
        ["next_attempt_at"],
        postgresql_where=sa.text("status IN ('pending', 'deleting')"),
    )


def downgrade() -> None:
    op.drop_index("idx_media_deletion_jobs_due", table_name="media_deletion_jobs")
    op.drop_table("media_deletion_jobs")
