"""Enforce canonical email uniqueness without rewriting existing accounts.

Revision ID: 20260926_0021
Revises: 20260924_0020
"""

import sqlalchemy as sa

from alembic import op

revision = "20260926_0021"
down_revision = "20260924_0020"
branch_labels = None
depends_on = None


def upgrade() -> None:
    connection = op.get_bind()
    duplicate = connection.execute(
        sa.text(
            "SELECT lower(trim(email)) AS normalized_email "
            "FROM users GROUP BY lower(trim(email)) HAVING count(*) > 1 LIMIT 1"
        )
    ).first()
    if duplicate is not None:
        raise RuntimeError(
            "Cannot add normalized email uniqueness because legacy users contain a collision. "
            "Inspect with: SELECT lower(trim(email)), count(*), array_agg(id) FROM users "
            "GROUP BY lower(trim(email)) HAVING count(*) > 1. Resolve each account manually; "
            "do not merge user records automatically."
        )

    op.execute("CREATE UNIQUE INDEX uq_users_email_normalized ON users (lower(trim(email)))")


def downgrade() -> None:
    op.drop_index("uq_users_email_normalized", table_name="users")
