"""Inactivity reminders on by default; category choices become the user's own.

Owner decision (2026-11-25): inactivity reminders are ON by default.

- ``notification_preferences.inactivity_enabled`` gets ``server_default true`` (it was ``false``,
  although code has always inserted ``true``).
- Existing rows: every category is set to ``true``. Since the first production release with
  notifications (2026-10-13) the server forced all four categories to ``true`` on every read and
  the worker flipped any stored ``false`` back to ``true``; no released client ever offered a
  switch (the only client switches existed in unreleased commits of 2026-10-08..12). So ``true`` is
  what every user effectively had. From this release on the server stops forcing the categories
  and the new Android settings page lets users switch them off, which is why stored values must
  match the effective state first.
- Nearby consent, the private point and inactivity cycles are not touched.

Revision ID: 20261125_0037
Revises: 20261123_0036
"""

from __future__ import annotations

import sqlalchemy as sa

from alembic import op

revision = "20261125_0037"
down_revision = "20261123_0036"
branch_labels = None
depends_on = None

CATEGORIES = ("push_comments", "push_replies", "push_followups", "inactivity_enabled")


def upgrade() -> None:
    op.alter_column(
        "notification_preferences",
        "inactivity_enabled",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=sa.text("true"),
    )
    condition = " OR ".join(f"{column} IS NOT TRUE" for column in CATEGORIES)
    assignments = ", ".join(f"{column} = true" for column in CATEGORIES)
    op.execute(f"UPDATE notification_preferences SET {assignments} WHERE {condition}")


def downgrade() -> None:
    # Only the schema default is restored: user choices made after the upgrade are kept.
    op.alter_column(
        "notification_preferences",
        "inactivity_enabled",
        existing_type=sa.Boolean(),
        existing_nullable=False,
        server_default=sa.text("false"),
    )
