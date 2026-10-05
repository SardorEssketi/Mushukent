"""Screen saved public 2GIS district searches and inspect each clinic firm page.

Output is suggestion-only; selected physical branches require explicit review.
Sequential public requests stop on access restrictions.
"""

from __future__ import annotations

import argparse
import http.client
import json
import re
import time
import urllib.error

from backend.scripts.build_places_v2 import DATA, read_jsonl
from backend.scripts.harvest_2gis_chain_v2 import BASE, fetch, parse_firm
from bs4 import BeautifulSoup


def links_from_saved_searches(topic: str) -> dict[str, str]:
    links = {}
    for path in sorted(DATA.glob(f"raw_2gis_*_{topic}_probe.html")):
        soup = BeautifulSoup(path.read_text(encoding="utf-8"), "html.parser")
        for a in soup.find_all("a", href=True):
            if re.fullmatch(r"/tashkent/firm/\d+", a["href"]):
                links.setdefault(BASE + a["href"], path.name)
    return links


def category_from_firm(soup: BeautifulSoup) -> str | None:
    h1 = soup.find("h1")
    if not h1:
        return None
    context = h1.parent.get_text(" ", strip=True)
    after_name = context.split(h1.get_text(" ", strip=True), 1)[-1][:100].casefold()
    if "ветеринарная аптека" in after_name:
        return "veterinary_pharmacy"
    if any(
        term in after_name
        for term in (
            "ветеринарная клиника",
            "ветеринарный центр",
            "ветеринарное отделение",
            "ветеринарный отдел",
        )
    ):
        return "veterinary_clinic"
    if any(
        term in after_name
        for term in ("зоомагазин", "магазин зоотоваров", "магазин товаров для животных")
    ):
        return "pet_store"
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--topic", choices=("clinics", "petstores", "pharmacies", "petgoods"), default="clinics"
    )
    args = parser.parse_args()
    stem = {
        "clinics": "district_clinic",
        "petstores": "district_petstore",
        "pharmacies": "district_pharmacy",
        "petgoods": "district_petgoods",
    }[args.topic]
    output = DATA / f"2gis_{stem}_firm_suggestions.jsonl"
    log_path = DATA / f"2gis_{stem}_firm_checks.jsonl"
    known = {row["firm_id"] for row in read_jsonl(output)}
    known |= {
        row["firm_id"]
        for path in DATA.glob("2gis_*_firm_suggestions.jsonl")
        if path != output
        for row in read_jsonl(path)
    }
    checked = {
        row["firm_id"]
        for row in read_jsonl(log_path)
        if row["result"] == "held_no_target_category_or_address_pin"
    }
    links = links_from_saved_searches(args.topic)
    with (
        output.open("a", encoding="utf-8") as suggestions,
        log_path.open("a", encoding="utf-8") as log,
    ):
        for url, search_file in sorted(links.items()):
            if args.topic == "clinics" and search_file == "raw_2gis_bektemir_clinics_probe.html":
                continue  # Its twelve visible results were manually screened as human healthcare.
            firm_id = url.rstrip("/").split("/")[-1]
            if firm_id in known or firm_id in checked:
                continue
            try:
                page = fetch(url)
            except urllib.error.HTTPError as error:
                print(f"Stopped at {url}: HTTP {error.code}", flush=True)
                if error.code in {403, 429}:
                    break
                continue
            except (urllib.error.URLError, http.client.IncompleteRead, TimeoutError) as error:
                print(f"Read failed at {url}: {error}", flush=True)
                continue
            soup = BeautifulSoup(page, "html.parser")
            category = category_from_firm(soup)
            heading = soup.find("h1")
            row = (
                parse_firm(page, url, heading.get_text(" ", strip=True), category)
                if category and heading
                else None
            )
            result = {
                "firm_id": firm_id,
                "source_url": url,
                "search_file": search_file,
                "category_on_firm_page": category,
                "result": (
                    "physical_point_suggestion" if row else "held_no_target_category_or_address_pin"
                ),
            }
            log.write(json.dumps(result, ensure_ascii=False) + "\n")
            log.flush()
            if row:
                row["discovery_search_file"] = search_file
                suggestions.write(json.dumps(row, ensure_ascii=False) + "\n")
                suggestions.flush()
                known.add(firm_id)
            print(json.dumps(result), flush=True)
            time.sleep(1.5)


if __name__ == "__main__":
    main()
