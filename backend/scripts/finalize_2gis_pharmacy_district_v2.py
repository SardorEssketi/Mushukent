"""Freeze reviewed firm selections from public 2GIS pharmacy district searches."""

from __future__ import annotations

import json
from collections import Counter

from backend.scripts.build_places_v2 import DATA, read_jsonl, write_jsonl

SELECTED_FIRMS = {
    "70000001037888332",  # 111, separate Vet Prom Invest stall
    "70000001037888339",  # 777, separate Azam agro vet servis stall
    "70000001037903719",  # Mak vest invest
    "70000001065434629",  # Chorvador.uz
    "70000001095170342",  # Happy puppy pet store
    "70000001104650572",  # Ravshan Omad Farm
    "70000001105289056",  # Azva_Vetapteka, 2GIS category pet store
    "70000001110829696",  # 222, separate Toshkent vet pharm stall
    "70000001111195663",  # Mobetco
    "70000001113507696",  # Zoo market pet store
    "70000001116903756",  # Lion Vet Pharm
    "70000001036778812",  # No. 1 Veterinariya Dorixonasi, separate marketplace stall
    "70000001037998805",  # Agro MxM
    "70000001037998833",  # 707
    "70000001059897816",  # Nozimbek zoo vet
    "70000001094922369",  # Agrovet Universal Savdo
    "70000001110829693",  # 888
    "70000001110829702",  # 223
}

POSSIBLE_ALIASES = {
    "70000001047135897": "v2_zoovetpro_tuzel_2_12",
    "70000001058716434": "v2_animalplanet_gulsanam_7b",
    "70000001068839702": "v2_top_agro_vet_qumariq_24a",
    "70000001110829707": "v2_mosso_quyliq_markaz_4",
    "70000001037998798": "v2_merit_vet_chemicals_fargona_10a",
    "70000001037998820": "v2_ecco_life_quyliq_markaz_4",
}


def main() -> None:
    suggestions = {
        row["firm_id"]: row
        for row in read_jsonl(DATA / "2gis_district_pharmacy_firm_suggestions.jsonl")
    }
    if not SELECTED_FIRMS <= suggestions.keys():
        raise ValueError("Missing reviewed pharmacy firm suggestions")
    selection_path = DATA / "2gis_district_pharmacy_verified_selections.jsonl"
    selections = read_jsonl(selection_path)
    existing = {row["firm_id"] for row in selections}
    for firm_id in sorted(SELECTED_FIRMS - existing):
        row = suggestions[firm_id]
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
    azva = next(row for row in selections if row["firm_id"] == "70000001105289056")
    azva_source = suggestions["70000001105289056"]["source_url"]
    yandex_azva = "https://yandex.uz/maps/org/azva_vetapteka/210942867345/"
    azva["additional_observation_ids"] = ["ypharm_010"]
    azva["address_conflict"] = [
        {
            "value": "Tashkent, Quyliq 4th quarter, 13A",
            "url": azva_source,
            "kind": "detailed_2gis_organization",
        },
        {
            "value": "Tashkent, Quyliq 4th quarter, 13",
            "url": yandex_azva,
            "kind": "detailed_map_organization",
        },
    ]
    write_jsonl(selection_path, selections)

    decision_path = DATA / "candidate_research_decisions.jsonl"
    decisions = read_jsonl(decision_path)
    decided = {row["candidate_id"] for row in decisions}
    for firm_id, possible_id in POSSIBLE_ALIASES.items():
        row = suggestions[firm_id]
        candidate_id = "v2_candidate_2gis_" + firm_id
        if candidate_id in decided:
            continue
        reason = (
            "The 2GIS Ekovet pharmacy pin at Tuzel 2/12A is about one metre from the "
            "ZooVetPro shop pin at 2/12; investigate colocation or rename before a second marker."
            if firm_id == "70000001047135897"
            else (
                "The 2GIS pet shop is about 21 m from Animal Planet at a differently named "
                "nearby street address; hold possible separate storefront or address alias."
                if firm_id == "70000001058716434"
                else (
                    "The 2GIS firm appears to describe the already verified named business at "
                    "essentially the same point; retain as possible alternate address/source "
                    "until reconciled."
                )
            )
        )
        decisions.append(
            {
                "type": "candidate_possible_alias",
                "candidate_id": candidate_id,
                "possible_verified_place_id": possible_id,
                "reason": reason,
                "evidence_urls": [row["source_url"]],
            }
        )
    write_jsonl(decision_path, decisions)
    print(
        json.dumps(
            {
                "selected": len(SELECTED_FIRMS - existing),
                "selected_by_district": Counter(
                    suggestions[id]["district_hint"] for id in SELECTED_FIRMS
                ),
            },
            default=dict,
        )
    )


if __name__ == "__main__":
    main()
