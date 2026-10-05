"""Data-independent checks for the saved-snapshot comparison rules."""

from __future__ import annotations

from scripts.compare_places_v2_production import candidates, category_compatible, strong_match


def test_veterinary_pharmacy_can_match_a_reviewed_shop_branch() -> None:
    old = {
        "id": "legacy-1",
        "name": "Ekovet",
        "category": "pet_shop",
        "categories": ["pet_shop"],
        "latitude": 41.3,
        "longitude": 69.2,
        "address": "Tuzel 2/12A",
        "phone": None,
        "phone_2": None,
        "website": None,
    }
    new = {
        "id": "v2-1",
        "source_id": "places_v2:v2-1",
        "name": "Ekovet",
        "category": "veterinary_pharmacy",
        "latitude": 41.3,
        "longitude": 69.2,
        "address": "Tuzel 2/12A",
        "phones": [],
        "website": None,
    }
    pairs = candidates([old], [new])
    assert len(pairs) == 1
    assert category_compatible(old, new, pairs[0])
    assert strong_match(old, new, pairs[0])


def test_same_name_at_distant_branch_is_not_a_candidate() -> None:
    old = {
        "id": "legacy-1",
        "name": "Ekovet",
        "category": "pet_shop",
        "categories": ["pet_shop"],
        "latitude": 41.3,
        "longitude": 69.2,
        "address": "Tuzel 2/12A",
        "phone": None,
        "phone_2": None,
        "website": None,
    }
    new = {
        "id": "v2-2",
        "source_id": "places_v2:v2-2",
        "name": "Ekovet",
        "category": "veterinary_pharmacy",
        "latitude": 41.4,
        "longitude": 69.3,
        "address": "Other branch",
        "phones": [],
        "website": None,
    }
    assert candidates([old], [new]) == []
