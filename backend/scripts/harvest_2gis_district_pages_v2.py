"""Follow public 2GIS district search pagination into saved V2 raw HTML.

Only discovery page links are collected here. A result is not a verified place.
The crawler uses visible next-page links, waits between requests, and stops on
access-control responses; it does not call private endpoints.
"""

from __future__ import annotations

import argparse
import json
import re
import time
import urllib.error
from datetime import UTC, datetime

from backend.scripts.build_places_v2 import DATA, read_jsonl, write_jsonl
from backend.scripts.harvest_2gis_chain_v2 import BASE, fetch
from bs4 import BeautifulSoup


def firm_ids(soup: BeautifulSoup) -> set[str]:
    return {
        a["href"].split("/")[-1]
        for a in soup.find_all("a", href=True)
        if re.fullmatch(r"/tashkent/firm/\d+", a["href"])
    }


def next_page_url(soup: BeautifulSoup, page: int) -> str | None:
    suffix = f"/page/{page}"
    for a in soup.find_all("a", href=True):
        if a["href"].endswith(suffix) and "/tashkent/search/" in a["href"]:
            return BASE + a["href"]
    return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", choices=("petstores", "clinics", "pharmacies"), required=True)
    parser.add_argument("--max-page", type=int, default=2)
    args = parser.parse_args()
    if args.max_page < 2 or args.max_page > 15:
        raise ValueError("max-page must be from 2 to 15")
    log_path = DATA / f"2gis_district_{args.topic}_pagination_checks.jsonl"
    checks = read_jsonl(log_path)
    done = {(row["search_file"], row["page"]) for row in checks if row["status"] == "executed"}
    for first in sorted(DATA.glob(f"raw_2gis_*_{args.topic}_probe.html")):
        if re.search(r"_page\d+_", first.name):
            continue
        stem = first.name.removesuffix(f"_{args.topic}_probe.html")
        previous = first
        known_ids = set()
        for page_no in range(1, args.max_page + 1):
            soup = BeautifulSoup(previous.read_text(encoding="utf-8"), "html.parser")
            ids = firm_ids(soup)
            if page_no == 1:
                known_ids |= ids
                continue
            url = next_page_url(soup, page_no)
            if not url:
                break
            target = DATA / f"{stem}_page{page_no}_{args.topic}_probe.html"
            if not target.exists():
                try:
                    target.write_text(fetch(url), encoding="utf-8")
                except urllib.error.HTTPError as error:
                    checks.append(
                        {
                            "search_file": first.name,
                            "page": page_no,
                            "source_url": url,
                            "status": (
                                "access_limited" if error.code in {403, 429} else "http_error"
                            ),
                            "http_status": error.code,
                            "checked_at": datetime.now(UTC).isoformat(),
                        }
                    )
                    write_jsonl(log_path, checks)
                    if error.code in {403, 429}:
                        return
                    break
                time.sleep(1.5)
            next_soup = BeautifulSoup(target.read_text(encoding="utf-8"), "html.parser")
            next_ids = firm_ids(next_soup)
            if (first.name, page_no) not in done:
                checks.append(
                    {
                        "search_file": first.name,
                        "page": page_no,
                        "source_url": url,
                        "status": "executed",
                        "result_links": len(next_ids),
                        "new_firm_links_vs_prior_pages": len(next_ids - known_ids),
                        "checked_at": datetime.now(UTC).isoformat(),
                    }
                )
                write_jsonl(log_path, checks)
                print(
                    json.dumps(
                        {
                            "district_file": first.name,
                            "page": page_no,
                            "result_links": len(next_ids),
                            "new_firm_links_vs_prior_pages": len(next_ids - known_ids),
                        }
                    ),
                    flush=True,
                )
            known_ids |= next_ids
            previous = target


if __name__ == "__main__":
    main()
