"""Rank original V2 lead searches against already reviewed 2GIS firm pages.

The output is a review list, never an automatic merge: name, address, category
and branch-specific result context must agree before linking a lead.
"""

from __future__ import annotations

import json
from difflib import SequenceMatcher

from backend.scripts.build_places_v2 import DATA, OUT, address_match, normal, read_jsonl


def main() -> None:
    candidates = {row["candidate_id"]: row for row in read_jsonl(OUT / "places_candidates.jsonl")}
    suggestions = {
        row["firm_id"]: row
        for path in DATA.glob("2gis_*_firm_suggestions.jsonl")
        for row in read_jsonl(path)
    }
    selections = {
        row["firm_id"]: row
        for path in DATA.glob("2gis_*_verified_selections.jsonl")
        for row in read_jsonl(path)
    }
    probes = read_jsonl(DATA / "2gis_original_lead_probes.jsonl") + read_jsonl(
        DATA / "2gis_original_lead_probes_short.jsonl"
    )
    reviewed = set()
    rows = []
    for probe in probes:
        candidate = candidates[probe["candidate_id"]]
        if candidate["status"] != "discovery_only":
            continue
        for firm_id in probe["result_firm_ids"]:
            if firm_id not in suggestions:
                continue
            firm = suggestions[firm_id]
            key = (candidate["candidate_id"], firm_id)
            if key in reviewed:
                continue
            reviewed.add(key)
            score = SequenceMatcher(
                None, normal(candidate["name_hint"]), normal(firm["name"])
            ).ratio()
            addr = address_match(candidate.get("address_hint") or "", firm["address"])
            rows.append(
                {
                    "candidate_id": candidate["candidate_id"],
                    "candidate_name": candidate["name_hint"],
                    "candidate_address": candidate.get("address_hint"),
                    "candidate_category": candidate["category_hint"],
                    "firm_id": firm_id,
                    "firm_name": firm["name"],
                    "firm_address": firm["address"],
                    "firm_category": firm["category"],
                    "firm_coordinates": firm["coordinates"],
                    "selected_place_id": selections.get(firm_id, {}).get("id"),
                    "name_score": round(score, 2),
                    "address_match": addr,
                    "firm_url": firm["source_url"],
                }
            )
    rows.sort(
        key=lambda row: (
            row["address_match"],
            row["selected_place_id"] is not None,
            row["name_score"],
        ),
        reverse=True,
    )
    for row in rows:
        print(json.dumps(row, ensure_ascii=False))


if __name__ == "__main__":
    main()
