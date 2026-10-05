"""Save public first-page 2GIS veterinary-pharmacy district search results.

Uses the district IDs already present in the saved V2 pet-store pages. The
saved HTML is discovery material only; firm-specific pages require review.
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.error
from datetime import UTC, datetime
from urllib.parse import quote

from backend.scripts.build_places_v2 import DATA, read_jsonl, write_jsonl
from backend.scripts.harvest_2gis_chain_v2 import fetch
from bs4 import BeautifulSoup


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", choices=("pharmacies", "petgoods"), default="pharmacies")
    args = parser.parse_args()
    log_path = DATA / (
        "2gis_district_pharmacy_search_checks.jsonl"
        if args.topic == "pharmacies"
        else "2gis_district_petgoods_search_checks.jsonl"
    )
    checks = read_jsonl(log_path)
    checked = {row["district"] for row in checks if row["status"] == "executed"}
    for prior in read_jsonl(DATA / "2gis_district_petstore_search_yields.jsonl"):
        district = prior["district"]
        if district in checked:
            continue
        district_id = re.search(r"district_id%3D(\d+)", prior["source_url"])
        if not district_id:
            raise ValueError(f"Missing district ID for {district}")
        query = "Ветеринарные аптеки (ветаптеки)" if args.topic == "pharmacies" else "Зоотовары"
        url = (
            "https://2gis.uz/tashkent/search/"
            + quote(query)
            + "/filters/district_id%3D"
            + district_id.group(1)
        )
        filename = "raw_2gis_" + district.lower().replace(" ", "") + f"_{args.topic}_probe.html"
        try:
            page = fetch(url)
        except urllib.error.HTTPError as error:
            checks.append(
                {
                    "district": district,
                    "source_url": url,
                    "status": "access_limited" if error.code in {403, 429} else "http_error",
                    "http_status": error.code,
                    "checked_at": datetime.now(UTC).isoformat(),
                }
            )
            write_jsonl(log_path, checks)
            if error.code in {403, 429}:
                break
            continue
        soup = BeautifulSoup(page, "html.parser")
        links = {
            a["href"]
            for a in soup.find_all("a", href=True)
            if re.fullmatch(r"/tashkent/firm/\d+", a["href"])
        }
        (DATA / filename).write_text(page, encoding="utf-8")
        checks.append(
            {
                "district": district,
                "source_url": url,
                "search_file": filename,
                "status": "executed",
                "result_links": len(links),
                "checked_at": datetime.now(UTC).isoformat(),
            }
        )
        write_jsonl(log_path, checks)
        print(json.dumps({"district": district, "result_links": len(links)}), flush=True)
        time.sleep(1.5)


if __name__ == "__main__":
    main()
