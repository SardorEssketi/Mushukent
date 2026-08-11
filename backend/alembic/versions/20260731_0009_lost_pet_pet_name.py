"""add pet name to lost pets

Revision ID: 20260731_0009
Revises: 20260731_0008
Create Date: 2026-07-31 23:30:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op


revision: str = "20260731_0009"
down_revision: str | None = "20260731_0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("lost_pets", sa.Column("pet_name", sa.Text(), nullable=True))
    op.execute("UPDATE lost_pets SET pet_name = 'Unknown pet' WHERE pet_name IS NULL")
    op.alter_column("lost_pets", "pet_name", nullable=False)


def downgrade() -> None:
    op.drop_column("lost_pets", "pet_name")
