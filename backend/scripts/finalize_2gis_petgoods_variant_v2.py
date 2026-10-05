"""Measure new firm links and target-place yield for the pet-goods query."""

from __future__ import annotations

import json

from backend.scripts.build_places_v2 import DATA, read_jsonl, write_jsonl
from bs4 import BeautifulSoup


def main() -> None:
    prior = {
        row["firm_id"]
        for path in DATA.glob("2gis_*_firm_suggestions.jsonl")
        if "petgoods" not in path.name
        for row in read_jsonl(path)
    }
    checks = read_jsonl(DATA / "2gis_district_petgoods_firm_checks.jsonl")
    checked = {row["firm_id"]: row for row in checks}
    yields = []
    all_new = set()
    for row in read_jsonl(DATA / "2gis_district_petgoods_search_checks.jsonl"):
        if row["status"] != "executed":
            yields.append(
                {**row, "new_firm_links_vs_prior_2gis": None, "new_target_physical_places": None}
            )
            continue
        soup = BeautifulSoup((DATA / row["search_file"]).read_text(encoding="utf-8"), "html.parser")
        ids = {
            a["href"].split("/")[-1]
            for a in soup.find_all("a", href=True)
            if a["href"].startswith("/tashkent/firm/") and a["href"].split("/")[-1].isdigit()
        }
        new = ids - prior
        all_new |= new
        target = sum(
            checked.get(firm_id, {}).get("result") == "physical_point_suggestion" for firm_id in new
        )
        yields.append(
            {
                **row,
                "new_firm_links_vs_prior_2gis": len(new),
                "new_target_firm_suggestions": target,
                "new_target_physical_places": 0,
                "note": (
                    "New firm IDs were reviewed on firm pages; none had the required target "
                    "category plus branch address and point."
                ),
            }
        )
    write_jsonl(DATA / "2gis_district_petgoods_search_yields.jsonl", yields)
    print(
        json.dumps(
            {
                "district_searches": len(yields),
                "distinct_new_firm_links": len(all_new),
                "target_firm_suggestions": sum(
                    row.get("new_target_firm_suggestions", 0) for row in yields
                ),
            }
        )
    )


if __name__ == "__main__":
    main()
