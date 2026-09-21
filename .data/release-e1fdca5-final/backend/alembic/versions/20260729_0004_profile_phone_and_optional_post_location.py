"""Add profile phone and allow locationless feed posts.

Revision ID: 20260729_0004
Revises: 20260723_0001
Create Date: 2026-07-29 00:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from geoalchemy2 import Geometry

from alembic import op

revision: str = "20260729_0004"
down_revision: str | None = "20260723_0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("phone_number", sa.Text(), nullable=True))
    op.alter_column(
        "posts",
        "location",
        existing_type=Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=True,
    )


def downgrade() -> None:
    op.alter_column(
        "posts",
        "location",
        existing_type=Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
        nullable=False,
    )
    op.drop_column("users", "phone_number")
