"""Owner contact details are not public (audit F-13, docs/CONTACT_PRIVACY.md).

Anonymous visitors and list/feed responses never receive phone numbers or Telegram handles; they
only learn that contact is possible. Signed-in viewers get the details on the detail endpoint, so
the Contact Owner workflow keeps working.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from test_blocking import (  # noqa: E402,F401
    API,
    Person,
    client,
    make_adoption,
    make_lost_pet,
    make_user,
    runtime,
)

PHONE = "+998901234567"
TELEGRAM = "owner_handle"


def _seed(runtime):
    from app.infrastructure.db.models import schema

    owner = make_user(runtime, "Owner")
    lost = make_lost_pet(runtime, owner)
    adoption = make_adoption(runtime, owner)
    with runtime.manager.session_scope() as session:
        session.get(schema.LostPet, lost).owner_telegram_username = TELEGRAM
        session.get(schema.AdoptionPost, adoption).owner_telegram_username = TELEGRAM
    return owner, lost, adoption


def _leaks(response) -> bool:
    text = response.text
    return PHONE in text or TELEGRAM in text


def test_anonymous_lists_feed_and_details_never_contain_contact_details(client, runtime) -> None:
    _, lost, adoption = _seed(runtime)
    for path in (
        "/lost-pets",
        "/adoption-posts",
        "/feed?filter=recent",
        "/feed?filter=adoption",
        f"/lost-pets/{lost}",
        f"/adoption-posts/{adoption}",
        "/lost-pets/map?bbox=69.0,41.0,69.5,41.5",
    ):
        response = client.get(f"{API}{path}")
        assert response.status_code == 200, path
        assert not _leaks(response), path


def test_guests_still_learn_that_contact_is_possible(client, runtime) -> None:
    _, lost, adoption = _seed(runtime)
    assert client.get(f"{API}/lost-pets/{lost}").json()["data"]["contact_available"] is True
    assert (
        client.get(f"{API}/adoption-posts/{adoption}").json()["data"]["contact_available"] is True
    )
    items = client.get(f"{API}/feed?filter=recent").json()["data"]["items"]
    assert items and all(item["contact_available"] for item in items)


def test_signed_in_viewers_get_contact_details_on_detail_only(client, runtime) -> None:
    owner, lost, adoption = _seed(runtime)
    viewer = make_user(runtime, "Viewer")
    detail = client.get(f"{API}/lost-pets/{lost}", headers=viewer.h).json()["data"]
    assert detail["owner_phone_number"] == PHONE
    assert detail["owner_telegram_username"] == TELEGRAM
    detail = client.get(f"{API}/adoption-posts/{adoption}", headers=viewer.h).json()["data"]
    assert detail["owner_phone_number"] == PHONE
    for path in ("/lost-pets", "/adoption-posts", "/feed?filter=recent", "/lost-pets/mine"):
        response = client.get(f"{API}{path}", headers=viewer.h)
        assert response.status_code in (200,), path
        assert not _leaks(response), path
    mine = client.get(f"{API}/adoption-posts/mine", headers=owner.h)
    assert not _leaks(mine)


def test_owner_sees_their_own_contact_details_for_editing(client, runtime) -> None:
    owner, lost, adoption = _seed(runtime)
    assert (
        client.get(f"{API}/lost-pets/{lost}", headers=owner.h).json()["data"]["owner_phone_number"]
        == PHONE
    )
    assert (
        client.get(f"{API}/adoption-posts/{adoption}", headers=owner.h).json()["data"][
            "owner_phone_number"
        ]
        == PHONE
    )


def test_contact_owner_workflow_still_works_after_signing_in(client, runtime) -> None:
    _, lost, adoption = _seed(runtime)
    viewer = make_user(runtime, "Viewer")
    assert client.post(f"{API}/lost-pets/{lost}/contact").status_code == 401
    assert client.post(f"{API}/lost-pets/{lost}/contact", headers=viewer.h).status_code == 204
    assert (
        client.post(f"{API}/adoption-posts/{adoption}/contact", headers=viewer.h).status_code == 204
    )


def test_scraping_the_public_api_yields_no_phone_numbers(client, runtime) -> None:
    owner = make_user(runtime, "Owner")
    for index in range(25):
        make_lost_pet(runtime, owner, name=f"Pet {index}")
        make_adoption(runtime, owner, name=f"Kitten {index}")
    harvested = ""
    for path in (
        "/lost-pets?limit=100",
        "/adoption-posts?limit=100",
        "/feed?filter=recent&limit=100",
    ):
        response = client.get(f"{API}{path}")
        assert response.status_code == 200
        harvested += response.text
    assert "+998" not in harvested
    assert len(json.loads(client.get(f"{API}/lost-pets?limit=100").text)["data"]["items"]) == 25


def test_resolved_posts_stop_advertising_contact(client, runtime) -> None:
    from app.infrastructure.db.models import schema

    owner, lost, _ = _seed(runtime)
    with runtime.manager.session_scope() as session:
        session.get(schema.LostPet, lost).is_resolved = True
    detail = client.get(f"{API}/lost-pets/{lost}").json()["data"]
    assert detail["contact_available"] is False
    assert not _leaks(client.get(f"{API}/lost-pets/{lost}"))
    viewer = make_user(runtime, "Viewer")
    assert (
        client.get(f"{API}/lost-pets/{lost}", headers=viewer.h).json()["data"]["contact_available"]
        is False
    )
