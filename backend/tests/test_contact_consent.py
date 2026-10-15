"""Contact-visibility consent for lost-pet and adoption posts (docs/CONTACT_PRIVACY.md).

Clients that show the new checkbox declare `X-Contact-Mode: reveal` and must send consent; older
clients send neither and keep working. An explicit refusal is never overridden.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from test_posts import (  # noqa: E402,F401
    _create_user_with_token,
    _jpeg_bytes,
    client,
    posts_runtime,
)

REVEAL = {"X-Contact-Mode": "reveal"}


def _owner(posts_runtime, email):
    from app.infrastructure.db.models import schema

    user, token = _create_user_with_token(
        posts_runtime.db_session_manager, posts_runtime.token_service, email=email
    )
    with posts_runtime.db_session_manager.session_scope() as session:
        session.get(schema.User, user.id).phone_number = "+998 90 123 45 67"
    return {"Authorization": f"Bearer {token}"}


def _files():
    return [("photos", ("pet.jpg", _jpeg_bytes(), "image/jpeg"))]


def _adoption(client, headers, **data):
    return client.post(
        "/api/v1/adoption-posts",
        headers=headers,
        data={"pet_name": "Mittens", **data},
        files=_files(),
    )


def _lost(client, headers):
    return client.post(
        "/api/v1/lost-pets",
        headers=headers,
        data={
            "pet_name": "Rex",
            "last_seen_location": json.dumps({"latitude": 41.3, "longitude": 69.25}),
            "owner_phone_publication_consent": "true",
        },
        files=_files(),
    )


def _stored(posts_runtime, model, post_id):
    with posts_runtime.db_session_manager.session_scope() as session:
        row = session.get(model, post_id)
        return row.contact_consent_version, row.contact_consent_at


def test_older_adoption_clients_without_a_checkbox_still_create_posts(
    client, posts_runtime
) -> None:
    from app.infrastructure.db.models import schema

    created = _adoption(client, _owner(posts_runtime, "legacy-adopt@example.com"))
    assert created.status_code == 201, created.text
    version, consented_at = _stored(
        posts_runtime, schema.AdoptionPost, created.json()["data"]["id"]
    )
    assert version is None and consented_at is None


def test_new_adoption_clients_must_send_the_checkbox_checked(client, posts_runtime) -> None:
    headers = _owner(posts_runtime, "new-adopt@example.com")
    for data in ({}, {"owner_contact_consent": "false"}):
        refused = client.post(
            "/api/v1/adoption-posts",
            headers={**headers, **REVEAL},
            data={"pet_name": "Mittens", **data},
            files=_files(),
        )
        assert refused.status_code == 422, data
        assert refused.json()["error"]["code"] == "CONTACT_CONSENT_REQUIRED"


def test_explicit_refusal_is_respected_even_without_the_header(client, posts_runtime) -> None:
    refused = _adoption(
        client, _owner(posts_runtime, "refuse-adopt@example.com"), owner_contact_consent="false"
    )
    assert refused.status_code == 422
    assert refused.json()["error"]["code"] == "CONTACT_CONSENT_REQUIRED"


def test_consent_version_and_time_are_recorded(client, posts_runtime) -> None:
    from app.infrastructure.db.models import schema

    headers = _owner(posts_runtime, "consent-ok@example.com")
    adoption = client.post(
        "/api/v1/adoption-posts",
        headers={**headers, **REVEAL},
        data={"pet_name": "Mittens", "owner_contact_consent": "true"},
        files=_files(),
    )
    assert adoption.status_code == 201, adoption.text
    version, consented_at = _stored(
        posts_runtime, schema.AdoptionPost, adoption.json()["data"]["id"]
    )
    assert version == 1 and consented_at is not None

    lost = client.post(
        "/api/v1/lost-pets",
        headers={**headers, **REVEAL},
        data={
            "pet_name": "Rex",
            "last_seen_location": json.dumps({"latitude": 41.3, "longitude": 69.25}),
            "owner_phone_publication_consent": "true",
        },
        files=_files(),
    )
    assert lost.status_code == 201, lost.text
    version, consented_at = _stored(posts_runtime, schema.LostPet, lost.json()["data"]["id"])
    assert version == 1 and consented_at is not None

    legacy = _lost(client, headers)
    assert legacy.status_code == 201, legacy.text
    version, consented_at = _stored(posts_runtime, schema.LostPet, legacy.json()["data"]["id"])
    assert version is None and consented_at is None


def test_lost_pet_still_requires_the_existing_consent_flag(client, posts_runtime) -> None:
    refused = client.post(
        "/api/v1/lost-pets",
        headers={**_owner(posts_runtime, "lost-refuse@example.com"), **REVEAL},
        data={
            "pet_name": "Rex",
            "last_seen_location": json.dumps({"latitude": 41.3, "longitude": 69.25}),
            "owner_phone_publication_consent": "false",
        },
        files=_files(),
    )
    assert refused.status_code == 422
