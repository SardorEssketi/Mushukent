"""Authorization regression tests for cat records (audit F-14, docs/CAT_EDITING.md).

Cat records are internal grouping entities: only the user who created one, or a moderator, may
change it, and a cover photo must be an image hosted on the platform's own media storage.
"""

from __future__ import annotations

import sys
from pathlib import Path
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).parent))
from test_cats import (  # noqa: E402,F401
    _create_user_with_token,
    cats_runtime,
    client,
)

from app.infrastructure.db.models import schema  # noqa: E402

API = "/api/v1/cats"


def _own_url(runtime, name: str) -> str:
    return f"https://storage.example/{runtime.fake_storage.bucket_name}/cats/covers/{name}"


def _headers(token: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {token}"}


def _make_cat(runtime, creator_id, name="Original") -> str:
    with runtime.db_session_manager.session_scope() as session:
        cat = schema.Cat(name=name, created_by=creator_id)
        session.add(cat)
        session.flush()
        return str(cat.id)


def _users(runtime):
    owner, owner_token = _create_user_with_token(
        runtime.db_session_manager, runtime.token_service, email=f"o-{uuid4().hex}@example.com"
    )
    other, other_token = _create_user_with_token(
        runtime.db_session_manager, runtime.token_service, email=f"x-{uuid4().hex}@example.com"
    )
    mod, mod_token = _create_user_with_token(
        runtime.db_session_manager,
        runtime.token_service,
        email=f"m-{uuid4().hex}@example.com",
        is_moderator=True,
    )
    return (owner, owner_token), (other, other_token), (mod, mod_token)


def _name(runtime, cat_id) -> str | None:
    with runtime.db_session_manager.session_scope() as session:
        return session.get(schema.Cat, cat_id).name


def test_other_users_cannot_edit_a_cat_they_did_not_create(client, cats_runtime) -> None:
    (owner, _), (_, other_token), _ = _users(cats_runtime)
    cat_id = _make_cat(cats_runtime, owner.id)
    for payload in (
        {"name": "Hacked"},
        {"canonical_location": {"latitude": 41.0, "longitude": 69.0}},
        {"approximate_age_smallyears": 3},
        {"cover_photo_url": _own_url(cats_runtime, "x.jpg")},
    ):
        response = client.patch(f"{API}/{cat_id}", headers=_headers(other_token), json=payload)
        assert response.status_code == 403, payload
    assert _name(cats_runtime, cat_id) == "Original"


def test_anonymous_requests_cannot_edit_cats(client, cats_runtime) -> None:
    (owner, _), _, _ = _users(cats_runtime)
    cat_id = _make_cat(cats_runtime, owner.id)
    assert client.patch(f"{API}/{cat_id}", json={"name": "Anon"}).status_code == 401


def test_creator_can_edit_their_own_cat(client, cats_runtime) -> None:
    (owner, owner_token), _, _ = _users(cats_runtime)
    cat_id = _make_cat(cats_runtime, owner.id)
    response = client.patch(
        f"{API}/{cat_id}", headers=_headers(owner_token), json={"name": "Renamed"}
    )
    assert response.status_code == 200
    assert _name(cats_runtime, cat_id) == "Renamed"


def test_moderators_can_edit_any_cat(client, cats_runtime) -> None:
    (owner, _), _, (_, mod_token) = _users(cats_runtime)
    cat_id = _make_cat(cats_runtime, owner.id)
    response = client.patch(
        f"{API}/{cat_id}", headers=_headers(mod_token), json={"name": "Moderated"}
    )
    assert response.status_code == 200
    assert _name(cats_runtime, cat_id) == "Moderated"


def test_cat_whose_creator_is_gone_is_editable_only_by_moderators(client, cats_runtime) -> None:
    _, (_, other_token), (_, mod_token) = _users(cats_runtime)
    cat_id = _make_cat(cats_runtime, None)
    assert (
        client.patch(
            f"{API}/{cat_id}", headers=_headers(other_token), json={"name": "Mine now"}
        ).status_code
        == 403
    )
    assert (
        client.patch(
            f"{API}/{cat_id}", headers=_headers(mod_token), json={"name": "Fixed"}
        ).status_code
        == 200
    )


def test_status_and_merge_remain_moderator_only_even_for_the_creator(client, cats_runtime) -> None:
    (owner, owner_token), _, _ = _users(cats_runtime)
    cat_id = _make_cat(cats_runtime, owner.id)
    other_cat = _make_cat(cats_runtime, owner.id)
    assert (
        client.patch(
            f"{API}/{cat_id}", headers=_headers(owner_token), json={"status": "healthy"}
        ).status_code
        == 403
    )
    assert (
        client.patch(
            f"{API}/{cat_id}", headers=_headers(owner_token), json={"merged_into": other_cat}
        ).status_code
        == 403
    )


def test_external_cover_photo_urls_are_rejected_for_edit_and_create(client, cats_runtime) -> None:
    (owner, owner_token), _, (_, mod_token) = _users(cats_runtime)
    cat_id = _make_cat(cats_runtime, owner.id)
    for url in (
        "http://169.254.169.254/latest/meta-data",
        "https://tracker.example.net/pixel.gif",
        "https://storage.example.evil.com/mushukistan-media/cats/covers/x.jpg",
        "https://other.example/mushukistan-media/cats/covers/x.jpg",
    ):
        for token in (owner_token, mod_token):  # the rule applies to moderators too
            response = client.patch(
                f"{API}/{cat_id}", headers=_headers(token), json={"cover_photo_url": url}
            )
            assert response.status_code == 422, url
            assert "cover_photo_url" in response.text
        created = client.post(API, headers=_headers(owner_token), json={"cover_photo_url": url})
        assert created.status_code == 422, url
    with cats_runtime.db_session_manager.session_scope() as session:
        assert session.get(schema.Cat, cat_id).cover_photo_url is None


def test_platform_hosted_cover_photo_urls_are_accepted(client, cats_runtime) -> None:
    (owner, owner_token), _, _ = _users(cats_runtime)
    url = _own_url(cats_runtime, "mine.jpg")
    created = client.post(API, headers=_headers(owner_token), json={"cover_photo_url": url})
    assert created.status_code == 201
    assert created.json()["data"]["cover_photo_url"] == url
    # PATCH accepts the same URL for the owner (the update path only applies uploaded files).
    cat_id = created.json()["data"]["id"]
    assert (
        client.patch(
            f"{API}/{cat_id}", headers=_headers(owner_token), json={"cover_photo_url": url}
        ).status_code
        == 200
    )
