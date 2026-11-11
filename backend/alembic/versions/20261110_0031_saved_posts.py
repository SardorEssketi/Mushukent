"""Add saved_posts: cat posts a user saved for later.

Additive only: old application code ignores the new table, so rolling the application back does
not require a schema rollback.

Revision ID: 20261110_0031
Revises: 20261102_0030
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261110_0031"
down_revision = "20261102_0030"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "saved_posts",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["post_id"], ["posts.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("user_id", "post_id", name="uq_saved_posts_user_id_post_id"),
    )
    op.create_index(
        "idx_saved_posts_user_id_created_at",
        "saved_posts",
        ["user_id", "created_at", "id"],
    )
    op.create_index("idx_saved_posts_post_id", "saved_posts", ["post_id"])


def downgrade() -> None:
    op.drop_index("idx_saved_posts_post_id", table_name="saved_posts")
    op.drop_index("idx_saved_posts_user_id_created_at", table_name="saved_posts")
    op.drop_table("saved_posts")
