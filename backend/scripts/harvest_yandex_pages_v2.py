"""Harvest accessible public Yandex search pages as V2 discovery hints.

Sequential requests only. Stops on access restrictions, never promotes places.
"""

import argparse
import json
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import UTC, datetime

from backend.scripts.probe_places_v2_yandex import DATA
from bs4 import BeautifulSoup

QUERY = "Товары для животных"
OUT = DATA / "yandex_pet_goods_pages_7plus.jsonl"
YIELDS = DATA / "yandex_page_yields.jsonl"


def parse(page: str, url: str, page_number: int, id_prefix: str = "ypgoods") -> list[dict]:
    soup = BeautifulSoup(page, "html.parser")
    rows = []
    for item in soup.select("li.search-snippet-view"):
        body = item.select_one("[data-object='search-list-item'][data-id]")
        title = item.select_one(".search-business-snippet-view__title")
        address = item.select_one(".search-business-snippet-view__address")
        cats = [
            tag.get_text(" ", strip=True).casefold()
            for tag in item.select(".search-business-snippet-view__category")
        ]
        if not body or not title or not address:
            continue
        if any("klinik" in cat or "клиник" in cat for cat in cats):
            category = "veterinary_clinic"
        elif any("zoodo" in cat or "зоомагаз" in cat or "pet shop" in cat for cat in cats):
            category = "pet_store"
        elif any(
            "dorixon" in cat
            or "ветаптек" in cat
            or "pharmacy" in cat
            or "veterinariya preparat" in cat
            for cat in cats
        ):
            category = "veterinary_pharmacy"
        else:
            continue
        point = body.get("data-coordinates", "").split(",")
        coords = None
        if len(point) == 2:
            lon, lat = [float(value) for value in point]
            if 40.9 <= lat <= 41.7 and 68.8 <= lon <= 69.7:
                coords = [lat, lon]
        rows.append(
            {
                "observation_id": f"{id_prefix}{page_number}_{body['data-id']}",
                "name": title.get_text(" ", strip=True),
                "address_hint": address.get_text(" ", strip=True),
                "category_hint": category,
                "coordinates_hint": coords,
                "yandex_org_id": body["data-id"],
                "source_url": url,
                "source_kind": "yandex_search",
                "discovery_status": "unverified",
            }
        )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--start", type=int, default=7)
    parser.add_argument("--end", type=int, default=12)
    parser.add_argument("--delay", type=float, default=2.0)
    parser.add_argument("--query", default=QUERY)
    parser.add_argument("--output", default=OUT.name)
    parser.add_argument("--yield-output", default=YIELDS.name)
    parser.add_argument("--id-prefix", default="ypgoods")
    parser.add_argument(
        "--base-url",
        default=None,
        help="Exact public category URL ending in /; overrides search query path",
    )
    args = parser.parse_args()
    out = DATA / args.output
    yield_path = DATA / args.yield_output
    known_ids = (
        {
            json.loads(line)["observation_id"]
            for line in out.read_text(encoding="utf-8").splitlines()
        }
        if out.exists()
        else set()
    )
    known_pairs = set()
    for path in DATA.glob("*.jsonl"):
        if path.name in {out.name, yield_path.name} or "probe" in path.name or "check" in path.name:
            continue
        for line in path.read_text(encoding="utf-8").splitlines():
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            if row.get("name") and row.get("address_hint"):
                known_pairs.add((row["name"].casefold(), row["address_hint"].casefold()))
    with (
        out.open("a", encoding="utf-8") as output,
        yield_path.open("a", encoding="utf-8") as yields,
    ):
        for page_number in range(args.start, args.end + 1):
            base_url = args.base_url or (
                "https://yandex.com/maps/10335/tashkent/search/"
                + urllib.parse.quote(args.query)
                + "/"
            )
            url = base_url + f"?page={page_number}"
            try:
                with urllib.request.urlopen(
                    urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=25
                ) as response:
                    page = response.read().decode("utf-8", errors="replace")
            except urllib.error.HTTPError as error:
                print(f"Stopped at page {page_number}: HTTP {error.code}", flush=True)
                break
            rows = parse(page, url, page_number, args.id_prefix)
            first_seen = 0
            for row in rows:
                if row["observation_id"] in known_ids:
                    continue
                pair = (row["name"].casefold(), row["address_hint"].casefold())
                if pair not in known_pairs:
                    first_seen += 1
                    known_pairs.add(pair)
                output.write(json.dumps(row, ensure_ascii=False) + "\n")
                known_ids.add(row["observation_id"])
            output.flush()
            result = {
                "page": page_number,
                "source_url": url,
                "target_observations": len(rows),
                "first_seen_name_address_pairs": first_seen,
                "checked_at": datetime.now(UTC).isoformat(),
                "note": "First-seen pair is a discovery yield, not verified physical places.",
            }
            yields.write(json.dumps(result, ensure_ascii=False) + "\n")
            yields.flush()
            print(json.dumps(result), flush=True)
            if not rows:
                break
            time.sleep(max(args.delay, 1.0))


if __name__ == "__main__":
    main()
