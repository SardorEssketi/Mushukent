"""Add lost pets.

Revision ID: 20260731_0008
Revises: 20260731_0007
Create Date: 2026-07-31
"""

from collections.abc import Sequence

import geoalchemy2
import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260731_0008"
down_revision: str | None = "20260731_0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "lost_pets",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("owner_phone_number", sa.Text(), nullable=False),
        sa.Column(
            "last_seen_location",
            geoalchemy2.types.Geometry(
                geometry_type="POINT",
                srid=4326,
                spatial_index=False,
                from_text="ST_GeomFromEWKT",
                name="geometry",
            ),
            nullable=False,
        ),
        sa.Column(
            "last_seen_latitude",
            postgresql.DOUBLE_PRECISION(),
            sa.Computed("ST_Y(last_seen_location::geometry)", persisted=True),
            nullable=True,
        ),
        sa.Column(
            "last_seen_longitude",
            postgresql.DOUBLE_PRECISION(),
            sa.Computed("ST_X(last_seen_location::geometry)", persisted=True),
            nullable=True,
        ),
        sa.Column("additional_info", sa.Text(), nullable=True),
        sa.Column("is_resolved", sa.Boolean(), server_default=sa.text("false"), nullable=False),
        sa.Column("is_public", sa.Boolean(), server_default=sa.text("true"), nullable=False),
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
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "lost_pets_last_seen_location_gist",
        "lost_pets",
        ["last_seen_location"],
        unique=False,
        postgresql_using="gist",
    )
    op.create_index("idx_lost_pets_created_at", "lost_pets", ["created_at"], unique=False)
    op.create_index(
        "idx_lost_pets_active_created_at",
        "lost_pets",
        ["created_at"],
        unique=False,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.create_index("idx_lost_pets_user_id", "lost_pets", ["user_id"], unique=False)

    op.create_table(
        "lost_pet_photos",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("lost_pet_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("photo_url", sa.Text(), nullable=False),
        sa.Column("thumb_url", sa.Text(), nullable=True),
        sa.Column("position", sa.Integer(), server_default=sa.text("0"), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.CheckConstraint("position >= 0", name="lost_pet_photo_position_non_negative"),
        sa.ForeignKeyConstraint(["lost_pet_id"], ["lost_pets.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "idx_lost_pet_photos_lost_pet_id_position",
        "lost_pet_photos",
        ["lost_pet_id", "position"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("idx_lost_pet_photos_lost_pet_id_position", table_name="lost_pet_photos")
    op.drop_table("lost_pet_photos")
    op.drop_index("idx_lost_pets_user_id", table_name="lost_pets")
    op.drop_index(
        "idx_lost_pets_active_created_at",
        table_name="lost_pets",
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    op.drop_index("idx_lost_pets_created_at", table_name="lost_pets")
    op.drop_index(
        "lost_pets_last_seen_location_gist", table_name="lost_pets", postgresql_using="gist"
    )
    op.drop_table("lost_pets")
