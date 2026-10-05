"""Make one immutable, evidence-reviewed V2 release snapshot.

Reads only existing V2 evidence and explicit gate decisions. Refuses to
overwrite a frozen snapshot; --verify checks its checksum without modifying it.
No database access.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from collections import Counter, defaultdict

from backend.scripts.build_places_v2 import DATA, OUT, distance_meters, read_jsonl, write_jsonl

FROZEN = OUT / "places_frozen_release.jsonl"
HASH = OUT / "places_frozen_release.sha256"


def _json_bytes(rows: list[dict]) -> bytes:
    return b"".join(
        (json.dumps(row, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode(
            "utf-8"
        )
        for row in rows
    )


def verify() -> str:
    expected = HASH.read_text(encoding="ascii").split()[0]
    actual = hashlib.sha256(FROZEN.read_bytes()).hexdigest()
    if actual != expected:
        raise ValueError(f"Frozen V2 checksum mismatch: expected {expected}, got {actual}")
    return actual


def freeze() -> dict:
    if FROZEN.exists() or HASH.exists():
        raise FileExistsError("Frozen snapshot already exists; use --verify, never overwrite it")
    places = read_jsonl(OUT / "places_release_candidate.jsonl")
    if len(places) != 225:
        raise ValueError(f"Expected 225 release-candidate inputs, got {len(places)}")
    by_id = {p["id"]: p for p in places}
    if len(by_id) != len(places):
        raise ValueError("Duplicate release-candidate IDs")
    coordinate_review_ids = {p["id"] for p in read_jsonl(OUT / "places_coordinate_review.jsonl")}
    if len(coordinate_review_ids) != 65:
        raise ValueError("Coordinate review input changed; re-audit before freezing")
    source_rows = read_jsonl(OUT / "places_sources.jsonl")
    coordinate_sources: dict[str, list[dict]] = defaultdict(list)
    for source in source_rows:
        if source["field"] == "coordinates" and source["status"] == "verified":
            coordinate_sources[source["record_id"]].append(source)

    pair_decisions = read_jsonl(DATA / "release_pair_decisions.jsonl")
    pair_cases = {row["case"] for row in pair_decisions}
    if len(pair_decisions) != 14 or len(pair_cases) != 14:
        raise ValueError("Expected 14 unique duplicate/branch case decisions")
    warnings = read_jsonl(OUT / "places_qa_warnings.jsonl")
    warned_pairs = {
        frozenset(w["place_ids"])
        for w in warnings
        if w["code"] in {"same_name_nearby", "identical_coordinates"}
    }
    reviewed_pairs = {
        frozenset(row["place_ids"]) for row in pair_decisions if len(row["place_ids"]) == 2
    }
    if warned_pairs != reviewed_pairs:
        raise ValueError(
            "Every same-name and identical-pin pair must have an explicit case decision"
        )

    aliases = []
    for pair in pair_decisions:
        if pair["classification"] == "confirmed_duplicate":
            survivor = pair["survivor_id"]
            retired = next(pid for pid in pair["place_ids"] if pid != survivor)
            aliases.append(
                {
                    "retired_research_id": retired,
                    "survivor_research_id": survivor,
                    "retired_source_id": "places_v2:" + retired,
                    "survivor_source_id": "places_v2:" + survivor,
                    "case": pair["case"],
                    "reason": pair["reason"],
                }
            )
    if len(aliases) != 3:
        raise ValueError("Expected three independently reviewed duplicate aliases")

    overrides = {row["place_id"]: row for row in read_jsonl(DATA / "release_gate_overrides.jsonl")}
    if len(overrides) != len(read_jsonl(DATA / "release_gate_overrides.jsonl")):
        raise ValueError("Duplicate gate override")
    decisions = []
    frozen = []
    for place in places:
        pid = place["id"]
        original_point = (place["latitude"], place["longitude"])
        pin_sources = coordinate_sources[pid]
        if not pin_sources or not any(
            isinstance(row["value"], list)
            and distance_meters(original_point, tuple(row["value"])) <= 1
            and row["source_url"] in place["source_urls"]
            for row in pin_sources
        ):
            raise ValueError(f"No matching field-level source for physical pin: {pid}")
        override = overrides.get(pid, {})
        decision = override.get("decision", "ACCEPT")
        if decision not in {"ACCEPT", "CORRECT", "HOLD"}:
            raise ValueError(f"Invalid gate decision: {pid}")
        source_kinds = sorted({row["source_kind"] for row in pin_sources})
        reason = override.get("reason")
        if not reason:
            if pid in coordinate_review_ids:
                if "detailed_2gis_organization" in source_kinds:
                    reason = (
                        "Firm-specific 2GIS page ties the named category, address/location "
                        "evidence and route pin to one firm ID. Nearby distinct names/market "
                        "stalls retain separate records."
                    )
                elif "detailed_map_house" in source_kinds:
                    reason = (
                        "Detailed Yandex house page ties the named business to this building; "
                        "shared building pins are acceptable for separately named listings."
                    )
                else:
                    reason = (
                        "Detailed organization evidence ties this named physical business to "
                        "the recorded point; no contradictory coordinate source was found."
                    )
            else:
                reason = (
                    "Verified physical location has a matching field-level coordinate source "
                    "and no coordinate QA warning."
                )
        evidence_urls = sorted({row["source_url"] for row in pin_sources})
        decision_row = {
            "place_id": pid,
            "decision": decision,
            "coordinate_review": pid in coordinate_review_ids,
            "original_coordinates": list(original_point),
            "qa_warnings": place["qa_warnings"],
            "coordinate_source_kinds": source_kinds,
            "coordinate_evidence_urls": evidence_urls,
            "reason": reason,
        }
        if decision == "HOLD":
            decisions.append(decision_row)
            continue

        row = dict(place)
        row["include"] = decision
        row["gate_decision_reason"] = reason
        if "district_override" in override:
            decision_row["district_before"] = row["district"]
            row["district"] = override["district_override"]
            decision_row["district_after"] = row["district"]
        if "address_override" in override:
            decision_row["address_before"] = row["address"]
            row["address"] = override["address_override"]
            decision_row["address_after"] = row["address"]
            row["field_conflicts"] = sorted(set(row["field_conflicts"]) | {"address"})
            row["field_confidence"] = dict(
                row["field_confidence"], address="conflict", location_evidence="high"
            )
            row["location_evidence"] = override["location_evidence"]
        if "add_source_url" in override:
            row["source_urls"] = sorted(set(row["source_urls"]) | {override["add_source_url"]})
            row["source_count"] = len(row["source_urls"])
        if decision == "CORRECT":
            new_point = (override["latitude"], override["longitude"])
            source_url = override["coordinate_source_url"]
            evidence_row = next(
                (
                    source
                    for source in source_rows
                    if source["field"] == "coordinates"
                    and source["status"] == "verified"
                    and source["source_url"] == source_url
                    and isinstance(source["value"], list)
                    and distance_meters(new_point, tuple(source["value"])) <= 1
                ),
                None,
            )
            if not evidence_row or evidence_row["source_kind"] != "detailed_2gis_organization":
                raise ValueError(
                    f"Corrected coordinate lacks stronger firm-specific evidence: {pid}"
                )
            if distance_meters(original_point, new_point) > 150:
                raise ValueError(f"Corrected point too far from prior branch: {pid}")
            row["latitude"], row["longitude"] = new_point
            row["source_urls"] = sorted(set(row["source_urls"]) | {source_url})
            row["source_count"] = len(row["source_urls"])
            row["release_coordinate_source_url"] = source_url
            decision_row["corrected_coordinates"] = list(new_point)
            decision_row["coordinate_correction_m"] = round(
                distance_meters(original_point, new_point), 1
            )
            decision_row["coordinate_evidence_urls"] = sorted(set(evidence_urls) | {source_url})
        decisions.append(decision_row)
        frozen.append(row)

    if len(decisions) != 225 or sum(row["coordinate_review"] for row in decisions) != 65:
        raise ValueError("Gate decisions do not cover every original place and coordinate warning")
    if any(alias["retired_research_id"] in {row["id"] for row in frozen} for alias in aliases):
        raise ValueError("Retired duplicate still present in frozen snapshot")
    frozen.sort(key=lambda row: row["source_id"])
    payload = _json_bytes(frozen)
    digest = hashlib.sha256(payload).hexdigest()
    FROZEN.write_bytes(payload)
    HASH.write_text(f"{digest}  {FROZEN.name}\n", encoding="ascii")
    write_jsonl(OUT / "places_gate_decisions.jsonl", decisions)
    write_jsonl(OUT / "places_gate_pair_decisions.jsonl", pair_decisions)
    write_jsonl(OUT / "places_release_aliases.jsonl", aliases)
    counts = Counter(row["decision"] for row in decisions)
    report = {
        "original_places": 225,
        "coordinate_review_entries": 65,
        "accept": counts["ACCEPT"],
        "correct": counts["CORRECT"],
        "hold": counts["HOLD"],
        "confirmed_duplicates_removed": len(aliases),
        "coordinate_corrections": counts["CORRECT"],
        "district_labels_cleared": sum(
            "district_before" in row and row["district_before"] != row["district_after"]
            for row in decisions
        ),
        "frozen_snapshot_count": len(frozen),
        "frozen_snapshot_sha256": digest,
        "frozen_field_conflict_places": sum(bool(row["field_conflicts"]) for row in frozen),
        "frozen_field_conflict_fields": dict(
            Counter(field for row in frozen for field in row["field_conflicts"])
        ),
        "postgis_gate": "blocked_docker_engine_unavailable",
        "production_changed": False,
    }
    (OUT / "places_gate_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--verify", action="store_true", help="Only verify the existing snapshot hash"
    )
    args = parser.parse_args()
    print(verify() if args.verify else json.dumps(freeze(), ensure_ascii=False, indent=2))
