"""Record who deleted lost-pet and adoption posts; allow publication-removed notifications.

Additive: two nullable ``deleted_by_id`` columns (``ON DELETE SET NULL``) and one more allowed
``notifications.kind`` value. Existing rows are unchanged and old application code ignores the new
columns, so rolling the application back does not require a schema rollback.

Revision ID: 20261101_0029
Revises: 20261029_0028
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261101_0029"
down_revision = "20261029_0028"
branch_labels = None
depends_on = None

TABLES = ("lost_pets", "adoption_posts")
OLD_KINDS = "kind IN ('comment', 'reply', 'nearby_lost_pet')"
NEW_KINDS = "kind IN ('comment', 'reply', 'nearby_lost_pet', 'publication_removed')"


def upgrade() -> None:
    for table in TABLES:
        op.add_column(table, sa.Column("deleted_by_id", postgresql.UUID(as_uuid=True)))
        op.create_foreign_key(
            op.f(f"fk_{table}_deleted_by_id_users"),
            table,
            "users",
            ["deleted_by_id"],
            ["id"],
            ondelete="SET NULL",
        )
        op.create_index(f"idx_{table}_deleted_by_id", table, ["deleted_by_id"])

    op.drop_constraint(
        op.f("ck_notifications_notifications_kind_valid"), "notifications", type_="check"
    )
    op.create_check_constraint("notifications_kind_valid", "notifications", NEW_KINDS)


def downgrade() -> None:
    # Rows of the new kind cannot satisfy the old constraint. Their push jobs cascade with them;
    # old code also has no push copy for the kind, so remove any job of that kind explicitly.
    op.execute("DELETE FROM notification_push_jobs WHERE kind = 'publication_removed'")
    op.execute("DELETE FROM notifications WHERE kind = 'publication_removed'")
    op.drop_constraint(
        op.f("ck_notifications_notifications_kind_valid"), "notifications", type_="check"
    )
    op.create_check_constraint("notifications_kind_valid", "notifications", OLD_KINDS)

    for table in TABLES:
        op.drop_index(f"idx_{table}_deleted_by_id", table_name=table)
        op.drop_constraint(op.f(f"fk_{table}_deleted_by_id_users"), table, type_="foreignkey")
        op.drop_column(table, "deleted_by_id")
