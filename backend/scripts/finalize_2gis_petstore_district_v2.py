"""Record human-reviewed firm selections from the last five district searches.

This only updates V2 research fixtures. Each selected firm page has a named
pet business, target category, street address, and a route point tied to its
firm ID. Firm IDs and coordinates are frozen so later page changes fail review.
"""

from __future__ import annotations

import json
from collections import Counter
from datetime import UTC, datetime

from backend.scripts.build_places_v2 import DATA, read_jsonl, write_jsonl
from bs4 import BeautifulSoup

SELECTED_FIRMS = {
    "70000001037208991",  # Zoo vet mag, Chilanzar
    "70000001037376682",  # Zoo, Fitrat 4
    "70000001037663238",  # Force Bio Trade, Yunusabad 3
    "70000001060019143",  # Zooorganic, Tuzel 2
    "70000001067536522",  # Zoolapka, Avliyo Ota 2
    "70000001082867880",  # Zoo Abrikos, Karasu 27
    "70000001094439432",  # ZooMarket, Maykurgan 3/1
    "70000001103436153",  # PetZoo, Osiyo 17/17A
}

POSSIBLE_ALIASES = {
    "70000001038809622": "v2_happy_pets_katartal_60",
    "70000001044152337": "v2_zoo_imperia_parkent_176",
    "70000001081285147": "v2_zoocenter_shop_sarykul_9",
    "70000001082523319": "v2_zoo_market_717_lisunov_2",
    "70000001087631869": "v2_charley_yunusabad_19_45",
    "70000001095535745": "v2_kupi_slona_karasu_17",
}

FIVE_DISTRICTS = {
    "Chilanzar": "raw_2gis_chilanzar_petstores_probe.html",
    "Mirobad": "raw_2gis_mirobod_petstores_probe.html",
    "Mirzo Ulugbek": "raw_2gis_mirzoulugbek_petstores_probe.html",
    "Yashnabad": "raw_2gis_yashnabad_petstores_probe.html",
    "Yunusabad": "raw_2gis_yunusabad_petstores_probe.html",
}


def main() -> None:
    suggestions = {
        row["firm_id"]: row
        for row in read_jsonl(DATA / "2gis_district_petstore_firm_suggestions.jsonl")
    }
    if not SELECTED_FIRMS <= suggestions.keys():
        raise ValueError("One or more reviewed 2GIS firm pages are missing")
    path = DATA / "2gis_district_petstore_verified_selections.jsonl"
    selections = read_jsonl(path)
    existing = {row["firm_id"] for row in selections}
    official_locator = "https://petzoo.uz/index.php?dispatch=store_locator.search"
    for firm_id in sorted(SELECTED_FIRMS - existing):
        row = suggestions[firm_id]
        selection = {
            "firm_id": firm_id,
            "id": "v2_petzoo_osiyo_17" if firm_id == "70000001103436153" else "v2_2gis_" + firm_id,
            "district": row["district_hint"],
            "branch_name": row["address"],
            "expected_coordinates": row["coordinates"],
            "expected_address": row["address"],
        }
        if firm_id == "70000001103436153":
            selection["official_url"] = official_locator
            selection["address_conflict"] = [
                {
                    "value": "Tashkent, Osiyo Street, 17",
                    "url": row["source_url"],
                    "kind": "detailed_2gis_organization",
                },
                {
                    "value": "Tashkent, Osiyo Street, 17A",
                    "url": official_locator,
                    "kind": "official_website",
                },
            ]
        selections.append(selection)
    osiyo = next(row for row in selections if row["firm_id"] == "70000001103436153")
    osiyo["address_conflict"] = [
        {
            "value": "Tashkent, Osiyo Street, 17",
            "url": suggestions["70000001103436153"]["source_url"],
            "kind": "detailed_2gis_organization",
        },
        {
            "value": "Tashkent, Osiyo Street, 17A",
            "url": official_locator,
            "kind": "official_website",
        },
        {
            "value": "Tashkent, Oqqo'rg'on 1st Passage, 17",
            "url": "https://yandex.uz/maps/org/petzoo/205427667877/",
            "kind": "detailed_map_organization",
        },
    ]
    write_jsonl(path, selections)

    decision_path = DATA / "candidate_research_decisions.jsonl"
    decisions = read_jsonl(decision_path)
    decided = {row["candidate_id"] for row in decisions}
    for firm_id, possible_id in POSSIBLE_ALIASES.items():
        row = suggestions[firm_id]
        candidate_id = "v2_candidate_2gis_" + firm_id
        if candidate_id not in decided:
            decisions.append(
                {
                    "type": "candidate_possible_alias",
                    "candidate_id": candidate_id,
                    "reason": (
                        "Same or near-identical business name and nearby mapped address as the "
                        "verified place; hold the second firm ID until branch or relocation "
                        "identity is resolved."
                    ),
                    "possible_verified_place_id": possible_id,
                    "evidence_urls": [row["source_url"]],
                }
            )
    write_jsonl(decision_path, decisions)

    yield_path = DATA / "2gis_district_petstore_search_yields.jsonl"
    yields = read_jsonl(yield_path)
    logged = {row["district"] for row in yields}
    selected_by_district = Counter(
        suggestions[firm_id]["district_hint"] for firm_id in SELECTED_FIRMS
    )
    for district, filename in FIVE_DISTRICTS.items():
        if district in logged:
            continue
        soup = BeautifulSoup((DATA / filename).read_text(encoding="utf-8"), "html.parser")
        canonical = soup.find("link", rel="canonical")
        if not canonical or not canonical.get("href", "").startswith(
            "https://2gis.uz/tashkent/search/"
        ):
            raise ValueError(f"Missing canonical query URL: {filename}")
        links = {
            a["href"]
            for a in soup.find_all("a", href=True)
            if a["href"].startswith("/tashkent/firm/") and a["href"].split("/")[-1].isdigit()
        }
        yields.append(
            {
                "source_url": canonical["href"],
                "district": district,
                "result_links": len(links),
                "new_verified_physical_places": selected_by_district[district],
                "checked_at": datetime.now(UTC).isoformat(),
                "note": (
                    "Visible first-page results only; accepted places have separately reviewed "
                    "firm-specific pins. Possible aliases are held."
                ),
            }
        )
    write_jsonl(yield_path, yields)

    resolution_path = DATA / "curated_review_resolutions.jsonl"
    resolutions = read_jsonl(resolution_path)
    if not any(row["place_id"] == "v2_petzoo_chilanzar_23" for row in resolutions):
        firm = suggestions["70000001036765852"]
        yandex_url = "https://yandex.com/maps/org/petzoo/195683614921/"
        two_gis = {"url": firm["source_url"], "kind": "detailed_2gis_organization"}
        official = {"url": official_locator, "kind": "official_website"}
        yandex = {"url": yandex_url, "kind": "map_listing"}
        resolutions.append(
            {
                "place_id": "v2_petzoo_chilanzar_23",
                "reason": (
                    "Official locator and 2GIS agree on branch identity and public point; "
                    "Yandex gives house 25 while official and 2GIS give 23. Keep the address "
                    "null, retain the pin, and review the house number before import."
                ),
                "candidate_observation_ids": ["2gis_70000001036765852"],
                "fields": {
                    "address": {
                        "value": None,
                        "status": "conflict",
                        "confidence": "conflict",
                        "sources": [official, two_gis, yandex],
                        "alternatives": [
                            {"value": "Tashkent, Chilanzarskaya Street, 23", **official},
                            {"value": "Tashkent, Chilanzar 3rd quarter, 23", **two_gis},
                            {"value": "Tashkent, Chilanzar 3rd quarter, 25", **yandex},
                        ],
                    },
                    "location_evidence": {
                        "value": "firm-specific 2GIS route point and official branch listing",
                        "status": "verified",
                        "confidence": "high",
                        "sources": [two_gis, official],
                    },
                    "coordinates": {
                        "value": firm["coordinates"],
                        "status": "verified",
                        "confidence": "medium",
                        "sources": [two_gis, {"url": firm["route_url"], "kind": "map_route_point"}],
                    },
                },
            }
        )
    write_jsonl(resolution_path, resolutions)
    print(
        json.dumps(
            {
                "new_selections": len(SELECTED_FIRMS - existing),
                "new_district_yield_rows": len(FIVE_DISTRICTS.keys() - logged),
                "selections_by_district": selected_by_district,
            },
            default=dict,
        )
    )


if __name__ == "__main__":
    main()
