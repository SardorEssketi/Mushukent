"""Rank previously saved organization search probes for exact-lead review.

No automatic promotion. A Yandex search can open a different business, so the
report requires address and category review in addition to a name match.
"""

from __future__ import annotations

import argparse
import json
from difflib import SequenceMatcher

from backend.scripts.build_places_v2 import DATA, OUT, address_match, normal, read_jsonl


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()
    candidates = {row["candidate_id"]: row for row in read_jsonl(OUT / "places_candidates.jsonl")}
    probes = read_jsonl(DATA / "yandex_lead_probes.jsonl") + read_jsonl(
        DATA / "yandex_lead_probes_address.jsonl"
    )
    matches = []
    for probe in probes:
        candidate = candidates.get(probe["candidate_id"])
        if (
            not candidate
            or candidate["status"] != "discovery_only"
            or not probe.get("organization_url")
        ):
            continue
        source_name = probe.get("result_title", "").split(",", 1)[0]
        score = SequenceMatcher(None, normal(candidate["name_hint"]), normal(source_name)).ratio()
        same_address = address_match(
            candidate.get("address_hint") or "", probe.get("result_address") or ""
        )
        matches.append(
            {
                "candidate_id": candidate["candidate_id"],
                "name_score": round(score, 2),
                "address_match": same_address,
                "name_hint": candidate["name_hint"],
                "address_hint": candidate.get("address_hint"),
                "result_title": probe.get("result_title"),
                "result_address": probe.get("result_address"),
                "result_coordinates": probe.get("result_coordinates"),
                "organization_url": probe["organization_url"],
            }
        )
    matches.sort(key=lambda row: (row["address_match"], row["name_score"]), reverse=True)
    print(
        json.dumps(
            {
                "all_unresolved_org_probes": len(matches),
                "high_name_address": sum(
                    row["name_score"] >= 0.75 and row["address_match"] for row in matches
                ),
            }
        )
    )
    for row in matches[: args.limit]:
        print(json.dumps(row, ensure_ascii=False))


if __name__ == "__main__":
    main()
