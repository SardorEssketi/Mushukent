"""Persistent notifications, Android delivery jobs, and private alert preferences.

Revision ID: 20261007_0025
Revises: 20261002_0024
"""

import geoalchemy2
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "20261007_0025"
down_revision = "20261002_0024"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("users", sa.Column("last_active_at", sa.DateTime(timezone=True)))
    op.create_index(
        "idx_users_active_last_activity",
        "users",
        ["last_active_at"],
        postgresql_where=sa.text("is_active = true AND last_active_at IS NOT NULL"),
    )
    op.create_table(
        "notification_preferences",
        sa.Column("user_id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column("push_comments", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("push_replies", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("push_followups", sa.Boolean(), nullable=False, server_default=sa.true()),
        sa.Column("nearby_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column("inactivity_enabled", sa.Boolean(), nullable=False, server_default=sa.false()),
        sa.Column(
            "alert_location",
            geoalchemy2.Geometry(geometry_type="POINT", srid=4326, spatial_index=False),
        ),
        sa.Column("last_inactivity_cycle_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.CheckConstraint(
            "NOT nearby_enabled OR alert_location IS NOT NULL",
            name="notification_preferences_nearby_requires_location",
        ),
    )
    op.execute(
        "CREATE INDEX idx_notification_preferences_alert_geography "
        "ON notification_preferences USING gist ((alert_location::geography)) "
        "WHERE nearby_enabled = true"
    )
    op.create_table(
        "notifications",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("recipient_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("actor_id", postgresql.UUID(as_uuid=True)),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("target_kind", sa.Text(), nullable=False),
        sa.Column("target_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("comment_id", postgresql.UUID(as_uuid=True)),
        sa.Column("event_key", sa.Text(), nullable=False, unique=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("read_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["recipient_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["actor_id"], ["users.id"], ondelete="SET NULL"),
        sa.CheckConstraint(
            "kind IN ('comment', 'reply', 'nearby_lost_pet')", name="notifications_kind_valid"
        ),
        sa.CheckConstraint(
            "target_kind IN ('post', 'lost_pet', 'adoption_post')",
            name="notifications_target_kind_valid",
        ),
    )
    op.execute(
        "CREATE INDEX idx_notifications_recipient_page "
        "ON notifications (recipient_id, created_at DESC, id DESC)"
    )
    op.create_index(
        "idx_notifications_recipient_unread",
        "notifications",
        ["recipient_id"],
        postgresql_where=sa.text("read_at IS NULL"),
    )
    op.create_table(
        "notification_devices",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("platform", sa.Text(), nullable=False),
        sa.Column("token_hash", sa.Text(), nullable=False, unique=True),
        sa.Column("token_encrypted", sa.Text(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.CheckConstraint("platform = 'android'", name="notification_devices_platform_valid"),
    )
    op.create_index("idx_notification_devices_user", "notification_devices", ["user_id"])
    op.create_table(
        "notification_push_jobs",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column("recipient_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("device_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("notification_id", postgresql.UUID(as_uuid=True)),
        sa.Column("event_key", sa.Text(), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("target_kind", sa.Text()),
        sa.Column("target_id", postgresql.UUID(as_uuid=True)),
        sa.Column("activity_cycle_at", sa.DateTime(timezone=True)),
        sa.Column("status", sa.Text(), nullable=False, server_default="pending"),
        sa.Column("attempts", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "next_attempt_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.Column("lease_until", sa.DateTime(timezone=True)),
        sa.Column("sent_at", sa.DateTime(timezone=True)),
        sa.Column("last_error_code", sa.Text()),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.ForeignKeyConstraint(["recipient_id"], ["users.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["device_id"], ["notification_devices.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["notification_id"], ["notifications.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("event_key", "device_id", name="uq_notification_push_event_device"),
        sa.CheckConstraint(
            "status IN ('pending', 'sending', 'sent', 'failed', 'cancelled')",
            name="notification_push_jobs_status_valid",
        ),
        sa.CheckConstraint("attempts >= 0", name="notification_push_jobs_attempts_valid"),
    )
    op.create_index(
        "idx_notification_push_jobs_due",
        "notification_push_jobs",
        ["next_attempt_at"],
        postgresql_where=sa.text("status IN ('pending', 'sending')"),
    )
    op.create_index(
        "idx_notification_push_jobs_recipient", "notification_push_jobs", ["recipient_id"]
    )


def downgrade() -> None:
    op.drop_table("notification_push_jobs")
    op.drop_table("notification_devices")
    op.drop_table("notifications")
    op.drop_table("notification_preferences")
    op.drop_index("idx_users_active_last_activity", table_name="users")
    op.drop_column("users", "last_active_at")
