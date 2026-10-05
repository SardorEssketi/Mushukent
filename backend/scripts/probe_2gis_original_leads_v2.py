"""Probe every unresolved original V2 lead against public 2GIS search pages.

These are search suggestions only. Search-page coordinates and contacts are
never promoted. HTML is compressed into V2 raw material for later inspection.
"""

from __future__ import annotations

import argparse
import gzip
import json
import re
import time
import urllib.error
from datetime import UTC, datetime
from urllib.parse import quote

from backend.scripts.build_places_v2 import DATA, OUT, read_jsonl, write_jsonl
from backend.scripts.harvest_2gis_chain_v2 import fetch
from bs4 import BeautifulSoup


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=50)
    parser.add_argument("--short-retry", action="store_true")
    args = parser.parse_args()
    candidates = {row["candidate_id"]: row for row in read_jsonl(OUT / "places_candidates.jsonl")}
    original_ids = {
        row["candidate_id"]
        for filename in ("yandex_lead_probes.jsonl", "yandex_lead_probes_address.jsonl")
        for row in read_jsonl(DATA / filename)
    }
    first_pass = {
        row["candidate_id"]: row for row in read_jsonl(DATA / "2gis_original_lead_probes.jsonl")
    }
    log_path = DATA / (
        "2gis_original_lead_probes_short.jsonl"
        if args.short_retry
        else "2gis_original_lead_probes.jsonl"
    )
    log = read_jsonl(log_path)
    done = {row["candidate_id"] for row in log}
    queue = [
        candidates[id]
        for id in sorted(original_ids)
        if id in candidates
        and candidates[id]["status"] == "discovery_only"
        and id not in done
        and (not args.short_retry or first_pass.get(id, {}).get("http_status") == 404)
    ]
    raw_dir = DATA / ("raw_2gis_lead_probes_short" if args.short_retry else "raw_2gis_lead_probes")
    raw_dir.mkdir(exist_ok=True)
    attempted = 0
    for candidate in queue:
        if attempted >= args.limit:
            break
        name = candidate["name_hint"]
        if args.short_retry:
            quoted = re.search(r'["“]([^"”]{3,70})["”]', name)
            name = (
                quoted.group(1)
                if quoted
                else re.split(r"\s*\(|\s+(?:ООО|ЧП|МЧЖ|MChJ)\b", name, maxsplit=1)[0]
            )
            name = re.sub(
                r"^(?:Аптека ветеринарная|Ветеринарная клиника|Зоологический магазин)\s+",
                "",
                name,
                flags=re.IGNORECASE,
            )
        query = name[:100].strip()
        if candidate.get("district_hint") and not args.short_retry:
            query += " " + candidate["district_hint"]
        url = "https://2gis.uz/tashkent/search/" + quote(query)
        try:
            page = fetch(url)
        except urllib.error.HTTPError as error:
            if error.code in {403, 429}:
                print(f"Stopped on access restriction HTTP {error.code}", flush=True)
                break
            result = {"status": "http_error", "http_status": error.code, "result_firm_ids": []}
        except (urllib.error.URLError, TimeoutError) as error:
            result = {"status": "network_error", "error": str(error)[:120], "result_firm_ids": []}
        else:
            soup = BeautifulSoup(page, "html.parser")
            ids = sorted(
                {
                    a["href"].split("/")[-1]
                    for a in soup.find_all("a", href=True)
                    if re.fullmatch(r"/tashkent/firm/\d+", a["href"])
                }
            )
            filename = candidate["candidate_id"] + ".html.gz"
            with gzip.open(raw_dir / filename, "wt", encoding="utf-8") as output:
                output.write(page)
            result = {
                "status": "executed",
                "result_firm_ids": ids,
                "raw_file": raw_dir.name + "/" + filename,
            }
        result.update(
            {
                "candidate_id": candidate["candidate_id"],
                "name_hint": candidate["name_hint"],
                "address_hint": candidate.get("address_hint"),
                "district_hint": candidate.get("district_hint"),
                "query": query,
                "source_url": url,
                "checked_at": datetime.now(UTC).isoformat(),
            }
        )
        log.append(result)
        write_jsonl(log_path, log)
        attempted += 1
        if attempted % 10 == 0:
            print(
                json.dumps({"probed": attempted, "remaining": len(queue) - attempted}), flush=True
            )
        time.sleep(1.5)
    print(json.dumps({"attempted_now": attempted, "total_logged": len(log)}), flush=True)


if __name__ == "__main__":
    main()
