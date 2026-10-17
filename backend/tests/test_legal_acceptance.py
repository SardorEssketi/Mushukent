"""Versioned legal acceptance: outdated consent is handled, never assumed.

Rules under test (docs/CONTACT_PRIVACY.md, "Legal documents and acceptance versions"):
* sign-in (password and Google) keeps working when acceptance is outdated and reports it;
* acceptance is recorded only by an explicit request naming the current document versions;
* sessions are never invalidated and a failed or repeated acceptance is harmless.
"""

from __future__ import annotations

import sys
from datetime import UTC, datetime, timedelta
from pathlib import Path

from sqlalchemy import select

sys.path.insert(0, str(Path(__file__).parent))
from test_auth import (  # noqa: E402,F401
    CURRENT_PRIVACY_VERSION,
    CURRENT_TERMS_VERSION,
    PasslibPasswordHasher,
    SqlAlchemyAuthUserRepository,
    auth_runtime,
    client,
    schema,
)

PASSWORD = "StrongPass123"
CURRENT = {
    "accept_terms": True,
    "accept_privacy": True,
    "terms_version": CURRENT_TERMS_VERSION,
    "privacy_version": CURRENT_PRIVACY_VERSION,
}


def _user(auth_runtime, email: str, *, accepted: str | None = None, at: datetime | None = None):
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        user = SqlAlchemyAuthUserRepository(session).create(
            email=email,
            password_hash=PasslibPasswordHasher().hash_password(PASSWORD),
            name="Returning User",
            email_verified=True,
            is_moderator=False,
            accepted_terms_version=accepted,
            accepted_privacy_version=accepted,
            accepted_legal_at=at,
        )
        return user.id


def _stored(auth_runtime, email: str):
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        user = session.scalar(select(schema.User).where(schema.User.email == email))
        return user.accepted_terms_version, user.accepted_privacy_version, user.accepted_legal_at


def _login(client, email: str):
    response = client.post("/api/v1/auth/login", json={"email": email, "password": PASSWORD})
    assert response.status_code == 200, response.text
    data = response.json()["data"]
    return data, {"Authorization": f"Bearer {data['access_token']}"}


def test_current_versions_match_the_displayed_documents() -> None:
    root = Path(__file__).resolve().parents[2]
    for name, version in (
        ("TERMS_OF_SERVICE.md", CURRENT_TERMS_VERSION),
        ("PRIVACY_POLICY.md", CURRENT_PRIVACY_VERSION),
    ):
        assert f"Version: {version}" in (root / "docs/legal" / name).read_text(encoding="utf-8")


def test_password_login_with_outdated_acceptance_succeeds_and_reports_it(
    client, auth_runtime
) -> None:
    email = "old-terms@example.com"
    _user(auth_runtime, email, accepted="2026-08-01", at=datetime.now(UTC) - timedelta(days=60))
    data, _ = _login(client, email)
    assert data["user"]["legal_acceptance_required"] is True
    assert data["user"]["current_terms_version"] == CURRENT_TERMS_VERSION
    assert data["user"]["current_privacy_version"] == CURRENT_PRIVACY_VERSION
    # Logging in is not acceptance.
    assert _stored(auth_runtime, email)[0] == "2026-08-01"


def test_users_without_any_record_are_also_asked(client, auth_runtime) -> None:
    email = "never-accepted@example.com"
    _user(auth_runtime, email)
    data, headers = _login(client, email)
    assert data["user"]["legal_acceptance_required"] is True
    me = client.get("/api/v1/users/me", headers=headers).json()["data"]
    assert me["legal_acceptance_required"] is True


def test_explicit_acceptance_records_current_versions_and_time(client, auth_runtime) -> None:
    email = "accepts@example.com"
    _user(auth_runtime, email, accepted="2026-08-01", at=datetime.now(UTC) - timedelta(days=60))
    data, headers = _login(client, email)
    before = datetime.now(UTC)
    response = client.post("/api/v1/auth/legal/accept", headers=headers, json=CURRENT)
    assert response.status_code == 200, response.text
    assert response.json()["data"]["legal_acceptance_required"] is False
    terms, privacy, at = _stored(auth_runtime, email)
    assert (terms, privacy) == (CURRENT_TERMS_VERSION, CURRENT_PRIVACY_VERSION)
    assert before - timedelta(seconds=5) <= at <= datetime.now(UTC) + timedelta(seconds=5)
    me = client.get("/api/v1/users/me", headers=headers).json()["data"]
    assert me["legal_acceptance_required"] is False
    # The session that was already open keeps working, and so does its refresh token.
    refreshed = client.post("/api/v1/auth/refresh", json={"refresh_token": data["refresh_token"]})
    assert refreshed.status_code == 200
    assert refreshed.json()["data"]["user"]["legal_acceptance_required"] is False


def test_repeating_acceptance_keeps_the_original_time(client, auth_runtime) -> None:
    email = "twice@example.com"
    _user(auth_runtime, email)
    _, headers = _login(client, email)
    assert (
        client.post("/api/v1/auth/legal/accept", headers=headers, json=CURRENT).status_code == 200
    )
    first = _stored(auth_runtime, email)[2]
    assert (
        client.post("/api/v1/auth/legal/accept", headers=headers, json=CURRENT).status_code == 200
    )
    assert _stored(auth_runtime, email)[2] == first


def test_acceptance_needs_explicit_consent_to_both_documents(client, auth_runtime) -> None:
    email = "refuses@example.com"
    _user(auth_runtime, email)
    _, headers = _login(client, email)
    for body in (
        {**CURRENT, "accept_terms": False},
        {**CURRENT, "accept_privacy": False},
        {**CURRENT, "accept_terms": False, "accept_privacy": False},
    ):
        response = client.post("/api/v1/auth/legal/accept", headers=headers, json=body)
        assert response.status_code == 422
        assert response.json()["error"]["code"] == "LEGAL_ACCEPTANCE_REQUIRED"
    missing = client.post("/api/v1/auth/legal/accept", headers=headers, json={})
    assert missing.status_code == 422
    assert _stored(auth_runtime, email)[2] is None


def test_acceptance_of_a_stale_document_version_is_refused_with_the_current_ones(
    client, auth_runtime
) -> None:
    email = "stale@example.com"
    _user(auth_runtime, email)
    _, headers = _login(client, email)
    response = client.post(
        "/api/v1/auth/legal/accept",
        headers=headers,
        json={**CURRENT, "terms_version": "2026-08-01"},
    )
    assert response.status_code == 409
    error = response.json()["error"]
    assert error["code"] == "LEGAL_VERSION_MISMATCH"
    assert error["details"]["current_terms_version"] == CURRENT_TERMS_VERSION
    assert _stored(auth_runtime, email)[2] is None


def test_acceptance_requires_authentication_and_cannot_be_recorded_for_someone_else(
    client, auth_runtime
) -> None:
    victim = "victim@example.com"
    other = "other@example.com"
    _user(auth_runtime, victim)
    _user(auth_runtime, other)
    assert client.post("/api/v1/auth/legal/accept", json=CURRENT).status_code == 401
    _, other_headers = _login(client, other)
    assert (
        client.post("/api/v1/auth/legal/accept", headers=other_headers, json=CURRENT).status_code
        == 200
    )
    assert _stored(auth_runtime, victim)[2] is None
    assert _stored(auth_runtime, other)[2] is not None


def test_account_switch_evaluates_each_account_separately(client, auth_runtime) -> None:
    accepted_email, pending_email = "accepted@example.com", "pending@example.com"
    _user(auth_runtime, accepted_email, accepted=CURRENT_TERMS_VERSION, at=datetime.now(UTC))
    _user(auth_runtime, pending_email)
    first, first_headers = _login(client, accepted_email)
    assert first["user"]["legal_acceptance_required"] is False
    assert (
        client.post(
            "/api/v1/auth/logout",
            headers=first_headers,
            json={"refresh_token": first["refresh_token"]},
        ).status_code
        == 204
    )
    second, _ = _login(client, pending_email)
    assert second["user"]["legal_acceptance_required"] is True


def test_logout_and_public_reads_work_while_acceptance_is_pending(client, auth_runtime) -> None:
    email = "pending-logout@example.com"
    _user(auth_runtime, email)
    data, headers = _login(client, email)
    assert client.get("/api/v1/users/me", headers=headers).status_code == 200
    assert client.get("/api/v1/feed?filter=recent", headers=headers).status_code == 200
    assert (
        client.post(
            "/api/v1/auth/logout", headers=headers, json={"refresh_token": data["refresh_token"]}
        ).status_code
        == 204
    )


def test_google_sign_in_with_consent_records_it_and_without_does_not(client, auth_runtime) -> None:
    _, auth_service = auth_runtime
    with auth_service.db_session_manager.session_scope() as session:
        SqlAlchemyAuthUserRepository(session).create(
            email="google-user@gmail.com",
            password_hash=None,
            name="Google User",
            legacy_google_unbound=True,
            email_verified=True,
            is_moderator=False,
            accepted_terms_version="2026-08-01",
            accepted_privacy_version="2026-08-01",
            accepted_legal_at=datetime.now(UTC) - timedelta(days=30),
        )
    without = client.post("/api/v1/auth/google", json={"id_token": "google-id-token"})
    assert without.status_code == 200
    assert without.json()["data"]["user"]["legal_acceptance_required"] is True
    assert _stored(auth_runtime, "google-user@gmail.com")[0] == "2026-08-01"
    partial = client.post(
        "/api/v1/auth/google", json={"id_token": "google-id-token", "accept_terms": True}
    )
    assert partial.json()["data"]["user"]["legal_acceptance_required"] is True
    both = client.post(
        "/api/v1/auth/google",
        json={"id_token": "google-id-token", "accept_terms": True, "accept_privacy": True},
    )
    assert both.json()["data"]["user"]["legal_acceptance_required"] is False
    assert _stored(auth_runtime, "google-user@gmail.com")[0] == CURRENT_TERMS_VERSION


def test_new_registrations_record_the_current_versions(client, auth_runtime) -> None:
    email = "new-user@example.com"
    response = client.post(
        "/api/v1/auth/register",
        json={
            "email": email,
            "password": PASSWORD,
            "name": "New User",
            "accept_terms": True,
            "accept_privacy": True,
        },
    )
    assert response.status_code == 201
    terms, privacy, at = _stored(auth_runtime, email)
    assert (terms, privacy) == (CURRENT_TERMS_VERSION, CURRENT_PRIVACY_VERSION) and at is not None
    refused = client.post(
        "/api/v1/auth/register",
        json={"email": "no-consent@example.com", "password": PASSWORD, "name": "No Consent"},
    )
    assert refused.status_code == 422
