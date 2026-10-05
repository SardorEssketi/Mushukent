from __future__ import annotations

from scripts.build_places_v2 import same_entity


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
