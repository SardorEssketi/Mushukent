"""Contact-visibility consent for lost-pet and adoption posts (docs/CONTACT_PRIVACY.md).

The current client has no checkbox: the profile phone is the consent, and it sends no consent
field (recorded as version 2). Older clients with the checkbox send `true` (version 1) and keep
working; an explicit `false` is always refused. Clients without `X-Contact-Mode: reveal` record
no version, as before. A phone in the profile is still required.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from test_posts import (  # noqa: E402,F401
    _create_user_with_token,
    _jpeg_bytes,
    client,
    posts_runtime,
)

REVEAL = {"X-Contact-Mode": "reveal"}
LOCATION = json.dumps({"latitude": 41.3, "longitude": 69.25})


def _owner(posts_runtime, email, *, phone: str | None = "+998 90 123 45 67"):
    from app.infrastructure.db.models import schema

    user, token = _create_user_with_token(
        posts_runtime.db_session_manager, posts_runtime.token_service, email=email
    )
    with posts_runtime.db_session_manager.session_scope() as session:
        session.get(schema.User, user.id).phone_number = phone
    return {"Authorization": f"Bearer {token}"}


def _files():
    return [("photos", ("pet.jpg", _jpeg_bytes(), "image/jpeg"))]


def _create(client, kind: str, headers, consent: str | None):
    """Create a post; ``consent=None`` leaves the consent field out of the form entirely."""
    if kind == "adoption":
        path, field, data = "/api/v1/adoption-posts", "owner_contact_consent", {}
    else:
        path, field = "/api/v1/lost-pets", "owner_phone_publication_consent"
        data = {"last_seen_location": LOCATION}
    data = {"pet_name": "Mittens", **data}
    if consent is not None:
        data[field] = consent
    return client.post(path, headers=headers, data=data, files=_files())


def _stored(posts_runtime, kind: str, post_id):
    from app.infrastructure.db.models import schema

    model = schema.AdoptionPost if kind == "adoption" else schema.LostPet
    with posts_runtime.db_session_manager.session_scope() as session:
        row = session.get(model, post_id)
        return row.contact_consent_version, row.contact_consent_at, row.owner_phone_number


KINDS = ("adoption", "lost")


@pytest.mark.parametrize("kind", KINDS)
def test_current_client_without_a_consent_field_creates_the_post(
    client, posts_runtime, kind
) -> None:
    headers = {**_owner(posts_runtime, f"no-field-{kind}@example.com"), **REVEAL}

    created = _create(client, kind, headers, consent=None)

    assert created.status_code == 201, created.text
    version, consented_at, phone = _stored(posts_runtime, kind, created.json()["data"]["id"])
    assert version == 2 and consented_at is not None
    assert phone == "+998 90 123 4567"


@pytest.mark.parametrize("kind", KINDS)
def test_older_client_with_the_checkbox_ticked_still_works(client, posts_runtime, kind) -> None:
    headers = {**_owner(posts_runtime, f"ticked-{kind}@example.com"), **REVEAL}

    created = _create(client, kind, headers, consent="true")

    assert created.status_code == 201, created.text
    version, consented_at, _ = _stored(posts_runtime, kind, created.json()["data"]["id"])
    assert version == 1 and consented_at is not None


@pytest.mark.parametrize("kind", KINDS)
@pytest.mark.parametrize("reveal", [True, False])
def test_explicit_refusal_is_always_respected(client, posts_runtime, kind, reveal) -> None:
    headers = _owner(posts_runtime, f"refuse-{kind}-{reveal}@example.com")
    if reveal:
        headers = {**headers, **REVEAL}

    refused = _create(client, kind, headers, consent="false")

    assert refused.status_code == 422
    expected = (
        "CONTACT_CONSENT_REQUIRED" if kind == "adoption" else ("PHONE_PUBLICATION_CONSENT_REQUIRED")
    )
    assert refused.json()["error"]["code"] == expected


@pytest.mark.parametrize("kind", KINDS)
@pytest.mark.parametrize("consent", [None, "true"])
def test_clients_without_the_reveal_header_record_no_version(
    client, posts_runtime, kind, consent
) -> None:
    created = _create(
        client, kind, _owner(posts_runtime, f"legacy-{kind}-{consent}@example.com"), consent
    )

    assert created.status_code == 201, created.text
    version, consented_at, _ = _stored(posts_runtime, kind, created.json()["data"]["id"])
    assert version is None and consented_at is None


@pytest.mark.parametrize("kind", KINDS)
def test_a_profile_phone_is_still_required(client, posts_runtime, kind) -> None:
    headers = {**_owner(posts_runtime, f"no-phone-{kind}@example.com", phone=None), **REVEAL}

    refused = _create(client, kind, headers, consent=None)

    assert refused.status_code == 403
    assert refused.json()["error"]["code"] == "PHONE_NUMBER_REQUIRED"


def test_consent_version_helper() -> None:
    from app.features.contact_reveal.service import (
        CONTACT_CONSENT_CHECKBOX,
        CONTACT_CONSENT_PROFILE_PHONE,
        contact_consent_refused,
        contact_consent_version,
    )

    assert contact_consent_version(None, reveal_mode=True) == CONTACT_CONSENT_PROFILE_PHONE == 2
    assert contact_consent_version(True, reveal_mode=True) == CONTACT_CONSENT_CHECKBOX == 1
    assert contact_consent_version(None, reveal_mode=False) is None
    assert contact_consent_version(True, reveal_mode=False) is None
    assert contact_consent_refused(False)
    assert not contact_consent_refused(None)
    assert not contact_consent_refused(True)
