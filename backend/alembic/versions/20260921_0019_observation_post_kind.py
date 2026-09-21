"""Make the observation purpose explicit instead of inferring it from status.

Revision ID: 20260921_0019
Revises: 20260920_0018
Create Date: 2026-09-21
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision: str = "20260921_0019"
down_revision: str | None = "20260920_0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


post_kind = postgresql.ENUM(
    "observation",
    "needs_help",
    name="post_kind",
    create_type=False,
)


def upgrade() -> None:
    bind = op.get_bind()
    post_kind.create(bind, checkfirst=True)
    op.add_column(
        "posts",
        sa.Column(
            "kind",
            post_kind,
            nullable=False,
            server_default=sa.text("'observation'"),
        ),
    )
    # The pre-kind UI rendered post status first and fell back to cat status.
    # Preserve that visible meaning without changing either legacy status field.
    op.execute(
        sa.text(
            """
            UPDATE posts AS post
            SET kind = 'needs_help'::post_kind
            FROM cats AS cat
            WHERE post.cat_id = cat.id
              AND (
                post.status = 'needs_help'::cat_status
                OR (post.status IS NULL AND cat.status = 'needs_help'::cat_status)
              )
            """
        )
    )
    op.create_index("idx_posts_kind", "posts", ["kind"], unique=False)

    # Existing audit payloads record the former status field. Add the explicit
    # semantic value so moderator history remains self-contained after status
    # is no longer used to determine post purpose.
    op.execute(
        sa.text(
            """
            UPDATE post_history AS history
            SET before = history.before || jsonb_build_object(
                    'kind',
                    CASE WHEN history.before->>'status' = 'needs_help'
                         THEN 'needs_help' ELSE 'observation' END
                ),
                after = history.after || jsonb_build_object(
                    'kind', post.kind::text
                )
            FROM posts AS post
            WHERE history.post_id = post.id
            """
        )
    )


def downgrade() -> None:
    op.drop_index("idx_posts_kind", table_name="posts")
    op.drop_column("posts", "kind")
    post_kind.drop(op.get_bind(), checkfirst=True)
