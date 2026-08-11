"""Add user preferred language.

Revision ID: 20260730_0006
Revises: 20260730_0005
Create Date: 2026-07-30 00:00:00.000000
"""

from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = "20260730_0006"
down_revision: str | None = "20260730_0005"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column(
            "preferred_language",
            sa.Text(),
            nullable=False,
            server_default=sa.text("'en'"),
        ),
    )
    op.create_check_constraint(
        op.f("ck_users_preferred_language_supported"),
        "users",
        "preferred_language IN ('en', 'uz', 'ru')",
    )


def downgrade() -> None:
    op.drop_constraint(op.f("ck_users_preferred_language_supported"), "users", type_="check")
    op.drop_column("users", "preferred_language")
