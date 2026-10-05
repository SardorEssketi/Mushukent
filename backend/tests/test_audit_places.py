from __future__ import annotations

import pytest

from scripts.audit_places import build_record, check_legacy, distance_m, stable_id


def _legacy(row_number: int, name: str, latitude: float, longitude: float) -> dict:
    return {
        "place_id": stable_id("legacy-row", str(row_number)),
        "row_number": row_number,
        "name": name,
        "type": "pet store",
        "latitude": latitude,
        "longitude": longitude,
        "address": "candidate address",
        "phone": "+998 90 111 22 33",
        "phone 2": None,
        "website": None,
        "instagram": None,
        "telegram": None,
        "opening_hours": None,
        "description": None,
    }


def _evidence(value: object) -> dict:
    return {"value": value, "sources": ["https://example.org/branch"], "confidence": "high"}


def test_evidence_cannot_shift_to_adjacent_workbook_row() -> None:
    first = _legacy(2, "Chain", 41.29, 69.21)
    second = _legacy(3, "Chain", 41.30, 69.22)
    evidence = {"fields": {"phone_numbers": _evidence(["+998901112233"])}}

    first_record, _ = build_record(first, evidence, [], "2026-10-01T00:00:00+00:00")
    second_record, _ = build_record(second, None, [], "2026-10-01T00:00:00+00:00")

    assert first_record["phone_numbers"] == ["+998901112233"]
    assert second_record["phone_numbers"] is None
    assert second_record["legacy_candidate"]["phone"] == "+998 90 111 22 33"
    assert first_record["place_id"] != second_record["place_id"]


def test_chain_branches_are_not_deduplicated_by_name() -> None:
    first = _legacy(2, "Chain", 41.29, 69.21)
    second = _legacy(3, "Chain", 41.30, 69.22)

    assert distance_m(first, second) > 100
    assert not any(flag["code"] == "possible_duplicate" for flag in check_legacy([first, second]))


def test_invalid_evidence_does_not_promote_candidate() -> None:
    row = _legacy(2, "Shop", 41.29, 69.21)
    evidence = {"fields": {"website": _evidence("javascript:alert(1)")}}

    with pytest.raises(ValueError, match="invalid URL"):
        build_record(row, evidence, [], "2026-10-01T00:00:00+00:00")
