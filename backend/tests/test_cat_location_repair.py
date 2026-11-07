"""AUTH-205 repair of cats left without a canonical location."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from uuid import UUID

import pytest
from geoalchemy2.elements import WKTElement
from sqlalchemy import Engine, func, select, text

from app.features.posts.domain.models import post_history_snapshot_from_values
from app.infrastructure.db.models import schema
from scripts.repair_cat_canonical_location import (
    apply_repairs,
    classify,
    find_candidates,
    main,
)

pytestmark = pytest.mark.integration


def _point(latitude: float, longitude: float) -> WKTElement:
    return WKTElement(f"POINT({longitude} {latitude})", srid=4326)


def _user(db_session_manager, email: str) -> UUID:
    with db_session_manager.session_scope() as session:
        user = schema.User(email=email, name="Repair user")
        session.add(user)
        session.flush()
        return user.id


def _cat_with_post(
    db_session_manager,
    *,
    user_id: UUID,
    post_location: tuple[float, float] | None,
    canonical_location: tuple[float, float] | None = None,
    post_user_id: UUID | None = None,
    post_created_offset: timedelta = timedelta(0),
    post_deleted: bool = False,
    cat_deleted: bool = False,
    kind: schema.PostKind = schema.PostKind.NEEDS_HELP,
) -> tuple[UUID, UUID]:
    created_at = datetime.now(UTC) - timedelta(hours=1)
    with db_session_manager.session_scope() as session:
        cat = schema.Cat(
            name="Named",
            created_by=user_id,
            created_at=created_at,
            canonical_location=_point(*canonical_location) if canonical_location else None,
            deleted_at=created_at if cat_deleted else None,
        )
        session.add(cat)
        session.flush()
        post = schema.Post(
            cat_id=cat.id,
            user_id=post_user_id or user_id,
            photo_url="https://storage.example/repair.jpg",
            location=_point(*post_location) if post_location else None,
            kind=kind,
            description="Needs help",
            is_public=True,
            created_at=created_at + post_created_offset,
            deleted_at=created_at if post_deleted else None,
        )
        session.add(post)
        session.flush()
        return cat.id, post.id


def _canonical(db_session_manager, cat_id: UUID) -> tuple[float, float] | None:
    with db_session_manager.session_scope() as session:
        row = session.execute(
            select(
                func.ST_Y(schema.Cat.canonical_location), func.ST_X(schema.Cat.canonical_location)
            ).where(schema.Cat.id == cat_id)
        ).one()
        return None if row[0] is None else (float(row[0]), float(row[1]))


def test_repair_sets_only_originating_post_location(
    integration_engine: Engine, db_session_manager
) -> None:
    owner = _user(db_session_manager, "repair-owner@example.com")
    other = _user(db_session_manager, "repair-other@example.com")

    affected, affected_post = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.31116078338159, 69.2797)
    )
    affected_observation, _ = _cat_with_post(
        db_session_manager,
        user_id=owner,
        post_location=(41.2, 69.2),
        kind=schema.PostKind.OBSERVATION,
    )
    legitimate, _ = _cat_with_post(
        db_session_manager,
        user_id=owner,
        post_location=(41.5, 69.5),
        canonical_location=(41.1, 69.1),
    )
    no_location, _ = _cat_with_post(db_session_manager, user_id=owner, post_location=None)
    deleted_post, _ = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.3, 69.3), post_deleted=True
    )
    deleted_cat, _ = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.3, 69.3), cat_deleted=True
    )
    # Not created in the same transaction as the cat (e.g. POST /cats, then a
    # later observation): never infer a location from it.
    later_post, _ = _cat_with_post(
        db_session_manager,
        user_id=owner,
        post_location=(41.3, 69.3),
        post_created_offset=timedelta(minutes=5),
    )
    # Someone else's post on the creator's cat is unrelated evidence.
    foreign_post, _ = _cat_with_post(
        db_session_manager, user_id=owner, post_user_id=other, post_location=(41.3, 69.3)
    )

    with integration_engine.begin() as connection:
        candidates = find_candidates(connection)
    assert {candidate.cat_id for candidate in candidates} == {affected, affected_observation}
    target = next(candidate for candidate in candidates if candidate.cat_id == affected)
    assert target.post_id == affected_post

    with integration_engine.begin() as connection:
        repaired = apply_repairs(connection, candidates)
    assert {candidate.cat_id for candidate in repaired} == {affected, affected_observation}

    assert _canonical(db_session_manager, affected) == (
        pytest.approx(41.31116078338159),
        pytest.approx(69.2797),
    )
    assert _canonical(db_session_manager, legitimate) == (pytest.approx(41.1), pytest.approx(69.1))
    for untouched in (no_location, deleted_post, deleted_cat, later_post, foreign_post):
        assert _canonical(db_session_manager, untouched) is None

    with db_session_manager.session_scope() as session:
        post_count = session.scalar(select(func.count()).select_from(schema.Post))
    assert post_count == 8

    with integration_engine.begin() as connection:
        reasons = {item.cat_id: item.reason for item in classify(connection).excluded}
    assert reasons == {
        no_location: "no_original_location",
        deleted_post: "originating_post_deleted",
        later_post: "no_originating_post",
        foreign_post: "no_originating_post",
    }

    # Idempotent: a second run finds and changes nothing.
    with integration_engine.begin() as connection:
        assert find_candidates(connection) == []
        assert apply_repairs(connection, candidates) == []


def _history(
    db_session_manager,
    *,
    post_id: UUID,
    before_location: tuple[float, float] | None,
    after_location: tuple[float, float] | None,
    created_at: datetime,
    before: dict | None = None,
) -> None:
    def snapshot(location):
        return post_history_snapshot_from_values(
            description="Needs help",
            kind="needs_help",
            status=None,
            location_latitude=location[0] if location else None,
            location_longitude=location[1] if location else None,
            is_public=True,
            photo_urls=[],
        )

    with db_session_manager.session_scope() as session:
        session.add(
            schema.PostHistory(
                post_id=post_id,
                action="edited",
                before=before if before is not None else snapshot(before_location),
                after=snapshot(after_location),
                created_at=created_at,
            )
        )


def test_repair_uses_original_location_from_edit_history(
    integration_engine: Engine, db_session_manager
) -> None:
    owner = _user(db_session_manager, "repair-history@example.com")
    edited_at = datetime.now(UTC) - timedelta(minutes=30)

    # Location moved twice after creation: the first edit's "before" is the
    # creation point, not the current point and not the intermediate one.
    moved, moved_post = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.33, 69.33)
    )
    _history(
        db_session_manager,
        post_id=moved_post,
        before_location=(41.31, 69.27),
        after_location=(41.32, 69.30),
        created_at=edited_at,
    )
    _history(
        db_session_manager,
        post_id=moved_post,
        before_location=(41.32, 69.30),
        after_location=(41.33, 69.33),
        created_at=edited_at + timedelta(minutes=5),
    )
    # Edited, but not its location.
    text_only, text_post = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.25, 69.25)
    )
    _history(
        db_session_manager,
        post_id=text_post,
        before_location=(41.25, 69.25),
        after_location=(41.25, 69.25),
        created_at=edited_at,
    )
    # Created without a point, location added by a later edit: the creation
    # contract left this cat unlocated (separate follow-up, not AUTH-205).
    added_later, added_post = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.3, 69.3)
    )
    _history(
        db_session_manager,
        post_id=added_post,
        before_location=None,
        after_location=(41.3, 69.3),
        created_at=edited_at,
    )
    # The owner removed the point: never publish it again.
    removed, removed_post = _cat_with_post(db_session_manager, user_id=owner, post_location=None)
    _history(
        db_session_manager,
        post_id=removed_post,
        before_location=(41.2, 69.2),
        after_location=None,
        created_at=edited_at,
    )
    # Two history rows tie for the earliest edit: the original is ambiguous.
    tied, tied_post = _cat_with_post(db_session_manager, user_id=owner, post_location=(41.4, 69.4))
    for location in ((41.1, 69.1), (41.15, 69.15)):
        _history(
            db_session_manager,
            post_id=tied_post,
            before_location=location,
            after_location=(41.4, 69.4),
            created_at=edited_at,
        )
    # A snapshot without a usable location is not evidence.
    malformed, malformed_post = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.4, 69.4)
    )
    _history(
        db_session_manager,
        post_id=malformed_post,
        before_location=None,
        after_location=(41.4, 69.4),
        created_at=edited_at,
        before={"location": {"latitude": "41.1", "longitude": 69.1}},
    )

    with integration_engine.begin() as connection:
        result = classify(connection)
    eligible = {candidate.cat_id: candidate for candidate in result.eligible}
    reasons = {item.cat_id: item.reason for item in result.excluded}

    assert set(eligible) == {moved, text_only}
    assert (eligible[moved].latitude, eligible[moved].longitude) == (41.31, 69.27)
    assert eligible[moved].location_edited is True
    assert eligible[text_only].location_edited is False
    assert reasons == {
        added_later: "no_original_location",
        removed: "location_removed_by_owner",
        tied: "original_location_ambiguous",
        malformed: "original_location_ambiguous",
    }

    with integration_engine.begin() as connection:
        skipped = classify(connection, skip_edited_locations=True)
    assert {candidate.cat_id for candidate in skipped.eligible} == {text_only}
    skipped_reasons = {item.cat_id: item.reason for item in skipped.excluded}
    assert skipped_reasons[moved] == "location_edited_skipped"

    # Classification (dry run) wrote nothing.
    for cat_id in (moved, text_only, added_later, removed, tied, malformed):
        assert _canonical(db_session_manager, cat_id) is None

    with integration_engine.begin() as connection:
        apply_repairs(connection, result.eligible)
    assert _canonical(db_session_manager, moved) == (pytest.approx(41.31), pytest.approx(69.27))
    assert _canonical(db_session_manager, text_only) == (
        pytest.approx(41.25),
        pytest.approx(69.25),
    )
    for cat_id in (added_later, removed, tied, malformed):
        assert _canonical(db_session_manager, cat_id) is None


def test_multiple_originating_posts_are_excluded(
    integration_engine: Engine, db_session_manager
) -> None:
    owner = _user(db_session_manager, "repair-multi@example.com")
    cat_id, first_post = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.3, 69.3)
    )
    with db_session_manager.session_scope() as session:
        first = session.get(schema.Post, first_post)
        session.add(
            schema.Post(
                cat_id=cat_id,
                user_id=owner,
                photo_url="https://storage.example/second.jpg",
                location=_point(41.4, 69.4),
                kind=schema.PostKind.NEEDS_HELP,
                description="Second",
                is_public=True,
                created_at=first.created_at,
            )
        )

    with integration_engine.begin() as connection:
        result = classify(connection)
    assert result.eligible == []
    assert [(item.cat_id, item.reason) for item in result.excluded] == [
        (cat_id, "multiple_originating_posts")
    ]


def test_repair_skips_cat_that_gained_location_after_selection(
    integration_engine: Engine, db_session_manager
) -> None:
    owner = _user(db_session_manager, "repair-race@example.com")
    cat_id, _ = _cat_with_post(db_session_manager, user_id=owner, post_location=(41.3, 69.3))
    with integration_engine.begin() as connection:
        candidates = find_candidates(connection)
    with integration_engine.begin() as connection:
        connection.execute(
            text(
                "UPDATE cats SET canonical_location = "
                "ST_SetSRID(ST_MakePoint(69.0, 41.0), 4326) WHERE id = :id"
            ),
            {"id": cat_id},
        )
    with integration_engine.begin() as connection:
        assert apply_repairs(connection, candidates) == []
    assert _canonical(db_session_manager, cat_id) == (pytest.approx(41.0), pytest.approx(69.0))


def test_cli_dry_run_writes_nothing_and_apply_requires_database_name(
    integration_engine: Engine,
    integration_database_url: str,
    db_session_manager,
    capsys: pytest.CaptureFixture[str],
) -> None:
    owner = _user(db_session_manager, "repair-cli@example.com")
    cat_id, post_id = _cat_with_post(db_session_manager, user_id=owner, post_location=(41.3, 69.3))

    assert main(["--database-url", integration_database_url]) == 0
    output = capsys.readouterr()
    assert str(cat_id) in output.out and str(post_id) in output.out
    assert '"applied": false' in output.out
    assert "1 eligible" in output.err
    assert _canonical(db_session_manager, cat_id) is None

    assert main(["--database-url", integration_database_url, "--apply"]) == 2
    assert (
        main(["--database-url", integration_database_url, "--apply", "--confirm-database", "wrong"])
        == 2
    )
    assert _canonical(db_session_manager, cat_id) is None

    with integration_engine.connect() as connection:
        database_name = connection.execute(text("SELECT current_database()")).scalar_one()
    capsys.readouterr()
    assert (
        main(
            [
                "--database-url",
                integration_database_url,
                "--apply",
                "--confirm-database",
                database_name,
            ]
        )
        == 0
    )
    assert '"applied": true' in capsys.readouterr().out
    assert _canonical(db_session_manager, cat_id) == (pytest.approx(41.3), pytest.approx(69.3))


def test_repaired_cat_becomes_visible_on_needs_help_map(
    monkeypatch: pytest.MonkeyPatch, integration_engine: Engine, db_session_manager
) -> None:
    from fastapi.testclient import TestClient

    from app.core.config import Settings
    from app.core.container import AppContainer
    from app.main import app

    monkeypatch.setenv("JWT_SECRET_KEY", "test-secret-key")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "google-client-id")
    app.state.container = AppContainer(settings=Settings(), db_session_manager=db_session_manager)
    app.dependency_overrides.clear()

    owner = _user(db_session_manager, "repair-map@example.com")
    cat_id, _ = _cat_with_post(
        db_session_manager, user_id=owner, post_location=(41.31116078338159, 69.2797)
    )
    params = {
        "filter": "recently_added",
        "kind": "needs_help",
        "bbox": "69.26,41.30,69.30,41.33",
    }

    with TestClient(app) as client:
        before = client.get("/api/v1/cats", params=params)
        assert before.status_code == 200
        assert str(cat_id) not in {item["id"] for item in before.json()["data"]["items"]}

        with integration_engine.begin() as connection:
            apply_repairs(connection, find_candidates(connection))

        after = client.get("/api/v1/cats", params=params)
        assert after.status_code == 200
        assert str(cat_id) in {item["id"] for item in after.json()["data"]["items"]}
