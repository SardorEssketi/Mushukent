"""Print nearest approved V2 locations for pharmacy-search firm suggestions."""

from __future__ import annotations

import argparse
import math

from backend.scripts.build_places_v2 import DATA, OUT, read_jsonl


def distance_m(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat1, lon1 = map(math.radians, a)
    lat2, lon2 = map(math.radians, b)
    h = (
        math.sin((lat2 - lat1) / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2
    )
    return 12742000 * math.asin(math.sqrt(h))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--topic", choices=("pharmacy", "petstore"), default="pharmacy")
    parser.add_argument("--page", type=int)
    args = parser.parse_args()
    verified = read_jsonl(OUT / "places_verified.jsonl")
    for row in read_jsonl(DATA / f"2gis_district_{args.topic}_firm_suggestions.jsonl"):
        if args.page and f"_page{args.page}_" not in row.get("discovery_search_file", ""):
            continue
        nearest = sorted(
            verified,
            key=lambda place: distance_m(
                row["coordinates"], (place["latitude"], place["longitude"])
            ),
        )[:3]
        print(row["firm_id"], row["name"], row["category"], row["district_hint"], row["address"])
        for place in nearest:
            print(
                " ",
                round(distance_m(row["coordinates"], (place["latitude"], place["longitude"]))),
                place["id"],
                place["name"],
                place["category"],
                place["address"],
            )


if __name__ == "__main__":
    main()
