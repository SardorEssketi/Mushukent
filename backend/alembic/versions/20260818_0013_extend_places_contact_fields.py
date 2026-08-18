"""Extend places with manual import contact fields.

Revision ID: 20260818_0013
Revises: 20260810_0012
Create Date: 2026-08-18
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "20260818_0013"
down_revision: str | None = "20260810_0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("places", sa.Column("phone_2", sa.Text(), nullable=True))
    op.add_column("places", sa.Column("instagram", sa.Text(), nullable=True))
    op.add_column("places", sa.Column("telegram", sa.Text(), nullable=True))
    op.add_column("places", sa.Column("days_off", sa.Text(), nullable=True))
    op.add_column("places", sa.Column("description", sa.Text(), nullable=True))
    op.create_table(
        "place_category_links",
        sa.Column("place_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "category",
            postgresql.ENUM(
                "pet_shop",
                "veterinary",
                "shelter",
                name="place_category",
                create_type=False,
            ),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["place_id"], ["places.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("place_id", "category", name="pk_place_category_links"),
    )
    op.execute(
        """
        INSERT INTO place_category_links (place_id, category)
        SELECT id, category
        FROM places
        ON CONFLICT DO NOTHING
        """
    )
    op.create_index(
        "idx_place_category_links_category",
        "place_category_links",
        ["category"],
        unique=False,
    )
    op.create_index(
        "uq_places_source_source_id",
        "places",
        ["source", "source_id"],
        unique=True,
        postgresql_where=sa.text("source_id IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("uq_places_source_source_id", table_name="places")
    op.drop_index("idx_place_category_links_category", table_name="place_category_links")
    op.drop_table("place_category_links")
    op.drop_column("places", "description")
    op.drop_column("places", "days_off")
    op.drop_column("places", "telegram")
    op.drop_column("places", "instagram")
    op.drop_column("places", "phone_2")
