"""Add post view log and view_count columns.

Additive only: old application code ignores the new table and columns, so rolling the application
back does not require a schema rollback.

Revision ID: 20261029_0028
Revises: 20261015_0027
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261029_0028"
down_revision = "20261015_0027"
branch_labels = None
depends_on = None

COUNTED_TABLES = (
    ("posts", "view_count_non_negative"),
    ("lost_pets", "lost_pets_view_count_non_negative"),
    ("adoption_posts", "adoption_posts_view_count_non_negative"),
)


def upgrade() -> None:
    op.create_table(
        "post_views",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("post_kind", sa.Text(), nullable=False),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("user_id", postgresql.UUID(as_uuid=True)),
        sa.Column("guest_key", sa.Text()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("post_kind", "post_id", "user_id", name="uq_post_views_user"),
        sa.UniqueConstraint("post_kind", "post_id", "guest_key", name="uq_post_views_guest"),
        sa.CheckConstraint(
            "post_kind IN ('post', 'lost_pet', 'adoption')", name="ck_post_views_kind"
        ),
        sa.CheckConstraint(
            "(user_id IS NULL) <> (guest_key IS NULL)", name="ck_post_views_one_viewer"
        ),
    )
    op.create_index("idx_post_views_user", "post_views", ["user_id"])
    for table, check_name in COUNTED_TABLES:
        op.add_column(
            table,
            sa.Column("view_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        )
        op.create_check_constraint(check_name, table, "view_count >= 0")


def downgrade() -> None:
    for table, check_name in COUNTED_TABLES:
        op.drop_constraint(check_name, table, type_="check")
        op.drop_column(table, "view_count")
    op.drop_index("idx_post_views_user", table_name="post_views")
    op.drop_table("post_views")
