from __future__ import annotations

import pytest
from geoalchemy2 import Geography, WKTElement
from sqlalchemy import cast, func, select
from sqlalchemy.exc import IntegrityError

from app.infrastructure.db.models import schema
from app.infrastructure.repositories.base import RepositoryBase, SoftDeleteRepository


def _unique_email(prefix: str) -> str:
    from uuid import uuid4

    return f"{prefix}-{uuid4().hex}@example.com"


def test_session_commit_and_rollback(db_session_manager) -> None:
    committed_email = _unique_email("commit")
    rolled_back_email = _unique_email("rollback")

    with db_session_manager.session_scope() as session:
        session.add(schema.User(email=committed_email, name="Commit Case"))

    with db_session_manager.session_scope() as session:
        committed_user = session.scalar(
            select(schema.User).where(schema.User.email == committed_email)
        )
        assert committed_user is not None
        assert committed_user.id is not None
        assert committed_user.registered_at.tzinfo is not None
        assert committed_user.is_active is True

    try:
        with db_session_manager.session_scope() as session:
            session.add(schema.User(email=rolled_back_email))
            raise RuntimeError("force rollback")
    except RuntimeError:
        pass

    with db_session_manager.session_scope() as session:
        rolled_back_user = session.scalar(
            select(schema.User).where(schema.User.email == rolled_back_email)
        )
        assert rolled_back_user is None


def test_repository_operations_use_the_database(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        user = schema.User(email=_unique_email("repo"), name="Repository User")
        cat = schema.Cat(status=schema.CatStatus.UNKNOWN, name="Repository Cat")
        user_repo = RepositoryBase(session, schema.User)
        cat_repo = SoftDeleteRepository(session, schema.Cat)

        user_repo.add(user)
        cat_repo.add(cat)
        session.flush()

        fetched_user = user_repo.get_by_id(user.id)
        assert fetched_user is not None
        assert fetched_user.email == user.email
        assert any(item.id == user.id for item in user_repo.list_all())

        cat_repo.soft_delete(cat)
        session.flush()
        assert cat.deleted_at is not None

        cat_repo.restore(cat)
        session.flush()
        assert cat.deleted_at is None


def test_unique_constraint_and_check_constraint_enforcement(integration_session) -> None:
    session = integration_session

    user = schema.User(email=_unique_email("constraint"), name="Constraint User")
    cat = schema.Cat(status=schema.CatStatus.UNKNOWN, name="Constraint Cat")
    session.add_all([user, cat])
    session.flush()

    post = schema.Post(
        cat_id=cat.id,
        user_id=user.id,
        photo_url="https://example.com/post.jpg",
        location=WKTElement("POINT(69.2500 41.3000)", srid=4326),
    )
    session.add(post)
    session.flush()

    like = schema.Like(post_id=post.id, user_id=user.id)
    session.add(like)
    session.flush()

    duplicate_like = schema.Like(post_id=post.id, user_id=user.id)
    session.add(duplicate_like)
    with pytest.raises(IntegrityError):
        session.flush()
    session.rollback()

    user = schema.User(email=_unique_email("constraint-merge"), name="Constraint Merge User")
    cat = schema.Cat(status=schema.CatStatus.UNKNOWN, name="Constraint Merge Cat")
    session.add_all([user, cat])
    session.flush()

    cat.merged_into = cat.id
    session.add(cat)
    with pytest.raises(IntegrityError):
        session.flush()
    session.rollback()


def test_foreign_key_delete_behavior_sets_user_references_to_null(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        user = schema.User(email=_unique_email("fk"), name="FK User")
        cat = schema.Cat(status=schema.CatStatus.UNKNOWN, name="FK Cat")
        session.add_all([user, cat])
        session.flush()

        post = schema.Post(
            cat_id=cat.id,
            user_id=user.id,
            photo_url="https://example.com/post.jpg",
            location=WKTElement("POINT(69.2500 41.3000)", srid=4326),
        )
        session.add(post)
        session.flush()

        like = schema.Like(post_id=post.id, user_id=user.id)
        session.add(like)
        session.flush()

        session.delete(user)
        session.flush()
        session.refresh(post)
        assert post.user_id is None
        assert session.scalar(select(schema.Like).where(schema.Like.id == like.id)) is None


def test_geospatial_insertion_and_nearby_distance_query(db_session_manager) -> None:
    with db_session_manager.session_scope() as session:
        user = schema.User(email=_unique_email("geo"), name="Geo User")
        cat = schema.Cat(status=schema.CatStatus.UNKNOWN, name="Geo Cat")
        session.add_all([user, cat])
        session.flush()

        origin = schema.Post(
            cat_id=cat.id,
            user_id=user.id,
            photo_url="https://example.com/origin.jpg",
            location=WKTElement("POINT(69.2500 41.3000)", srid=4326),
        )
        nearby = schema.Post(
            cat_id=cat.id,
            user_id=user.id,
            photo_url="https://example.com/nearby.jpg",
            location=WKTElement("POINT(69.2504 41.3004)", srid=4326),
        )
        far = schema.Post(
            cat_id=cat.id,
            user_id=user.id,
            photo_url="https://example.com/far.jpg",
            location=WKTElement("POINT(69.2700 41.3200)", srid=4326),
        )
        session.add_all([origin, nearby, far])
        session.flush()
        session.refresh(origin)

        assert origin.latitude is not None
        assert origin.longitude is not None
        assert abs(origin.latitude - 41.3) < 0.01
        assert abs(origin.longitude - 69.25) < 0.01
        assert origin.created_at.tzinfo is not None
        assert origin.updated_at.tzinfo is not None
        assert origin.deleted_at is None

        origin_geography = func.ST_SetSRID(func.ST_MakePoint(69.25, 41.3), 4326).cast(Geography)
        nearby_statement = select(schema.Post.id).where(
            func.ST_DWithin(cast(schema.Post.location, Geography), origin_geography, 100)
        )
        nearby_ids = set(session.scalars(nearby_statement).all())

        assert origin.id in nearby_ids
        assert nearby.id in nearby_ids
        assert far.id not in nearby_ids
