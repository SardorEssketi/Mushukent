"""Slow public-page probe of V2 discovery leads; emits review suggestions only.

No suggestion is imported or verified automatically. Stop on access-control responses.
"""

import argparse
import html
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "data" / "places_v2"
QUEUE = DATA / "output" / "places_verification_queue.jsonl"
OUT = DATA / "yandex_lead_probes_address.jsonl"


def match(pattern: str, page: str) -> str | None:
    found = re.search(pattern, page, re.IGNORECASE)
    return html.unescape(found.group(1)) if found else None


def extract(page: str) -> dict:
    canonical = match(r'<link rel="canonical" href="([^"]+)"', page)
    title = match(r'<meta property="og:title" content="([^"]+)"', page)
    address = match(r'<meta itemProp="address" content="([^"]+)"', page)
    coordinates = match(r'data-coordinates="([0-9.]+,[0-9.]+)"', page)
    location = None
    if coordinates:
        longitude, latitude = [float(value) for value in coordinates.split(",")]
        if 40.9 <= latitude <= 41.7 and 68.8 <= longitude <= 69.7:
            location = [latitude, longitude]
    organization = canonical if canonical and "/org/" in canonical else None
    # Search-page map centers are not business pins. Discard them unless the
    # page has opened an organization result.
    return {
        "organization_url": organization,
        "result_title": title,
        "result_address": address,
        "result_coordinates": location if organization else None,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=200)
    parser.add_argument("--delay", type=float, default=1.5)
    args = parser.parse_args()
    queue = [json.loads(line) for line in QUEUE.read_text(encoding="utf-8").splitlines()]
    candidates = {
        row["candidate_id"]: row
        for row in (
            json.loads(line)
            for line in (DATA / "output" / "places_candidates.jsonl")
            .read_text(encoding="utf-8")
            .splitlines()
        )
    }
    done = (
        {json.loads(line)["candidate_id"] for line in OUT.read_text(encoding="utf-8").splitlines()}
        if OUT.exists()
        else set()
    )
    leads = [
        row
        for row in queue
        if row["status"] == "discovery_only" and row["candidate_id"] not in done
    ]
    count = 0
    with OUT.open("a", encoding="utf-8") as output:
        for lead in leads:
            if count >= args.limit:
                break
            address_hint = candidates[lead["candidate_id"]].get("address_hint")
            query = " ".join(filter(None, [lead["name_hint"], address_hint]))[:180]
            url = "https://yandex.com/maps/10335/tashkent/search/" + urllib.parse.quote(query) + "/"
            try:
                with urllib.request.urlopen(
                    urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"}), timeout=25
                ) as response:
                    page = response.read().decode("utf-8", errors="replace")
                result = extract(page)
                result["probe_status"] = (
                    "suggestion_only" if result["organization_url"] else "no_organization_result"
                )
            except urllib.error.HTTPError as error:
                if error.code in {401, 403, 429}:
                    print(f"Stopped on access restriction {error.code}: {url}", flush=True)
                    break
                result = {"probe_status": "http_error", "http_status": error.code}
            except (urllib.error.URLError, TimeoutError) as error:
                result = {"probe_status": "network_error", "error": str(error)[:120]}
            result.update(
                {
                    "candidate_id": lead["candidate_id"],
                    "name_hint": lead["name_hint"],
                    "address_hint": address_hint,
                    "category_hint": lead["category_hint"],
                    "search_url": url,
                    "checked_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                }
            )
            output.write(json.dumps(result, ensure_ascii=False) + "\n")
            output.flush()
            count += 1
            if count % 10 == 0:
                print(f"Probed {count} leads", flush=True)
            time.sleep(max(args.delay, 1.0))


if __name__ == "__main__":
    main()
