"""Read public 2GIS branch pages into review-only V2 discovery suggestions.

Each firm page must bind its own name, address and route point to the same firm
ID. The output never supplies verified contact fields or auto-promotes a place.
"""

from __future__ import annotations

import argparse
import http.client
import json
import re
import time
import urllib.error
import urllib.request
from datetime import UTC, datetime

from bs4 import BeautifulSoup

from .build_places_v2 import DATA

BASE = "https://2gis.uz"
DISTRICTS = {
    "Алмазарск": "Olmazor",
    "Бектемирск": "Bektemir",
    "Мирабадск": "Mirobad",
    "Мирзо-Улугбекск": "Mirzo Ulugbek",
    "Сергелийск": "Sergeli",
    "Учтепинск": "Uchtepa",
    "Чиланзарск": "Chilanzar",
    "Шайхантахурск": "Shaykhantahur",
    "Юнусабадск": "Yunusabad",
    "Яккасарайск": "Yakkasaray",
    "Янгихаётск": "Yangihayot",
    "Яшнабадск": "Yashnabad",
}


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=25) as response:
        if response.status != 200:
            raise ValueError(f"HTTP {response.status}: {url}")
        return response.read().decode("utf-8", errors="replace")


def branch_links(page: str, brand: str) -> set[str]:
    soup = BeautifulSoup(page, "html.parser")
    return {
        BASE + a["href"]
        for a in soup.find_all("a", href=True)
        if re.fullmatch(r"/tashkent/firm/\d+", a["href"])
        and brand.casefold() in a.get_text(" ", strip=True).casefold()
    }


def district_filter_links(page: str, branch_id: str) -> set[str]:
    soup = BeautifulSoup(page, "html.parser")
    return {
        BASE + a["href"]
        for a in soup.find_all("a", href=True)
        if f"/tashkent/branches/{branch_id}/filters/district_id" in a["href"]
    }


def parse_firm(page: str, url: str, brand: str, category: str) -> dict | None:
    soup = BeautifulSoup(page, "html.parser")
    firm_id = url.rstrip("/").split("/")[-1]
    heading = soup.find("h1")
    if not heading or brand.casefold() not in heading.get_text(" ", strip=True).casefold():
        return None
    route = next(
        (
            a["href"]
            for a in soup.find_all("a", href=True)
            if "/directions/points/" in a["href"] and f"%3B{firm_id}" in a["href"]
        ),
        None,
    )
    geo = next((a for a in soup.find_all("a", href=True) if "/tashkent/geo/" in a["href"]), None)
    if not route or not geo:
        return None
    match = re.search(r"%7C([0-9.]+)%2C([0-9.]+)%3B", route)
    if not match:
        return None
    lon, lat = float(match.group(1)), float(match.group(2))
    if not (41.15 <= lat <= 41.45 and 69.10 <= lon <= 69.48):
        return None
    address = geo.get_text(" ", strip=True).replace("\u200b", "")
    context = (
        geo.parent.parent.parent.get_text(" ", strip=True)
        if geo.parent and geo.parent.parent and geo.parent.parent.parent
        else ""
    )
    district = next((name for needle, name in DISTRICTS.items() if needle in context), None)
    return {
        "firm_id": firm_id,
        "name": heading.get_text(" ", strip=True),
        "category": category,
        "address": address,
        "district_hint": district,
        "coordinates": [lat, lon],
        "source_url": url,
        "route_url": BASE + route,
        "checked_at": datetime.now(UTC).isoformat(),
        "evidence_status": "branch_firm_page_suggestion",
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--branch-id", required=True)
    parser.add_argument("--brand", required=True)
    parser.add_argument("--category", required=True)
    parser.add_argument("--prefix", required=True)
    parser.add_argument("--delay", type=float, default=2.0)
    args = parser.parse_args()
    output = DATA / f"2gis_{args.prefix}_firm_suggestions.jsonl"
    yield_output = DATA / f"2gis_{args.prefix}_branch_yields.jsonl"
    known = (
        {json.loads(x)["firm_id"] for x in output.read_text(encoding="utf-8").splitlines()}
        if output.exists()
        else set()
    )
    root = f"{BASE}/tashkent/branches/{args.branch_id}"
    try:
        root_page = fetch(root)
    except (urllib.error.HTTPError, urllib.error.URLError) as error:
        print(f"Stopped: {error}", flush=True)
        return
    pages = [root] + sorted(district_filter_links(root_page, args.branch_id))
    found = set()
    with (
        output.open("a", encoding="utf-8") as rows_file,
        yield_output.open("a", encoding="utf-8") as yield_file,
    ):
        for page_url in pages:
            try:
                page = root_page if page_url == root else fetch(page_url)
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    print(f"Unavailable district filter: {page_url}", flush=True)
                    continue
                print(f"Stopped: {error}", flush=True)
                break
            except urllib.error.URLError as error:
                print(f"Stopped: {error}", flush=True)
                break
            links = branch_links(page, args.brand)
            # A one-result filtered page may resolve directly to the firm.
            canonical = BeautifulSoup(page, "html.parser").find("link", rel="canonical")
            if canonical and re.search(r"/tashkent/firm/\d+", canonical.get("href", "")):
                links.add(canonical["href"])
            new_links = links - found
            found |= links
            info = {
                "source_url": page_url,
                "first_seen_firm_links": len(new_links),
                "firm_links": len(links),
                "checked_at": datetime.now(UTC).isoformat(),
            }
            yield_file.write(json.dumps(info, ensure_ascii=False) + "\n")
            yield_file.flush()
            print(json.dumps(info, ensure_ascii=False), flush=True)
            time.sleep(max(args.delay, 1.0))
        for firm_url in sorted(found):
            firm_id = firm_url.rstrip("/").split("/")[-1]
            if firm_id in known:
                continue
            try:
                row = parse_firm(fetch(firm_url), firm_url, args.brand, args.category)
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    print(f"Unavailable firm: {firm_url}", flush=True)
                    continue
                print(f"Stopped: {error}", flush=True)
                break
            except (urllib.error.URLError, http.client.IncompleteRead) as error:
                print(f"Transient firm read failure: {firm_url}: {error}", flush=True)
                continue
            if row:
                rows_file.write(json.dumps(row, ensure_ascii=False) + "\n")
                rows_file.flush()
                known.add(firm_id)
                print(
                    json.dumps({"firm_id": firm_id, "address": row["address"]}, ensure_ascii=False),
                    flush=True,
                )
            time.sleep(max(args.delay, 1.0))


if __name__ == "__main__":
    main()
