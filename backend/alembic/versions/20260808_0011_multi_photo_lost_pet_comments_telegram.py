"""multi photo posts, lost pet comments, and telegram profile fields

Revision ID: 20260808_0011
Revises: 20260801_0010
Create Date: 2026-08-08
"""

from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = "20260808_0011"
down_revision: str | None = "20260801_0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("telegram_username", sa.Text(), nullable=True))
    op.add_column(
        "lost_pets",
        sa.Column("owner_telegram_username", sa.Text(), nullable=True),
    )
    op.add_column(
        "lost_pets",
        sa.Column("comment_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
    )
    op.create_check_constraint(
        "lost_pets_comment_count_non_negative",
        "lost_pets",
        "comment_count >= 0",
    )

    op.create_table(
        "post_photos",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("post_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("photo_url", sa.Text(), nullable=False),
        sa.Column("thumb_url", sa.Text(), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.CheckConstraint("position >= 0", name="post_photo_position_non_negative"),
        sa.ForeignKeyConstraint(["post_id"], ["posts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_post_photos_post_id_position",
        "post_photos",
        ["post_id", "position"],
        unique=False,
    )
    op.execute(
        """
        INSERT INTO post_photos (post_id, photo_url, thumb_url, position)
        SELECT id, photo_url, thumb_url, 0
        FROM posts
        WHERE photo_url IS NOT NULL AND photo_url NOT LIKE 'deleted://%'
        """
    )

    op.add_column(
        "comments",
        sa.Column("lost_pet_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.alter_column(
        "comments",
        "post_id",
        existing_type=postgresql.UUID(as_uuid=True),
        nullable=True,
    )
    op.create_foreign_key(
        "comments_lost_pet_id_fkey",
        "comments",
        "lost_pets",
        ["lost_pet_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_check_constraint(
        "comments_exactly_one_target",
        "comments",
        "(post_id IS NOT NULL AND lost_pet_id IS NULL) OR "
        "(post_id IS NULL AND lost_pet_id IS NOT NULL)",
    )
    op.create_index("idx_comments_lost_pet_id", "comments", ["lost_pet_id"], unique=False)


def downgrade() -> None:
    op.drop_index("idx_comments_lost_pet_id", table_name="comments")
    op.drop_constraint("comments_exactly_one_target", "comments", type_="check")
    op.drop_constraint("comments_lost_pet_id_fkey", "comments", type_="foreignkey")
    op.alter_column(
        "comments",
        "post_id",
        existing_type=postgresql.UUID(as_uuid=True),
        nullable=False,
    )
    op.drop_column("comments", "lost_pet_id")

    op.drop_index("idx_post_photos_post_id_position", table_name="post_photos")
    op.drop_table("post_photos")

    op.drop_constraint("lost_pets_comment_count_non_negative", "lost_pets", type_="check")
    op.drop_column("lost_pets", "comment_count")
    op.drop_column("lost_pets", "owner_telegram_username")
    op.drop_column("users", "telegram_username")
