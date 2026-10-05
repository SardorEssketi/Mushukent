"""Freeze reviewed 2GIS pet-store district pagination selections and holds."""

from __future__ import annotations

import json
from collections import Counter

from backend.scripts.build_places_v2 import DATA, read_jsonl, write_jsonl

SELECTED_FIRMS = {
    # Page 2: separate named stores or separately numbered premises.
    "70000001037314669",
    "70000001043164105",
    "70000001052067541",
    "70000001054968037",
    "70000001063935334",
    "70000001075312362",
    "70000001078642302",
    "70000001082344833",
    "70000001087486768",
    "70000001090377228",
    "70000001092441605",
    "70000001094344747",
    "70000001095791985",
    "70000001097239547",
    "70000001104583172",
    "70000001112986629",
    "70000001118088372",
    # Page 3: distinct addresses; same-brand branches remain separate.
    "70000001041300778",
    "70000001048415142",
    "70000001083042322",
    "70000001094669136",
    "70000001096356594",
    "70000001096998096",
    "70000001100214402",
    "70000001104585744",
    "70000001113944331",
    # Page 4: pet store and separately named veterinary pharmacy.
    "70000001082600395",
    "70000001083946107",
}

ALIASES = {
    "70000001037606526": "v2_2gis_70000001110450093",
    "70000001065112096": "v2_zoomagazin_yunusabad_11_7",
    "70000001084428854": "v2_zoo_topia_chimkent_1",
    "70000001087606741": "v2_happy_pets_katartal_60",
    "70000001095128674": "v2_zoo_market_sayram_3a",
    "70000001103369281": "v2_arcazoo_nukus_88",
    "70000001113692158": "v2_petzoo_biy_103",
    "70000001114834589": "v2_lapalavka_oqquorgon_18",
    "70000001115592402": "v2_blackbee_quyliq_2_11",
    "70000001116767753": "v2_kw_zoo_product_billur_84",
    "70000001037274534": "v2_ekovet_traktorsozlar_2_40",
    "70000001067179638": "v2_zoo_market_yunusabad_14_61a",
    "70000001097236528": "v2_tri_kota_feruza_21",
}

SHARED_PREMISES = {
    "70000001088808683",
    "70000001110450088",
    "70000001110450091",
    "70000001037341119",
    "70000001040096288",
}

PUBLIC_ACCESS_UNCERTAIN = {"70000001095750288"}


def main() -> None:
    suggestions = {
        row["firm_id"]: row
        for row in read_jsonl(DATA / "2gis_district_petstore_firm_suggestions.jsonl")
    }
    later = {
        id: row
        for id, row in suggestions.items()
        if "_page" in row.get("discovery_search_file", "")
    }
    unresolved = (
        later.keys() - SELECTED_FIRMS - ALIASES.keys() - SHARED_PREMISES - PUBLIC_ACCESS_UNCERTAIN
    )
    if unresolved:
        raise ValueError(
            f"Later-page firm suggestions require explicit disposition: {sorted(unresolved)}"
        )
    if not SELECTED_FIRMS <= later.keys():
        raise ValueError("Some selected firm IDs are absent from saved later-page evidence")

    selection_path = DATA / "2gis_district_petstore_verified_selections.jsonl"
    selections = read_jsonl(selection_path)
    existing = {row["firm_id"] for row in selections}
    for firm_id in sorted(SELECTED_FIRMS - existing):
        row = later[firm_id]
        selections.append(
            {
                "firm_id": firm_id,
                "id": "v2_2gis_" + firm_id,
                "district": row["district_hint"],
                "branch_name": row["address"],
                "expected_coordinates": row["coordinates"],
                "expected_address": row["address"],
            }
        )
    write_jsonl(selection_path, selections)

    decision_path = DATA / "candidate_research_decisions.jsonl"
    decisions = read_jsonl(decision_path)
    decided = {row["candidate_id"] for row in decisions}
    for firm_id in sorted(later.keys() - SELECTED_FIRMS):
        candidate_id = "v2_candidate_2gis_" + firm_id
        if candidate_id in decided:
            continue
        row = later[firm_id]
        if firm_id in ALIASES:
            reason = (
                "Same or compatible business identity and nearby address as an existing verified "
                "place; check whether this is an alias or distinct storefront before adding "
                "another marker."
            )
            decision = {
                "type": "candidate_possible_alias",
                "possible_verified_place_id": ALIASES[firm_id],
            }
        elif firm_id in SHARED_PREMISES:
            reason = (
                "Several differently named pet shops have firm pins at the same numbered "
                "marketplace premises; individual storefront or trading-name distinction "
                "needs review."
            )
            decision = {"type": "candidate_needs_review"}
        else:
            reason = (
                "A pet-store listing in a military-town address needs confirmation that this "
                "is a public visitor location."
            )
            decision = {"type": "candidate_needs_review"}
        decisions.append(
            {
                **decision,
                "candidate_id": candidate_id,
                "reason": reason,
                "evidence_urls": [row["source_url"]],
            }
        )
    write_jsonl(decision_path, decisions)
    print(
        json.dumps(
            {
                "new_selections": len(SELECTED_FIRMS - existing),
                "held_later_page_firms": len(later.keys() - SELECTED_FIRMS),
                "selected_by_district": Counter(
                    later[id]["district_hint"] for id in SELECTED_FIRMS
                ),
            },
            default=dict,
        )
    )


if __name__ == "__main__":
    main()
