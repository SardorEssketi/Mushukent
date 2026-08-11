"""Add adoption posts.

Revision ID: 20260810_0012
Revises: 20260808_0011
Create Date: 2026-08-10
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260810_0012"
down_revision: str | None = "20260808_0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "adoption_posts",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("pet_name", sa.Text(), nullable=False),
        sa.Column("owner_phone_number", sa.Text(), nullable=False),
        sa.Column("owner_telegram_username", sa.Text(), nullable=True),
        sa.Column(
            "owner_phone_publication_consent",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column("additional_info", sa.Text(), nullable=True),
        sa.Column("is_public", sa.Boolean(), server_default=sa.text("true"), nullable=False),
        sa.Column("comment_count", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "comment_count >= 0",
            name="adoption_posts_comment_count_non_negative",
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_adoption_posts_created_at",
        "adoption_posts",
        ["created_at"],
        unique=False,
    )
    op.create_index(
        "idx_adoption_posts_active_created_at",
        "adoption_posts",
        ["created_at"],
        unique=False,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index("idx_adoption_posts_user_id", "adoption_posts", ["user_id"], unique=False)

    op.create_table(
        "adoption_post_photos",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("adoption_post_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("photo_url", sa.Text(), nullable=False),
        sa.Column("thumb_url", sa.Text(), nullable=True),
        sa.Column("position", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint("position >= 0", name="adoption_post_photo_position_non_negative"),
        sa.ForeignKeyConstraint(["adoption_post_id"], ["adoption_posts.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_adoption_post_photos_post_id_position",
        "adoption_post_photos",
        ["adoption_post_id", "position"],
        unique=False,
    )

    op.add_column(
        "comments",
        sa.Column("adoption_post_id", postgresql.UUID(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "comments_adoption_post_id_fkey",
        "comments",
        "adoption_posts",
        ["adoption_post_id"],
        ["id"],
        ondelete="CASCADE",
    )
    op.create_index(
        "idx_comments_adoption_post_id",
        "comments",
        ["adoption_post_id"],
        unique=False,
    )
    op.drop_constraint("comments_exactly_one_target", "comments", type_="check")
    op.create_check_constraint(
        "comments_exactly_one_target",
        "comments",
        "((post_id IS NOT NULL)::int + "
        "(lost_pet_id IS NOT NULL)::int + "
        "(adoption_post_id IS NOT NULL)::int) = 1",
    )


def downgrade() -> None:
    op.drop_constraint("comments_exactly_one_target", "comments", type_="check")
    op.create_check_constraint(
        "comments_exactly_one_target",
        "comments",
        "(post_id IS NOT NULL AND lost_pet_id IS NULL) OR "
        "(post_id IS NULL AND lost_pet_id IS NOT NULL)",
    )
    op.drop_index("idx_comments_adoption_post_id", table_name="comments")
    op.drop_constraint("comments_adoption_post_id_fkey", "comments", type_="foreignkey")
    op.drop_column("comments", "adoption_post_id")
    op.drop_index(
        "idx_adoption_post_photos_post_id_position",
        table_name="adoption_post_photos",
    )
    op.drop_table("adoption_post_photos")
    op.drop_index("idx_adoption_posts_user_id", table_name="adoption_posts")
    op.drop_index(
        "idx_adoption_posts_active_created_at",
        table_name="adoption_posts",
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.drop_index("idx_adoption_posts_created_at", table_name="adoption_posts")
    op.drop_table("adoption_posts")
