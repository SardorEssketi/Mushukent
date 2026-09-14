"""initial database foundation

Revision ID: 20260723_0001
Revises:
Create Date: 2026-07-23 00:00:00.000000
"""

from __future__ import annotations

from alembic import op
import sqlalchemy as sa
from geoalchemy2 import Geometry
from sqlalchemy.dialects.postgresql import DOUBLE_PRECISION, JSONB, ENUM, UUID

# revision identifiers, used by Alembic.
revision = "20260723_0001"
down_revision = None
branch_labels = None
depends_on = None


cat_status = ENUM(
    "healthy",
    "injured",
    "needs_help",
    "adopted",
    "unknown",
    "feed",
    name="cat_status",
    create_type=False,
)

report_target_type = ENUM(
    "post",
    "comment",
    "user",
    "cat",
    "lost_pet",
    "adoption_post",
    name="report_target_type",
    create_type=False,
)

report_status = ENUM(
    "open",
    "resolved",
    "dismissed",
    name="report_status",
    create_type=False,
)

leaderboard_type = ENUM(
    "most_active",
    "most_popular",
    "top_helpers",
    name="leaderboard_type",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    op.execute(sa.text("CREATE EXTENSION IF NOT EXISTS postgis"))
    op.execute(sa.text("CREATE EXTENSION IF NOT EXISTS pgcrypto"))

    cat_status.create(bind, checkfirst=True)
    report_target_type.create(bind, checkfirst=True)
    report_status.create(bind, checkfirst=True)
    leaderboard_type.create(bind, checkfirst=True)

    op.create_table(
        "users",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("email", sa.Text(), nullable=False),
        sa.Column("email_verified", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("password_hash", sa.Text(), nullable=True),
        sa.Column("name", sa.Text(), nullable=True),
        sa.Column("avatar_url", sa.Text(), nullable=True),
        sa.Column("bio", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("is_moderator", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column(
            "registered_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("last_login_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_users")),
        sa.UniqueConstraint("email", name=op.f("uq_users_email")),
    )
    op.create_index("idx_users_registered_at", "users", ["registered_at"], unique=False)

    op.create_table(
        "cats",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("name", sa.Text(), nullable=True),
        sa.Column("status", cat_status, nullable=False, server_default=sa.text("'unknown'")),
        sa.Column("approximate_age_smallyears", sa.SmallInteger(), nullable=True),
        sa.Column(
            "created_by",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("first_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("last_seen_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cover_photo_url", sa.Text(), nullable=True),
        sa.Column(
            "canonical_location",
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=True,
        ),
        sa.Column("total_observations", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("total_contributors", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("total_likes", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column(
            "merged_into",
            UUID(as_uuid=True),
            sa.ForeignKey("cats.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            "approximate_age_smallyears IS NULL OR approximate_age_smallyears BETWEEN 0 AND 60",
            name=op.f("ck_cats_approximate_age_smallyears_range"),
        ),
        sa.CheckConstraint(
            "merged_into IS NULL OR merged_into <> id", name=op.f("ck_cats_merged_into_not_self")
        ),
        sa.CheckConstraint(
            "total_observations >= 0", name=op.f("ck_cats_total_observations_non_negative")
        ),
        sa.CheckConstraint(
            "total_contributors >= 0", name=op.f("ck_cats_total_contributors_non_negative")
        ),
        sa.CheckConstraint("total_likes >= 0", name=op.f("ck_cats_total_likes_non_negative")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_cats")),
    )
    op.create_index(
        "cats_canonical_location_gist",
        "cats",
        ["canonical_location"],
        unique=False,
        postgresql_using="gist",
    )
    op.create_index("idx_cats_created_at", "cats", ["created_at"], unique=False)

    op.create_table(
        "posts",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "cat_id",
            UUID(as_uuid=True),
            sa.ForeignKey("cats.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("photo_url", sa.Text(), nullable=False),
        sa.Column("thumb_url", sa.Text(), nullable=True),
        sa.Column(
            "location",
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=False,
        ),
        sa.Column(
            "latitude", DOUBLE_PRECISION(), sa.Computed("ST_Y(location::geometry)", persisted=True)
        ),
        sa.Column(
            "longitude", DOUBLE_PRECISION(), sa.Computed("ST_X(location::geometry)", persisted=True)
        ),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("status", cat_status, nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_public", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("like_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.Column("comment_count", sa.Integer(), nullable=False, server_default=sa.text("0")),
        sa.CheckConstraint("like_count >= 0", name=op.f("ck_posts_like_count_non_negative")),
        sa.CheckConstraint("comment_count >= 0", name=op.f("ck_posts_comment_count_non_negative")),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_posts")),
    )
    op.create_index(
        "posts_location_gist", "posts", ["location"], unique=False, postgresql_using="gist"
    )
    op.create_index("idx_posts_created_at", "posts", ["created_at"], unique=False)
    op.create_index(
        "idx_posts_active_created_at",
        "posts",
        ["created_at"],
        unique=False,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index("idx_posts_user_id", "posts", ["user_id"], unique=False)
    op.create_index("idx_posts_cat_id", "posts", ["cat_id"], unique=False)

    op.create_table(
        "comments",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "post_id",
            UUID(as_uuid=True),
            sa.ForeignKey("posts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_comments")),
    )
    op.create_index("idx_comments_post_id", "comments", ["post_id"], unique=False)
    op.create_index("idx_comments_user_id", "comments", ["user_id"], unique=False)

    op.create_table(
        "likes",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "post_id",
            UUID(as_uuid=True),
            sa.ForeignKey("posts.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "user_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_likes")),
        sa.UniqueConstraint("post_id", "user_id", name=op.f("uq_likes_post_id_user_id")),
    )
    op.create_index("idx_likes_post_id", "likes", ["post_id"], unique=False)
    op.create_index("idx_likes_user_id", "likes", ["user_id"], unique=False)

    op.create_table(
        "reports",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "reporter_id",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("target_type", report_target_type, nullable=False),
        sa.Column("target_id", UUID(as_uuid=True), nullable=False),
        sa.Column("reason", sa.Text(), nullable=True),
        sa.Column("metadata", JSONB(), nullable=True),
        sa.Column("status", report_status, nullable=False, server_default=sa.text("'open'")),
        sa.Column(
            "handled_by",
            UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("handled_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_reports")),
    )
    op.create_index("idx_reports_status", "reports", ["status"], unique=False)
    op.create_index("idx_reports_target", "reports", ["target_type", "target_id"], unique=False)

    op.create_table(
        "leaderboard_cache",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("leaderboard_type", leaderboard_type, nullable=False),
        sa.Column("period", sa.Text(), nullable=False),
        sa.Column("data", JSONB(), nullable=False),
        sa.Column(
            "computed_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.PrimaryKeyConstraint("id", name=op.f("pk_leaderboard_cache")),
    )
    op.create_index(
        "idx_leaderboard_type_period",
        "leaderboard_cache",
        ["leaderboard_type", "period"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_leaderboard_type_period", table_name="leaderboard_cache")
    op.drop_table("leaderboard_cache")

    op.drop_index("idx_reports_target", table_name="reports")
    op.drop_index("idx_reports_status", table_name="reports")
    op.drop_table("reports")

    op.drop_index("idx_likes_user_id", table_name="likes")
    op.drop_index("idx_likes_post_id", table_name="likes")
    op.drop_table("likes")

    op.drop_index("idx_comments_user_id", table_name="comments")
    op.drop_index("idx_comments_post_id", table_name="comments")
    op.drop_table("comments")

    op.drop_index("idx_posts_cat_id", table_name="posts")
    op.drop_index("idx_posts_user_id", table_name="posts")
    op.drop_index("idx_posts_active_created_at", table_name="posts")
    op.drop_index("idx_posts_created_at", table_name="posts")
    op.drop_index("posts_location_gist", table_name="posts")
    op.drop_table("posts")

    op.drop_index("idx_cats_created_at", table_name="cats")
    op.drop_index("cats_canonical_location_gist", table_name="cats")
    op.drop_table("cats")

    op.drop_index("idx_users_registered_at", table_name="users")
    op.drop_table("users")

    bind = op.get_bind()
    leaderboard_type.drop(bind, checkfirst=True)
    report_status.drop(bind, checkfirst=True)
    report_target_type.drop(bind, checkfirst=True)
    cat_status.drop(bind, checkfirst=True)
    op.execute(sa.text("DROP EXTENSION IF EXISTS postgis"))
    op.execute(sa.text("DROP EXTENSION IF EXISTS pgcrypto"))
