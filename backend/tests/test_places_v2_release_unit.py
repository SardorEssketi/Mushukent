"""Portable checks for the offline release gate and import rehearsal."""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path
from uuid import uuid5

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts import freeze_places_v2_release, qa_places_v2_release  # noqa: E402
from scripts.dry_run_places_v2 import api_readback, import_row, make_database, upsert  # noqa: E402
from scripts.qa_places_v2_release import NAMESPACE  # noqa: E402


def _place(place_id: str = "v2-example", **overrides: object) -> dict:
    source_id = f"places_v2:{place_id}"
    place = {
        "id": place_id,
        "source_id": source_id,
        "import_uuid": str(uuid5(NAMESPACE, source_id)),
        "name": "Example Vet",
        "category": "veterinary_pharmacy",
        "latitude": 41.3,
        "longitude": 69.2,
        "address": "Example Street 2",
        "district": "Yashnabad",
        "phones": [],
        "website": None,
        "instagram": None,
        "telegram": None,
        "opening_hours": None,
        "description": None,
        "verified_at": None,
        "source_urls": ["https://2gis.uz/tashkent/firm/123"],
        "entity_confidence": "high",
        "field_confidence": {"location_evidence": "high"},
        "field_conflicts": [],
    }
    place.update(overrides)
    return place


def test_stable_identity_upsert_and_api_schema_readback() -> None:
    original = _place()
    changed = {**original, "name": "Example Vet Pharmacy", "latitude": 41.300001}
    mapped = import_row(original)
    updated = import_row(changed)
    assert (mapped["id"], mapped["source_id"]) == (updated["id"], updated["source_id"])
    assert mapped["category"] == "veterinary_pharmacy"

    db = make_database()
    try:
        assert upsert(db, mapped) == "insert"
        assert upsert(db, mapped) == "skip"
        assert upsert(db, updated) == "update"
        assert upsert(db, {**updated, "id": "00000000-0000-4000-8000-000000000000"}) == "conflict"
        stored = db.execute(
            "SELECT * FROM places WHERE source_id = ?", (mapped["source_id"],)
        ).fetchone()
        payload = api_readback(stored).model_dump(mode="json")
        assert payload["source_id"] == mapped["source_id"]
        assert payload["name"] == "Example Vet Pharmacy"
        assert payload["category"] == "veterinary_pharmacy"
    finally:
        db.close()


def test_null_address_requires_alternate_location_evidence() -> None:
    place = _place(address=None, field_confidence={})
    with pytest.raises(ValueError, match="physical-location evidence"):
        import_row(place)
    assert (
        import_row({**place, "field_confidence": {"location_evidence": "medium"}})["address"]
        is None
    )


def test_frozen_checksum_verification_and_overwrite_guard(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    frozen = tmp_path / "frozen.jsonl"
    checksum = tmp_path / "frozen.sha256"
    monkeypatch.setattr(freeze_places_v2_release, "FROZEN", frozen)
    monkeypatch.setattr(freeze_places_v2_release, "HASH", checksum)
    content = b'{"id":"v2-example"}\n'
    frozen.write_bytes(content)
    expected = hashlib.sha256(content).hexdigest()
    checksum.write_text(f"{expected}  frozen.jsonl\n", encoding="ascii")

    assert freeze_places_v2_release.verify() == expected
    with pytest.raises(FileExistsError, match="already exists"):
        freeze_places_v2_release.freeze()
    frozen.write_bytes(content + b" ")
    with pytest.raises(ValueError, match="checksum mismatch"):
        freeze_places_v2_release.verify()


def test_release_qa_keeps_uncertain_branches_for_review(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    first = _place("v2-first", name="PetZoo", category="pet_store")
    second = _place(
        "v2-second",
        name="PetZoo",
        category="pet_store",
        latitude=41.3005,
        address=None,
        field_conflicts=["address"],
    )
    sources = [
        {
            "record_id": place["id"],
            "field": "coordinates",
            "status": "verified",
            "value": [place["latitude"], place["longitude"]],
            "source_url": place["source_urls"][0],
        }
        for place in (first, second)
    ]
    for name, rows in (
        ("places_verified.jsonl", [first, second]),
        ("places_sources.jsonl", sources),
        ("places_audit.jsonl", []),
    ):
        (tmp_path / name).write_text(
            "".join(json.dumps(row) + "\n" for row in rows), encoding="utf-8"
        )
    monkeypatch.setattr(qa_places_v2_release, "OUT", tmp_path)
    monkeypatch.setattr(qa_places_v2_release, "_workbook", lambda rows, warnings: None)

    report = qa_places_v2_release.qa()
    candidates = [
        json.loads(line)
        for line in (tmp_path / "places_release_candidate.jsonl")
        .read_text(encoding="utf-8")
        .splitlines()
    ]
    assert report["release_candidate_places"] == 2
    assert report["automatic_merges"] == 0
    assert report["possible_duplicate_pairs"] == 1
    assert report["field_conflict_places"] == 1
    assert report["blocker_places"] == 0
    assert {row["include"] for row in candidates} == {"PENDING_HUMAN_REVIEW"}
    assert len({row["source_id"] for row in candidates}) == 2
    assert next(row for row in candidates if row["id"] == "v2-second")["address"] is None
