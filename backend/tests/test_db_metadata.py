from __future__ import annotations

from pathlib import Path

from geoalchemy2 import Geometry
from sqlalchemy import Computed, UniqueConstraint
from sqlalchemy.dialects.postgresql import ENUM, JSONB

from app.infrastructure.db.base import NAMING_CONVENTION, Base
from app.infrastructure.db.models import schema


def test_metadata_discovers_all_mvp_tables() -> None:
    assert set(Base.metadata.tables) == {
        "users",
        "cats",
        "posts",
        "comments",
        "likes",
        "reports",
        "leaderboard_cache",
    }
    assert Base.metadata.naming_convention == NAMING_CONVENTION


def test_table_definitions_match_database_contract() -> None:
    users = schema.User.__table__
    cats = schema.Cat.__table__
    posts = schema.Post.__table__
    comments = schema.Comment.__table__
    likes = schema.Like.__table__
    reports = schema.Report.__table__
    leaderboard_cache = schema.LeaderboardCache.__table__

    assert users.c.id.server_default.arg.text == "gen_random_uuid()"
    assert users.c.registered_at.type.timezone is True
    assert users.c.email.unique is True

    assert isinstance(cats.c.status.type, ENUM)
    assert cats.c.status.type.name == "cat_status"
    assert isinstance(cats.c.canonical_location.type, Geometry)
    assert cats.c.canonical_location.type.srid == 4326
    assert cats.c.created_at.type.timezone is True
    assert cats.c.updated_at.type.timezone is True
    assert cats.c.deleted_at.type.timezone is True

    assert isinstance(posts.c.status.type, ENUM)
    assert isinstance(posts.c.location.type, Geometry)
    assert posts.c.location.type.srid == 4326
    assert isinstance(posts.c.latitude.computed, Computed)
    assert isinstance(posts.c.longitude.computed, Computed)
    assert posts.c.latitude.computed.persisted is True
    assert posts.c.longitude.computed.persisted is True
    assert posts.c.created_at.type.timezone is True
    assert posts.c.updated_at.type.timezone is True
    assert posts.c.deleted_at.type.timezone is True

    assert comments.c.deleted_at.type.timezone is True
    assert likes.constraints
    assert any(
        isinstance(constraint, UniqueConstraint)
        and {column.name for column in constraint.columns} == {"post_id", "user_id"}
        for constraint in likes.constraints
    )

    assert isinstance(reports.c.metadata.type, JSONB)
    assert isinstance(reports.c.target_type.type, ENUM)
    assert isinstance(reports.c.status.type, ENUM)

    assert isinstance(leaderboard_cache.c.data.type, JSONB)
    assert leaderboard_cache.c.computed_at.type.timezone is True


def test_constraints_and_indexes_match_mvp_rules() -> None:
    cat_constraints = {constraint.name for constraint in schema.Cat.__table__.constraints}
    post_constraints = {constraint.name for constraint in schema.Post.__table__.constraints}
    like_constraints = {constraint.name for constraint in schema.Like.__table__.constraints}

    assert {
        "ck_cats_approximate_age_smallyears_range",
        "ck_cats_merged_into_not_self",
        "ck_cats_total_observations_non_negative",
        "ck_cats_total_contributors_non_negative",
        "ck_cats_total_likes_non_negative",
    } <= cat_constraints
    assert {
        "ck_posts_like_count_non_negative",
        "ck_posts_comment_count_non_negative",
    } <= post_constraints
    assert "uq_likes_post_id_user_id" in like_constraints

    index_names = {index.name for index in schema.Base.metadata.tables["posts"].indexes}
    assert {
        "posts_location_gist",
        "idx_posts_created_at",
        "idx_posts_active_created_at",
        "idx_posts_user_id",
        "idx_posts_cat_id",
    } <= index_names

    active_index = next(
        index
        for index in schema.Base.metadata.tables["posts"].indexes
        if index.name == "idx_posts_active_created_at"
    )
    assert str(active_index.dialect_options["postgresql"]["where"]) == "deleted_at IS NULL"

    cat_indexes = {index.name for index in schema.Base.metadata.tables["cats"].indexes}
    assert {"cats_canonical_location_gist", "idx_cats_created_at"} <= cat_indexes


def test_alembic_environment_discovers_base_metadata() -> None:
    env_path = Path(__file__).resolve().parents[1] / "alembic" / "env.py"
    env_text = env_path.read_text(encoding="utf-8")

    assert "from app.infrastructure.db import models as _models" in env_text
    assert "target_metadata = Base.metadata" in env_text
    assert Base.metadata is schema.Base.metadata
