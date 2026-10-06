from __future__ import annotations

import pytest

from scripts.build_places_v2 import reviewed_firm_distances, same_entity


def test_matching_name_and_branch_address_can_group() -> None:
    first = {"name": "PetZoo", "address_hint": "Katartal Street, 60/1"}
    second = {"name": "PetZoo", "address_hint": "Katartal Street, 60/1"}

    assert same_entity(first, second)


def test_names_do_not_merge_distinct_branches_or_distant_pins() -> None:
    first = {"name": "PetZoo", "address_hint": "Katartal Street, 60/1"}
    other_branch = {"name": "PetZoo", "address_hint": "Buyuk Ipak Yuli Street, 103"}
    distant_pin = {
        **first,
        "latitude": 41.3266,
        "longitude": 69.328524,
    }
    first = {**first, "latitude": 41.29318, "longitude": 69.211213}

    assert not same_entity(first, other_branch)
    assert not same_entity(first, distant_pin)


def test_shared_building_does_not_merge_different_businesses() -> None:
    first = {"name": "Vet+ZooPlaneta", "address_hint": "Sergeli-2 dahasi, 2A"}
    second = {"name": "Aquamir", "address_hint": "Sergeli-2 dahasi, 2A"}

    assert not same_entity(first, second)


def test_same_house_number_in_different_mavze_is_not_a_branch_match() -> None:
    first = {"name": "PetZoo", "address_hint": "Chilanzar 1-mavze, 60"}
    second = {"name": "PetZoo", "address_hint": "Chilanzar 12-mavze, 60"}

    assert not same_entity(first, second)


def test_exact_branch_link_requires_a_nearby_reviewed_firm_pin() -> None:
    link = {"evidence_urls": ["https://2gis.uz/tashkent/firm/123"]}
    point = (41.3, 69.2)
    suggestions = {"123": {"coordinates": [41.3001, 69.2]}}

    assert reviewed_firm_distances(link, point, suggestions)[0] == pytest.approx(11.1, abs=0.2)
    with pytest.raises(ValueError, match=r"Candidate link is \d+ m from firm pin"):
        reviewed_firm_distances(link, point, {"123": {"coordinates": [41.303, 69.2]}})
    with pytest.raises(ValueError, match="no reviewed 2GIS firm pin"):
        reviewed_firm_distances(link, point, {})
