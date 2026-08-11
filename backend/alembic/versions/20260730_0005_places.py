"""Add cat-support places.

Revision ID: 20260730_0005
Revises: 20260729_0004
Create Date: 2026-07-30 00:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from geoalchemy2 import Geometry
from sqlalchemy.dialects.postgresql import DOUBLE_PRECISION, ENUM, UUID

from alembic import op

revision: str = "20260730_0005"
down_revision: str | None = "20260729_0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


place_category = ENUM(
    "pet_shop",
    "veterinary",
    "shelter",
    name="place_category",
    create_type=False,
)

place_source = ENUM(
    "osm",
    "manual",
    name="place_source",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    place_category.create(bind, checkfirst=True)
    place_source.create(bind, checkfirst=True)

    op.create_table(
        "places",
        sa.Column(
            "id",
            UUID(as_uuid=True),
            primary_key=True,
            nullable=False,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("category", place_category, nullable=False),
        sa.Column(
            "location",
            Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
            nullable=False,
        ),
        sa.Column(
            "latitude",
            DOUBLE_PRECISION(),
            sa.Computed("ST_Y(location::geometry)", persisted=True),
        ),
        sa.Column(
            "longitude",
            DOUBLE_PRECISION(),
            sa.Computed("ST_X(location::geometry)", persisted=True),
        ),
        sa.Column("address", sa.Text(), nullable=True),
        sa.Column("phone", sa.Text(), nullable=True),
        sa.Column("website", sa.Text(), nullable=True),
        sa.Column("opening_hours", sa.Text(), nullable=True),
        sa.Column("source", place_source, nullable=False, server_default=sa.text("'manual'")),
        sa.Column("source_id", sa.Text(), nullable=True),
        sa.Column("verified_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
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
        sa.PrimaryKeyConstraint("id", name=op.f("pk_places")),
    )
    op.create_index(
        "places_location_gist", "places", ["location"], unique=False, postgresql_using="gist"
    )
    op.create_index("idx_places_category", "places", ["category"], unique=False)
    op.create_index("idx_places_source", "places", ["source", "source_id"], unique=False)


def downgrade() -> None:
    op.drop_index("idx_places_source", table_name="places")
    op.drop_index("idx_places_category", table_name="places")
    op.drop_index("places_location_gist", table_name="places")
    op.drop_table("places")

    bind = op.get_bind()
    place_source.drop(bind, checkfirst=True)
    place_category.drop(bind, checkfirst=True)
