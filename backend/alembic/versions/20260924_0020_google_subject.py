"""Store the stable Google identity on the existing user row.

Revision ID: 20260924_0020
Revises: 20260921_0019
"""

from alembic import op
import sqlalchemy as sa

revision = "20260924_0020"
down_revision = "20260921_0019"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("google_subject", sa.Text(), nullable=True))
    op.add_column(
        "users",
        sa.Column(
            "legacy_google_unbound", sa.Boolean(), nullable=False, server_default=sa.text("false")
        ),
    )
    op.execute(
        "UPDATE users SET legacy_google_unbound = true "
        "WHERE password_hash IS NULL AND email_verified = true AND is_active = true "
        "AND lower(split_part(email, '@', 2)) IN ('gmail.com', 'googlemail.com')"
    )
    op.create_unique_constraint("uq_users_google_subject", "users", ["google_subject"])


def downgrade() -> None:
    op.drop_constraint("uq_users_google_subject", "users", type_="unique")
    op.drop_column("users", "legacy_google_unbound")
    op.drop_column("users", "google_subject")
