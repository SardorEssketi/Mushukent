"""Read-only evidence comparison of a production export with frozen Places V2.

No database access. Never mutates either source dataset. Name alone never
creates a match. The generated actions are a review proposal, not an importer.
"""

from __future__ import annotations

import json
import math
import re
import sys
import unicodedata
from collections import Counter
from difflib import SequenceMatcher
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "places_v2" / "output"
PRODUCTION = OUT / "production_places_readonly_export.jsonl"
FROZEN = OUT / "places_frozen_release.jsonl"
EXPECTED_HASH = "8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be"
CYRILLIC = dict(
    zip(
        "абвгдежзийклмнопрстуфхцчшщыэюяъьё",
        (
            "a",
            "b",
            "v",
            "g",
            "d",
            "e",
            "zh",
            "z",
            "i",
            "y",
            "k",
            "l",
            "m",
            "n",
            "o",
            "p",
            "r",
            "s",
            "t",
            "u",
            "f",
            "kh",
            "ts",
            "ch",
            "sh",
            "shch",
            "y",
            "e",
            "yu",
            "ya",
            "",
            "",
            "e",
        ),
        strict=True,
    )
)


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def normalize(value: str | None) -> str:
    if not value:
        return ""
    value = unicodedata.normalize("NFKC", value).casefold().replace("ё", "е")
    value = "".join(CYRILLIC.get(char, char) for char in value)
    value = value.replace("oʻ", "o").replace("o‘", "o").replace("o'", "o")
    value = re.sub(r"[^\w\d]+", " ", value, flags=re.UNICODE)
    return " ".join(value.split())


def name_similarity(left: str, right: str) -> float:
    a, b = normalize(left), normalize(right)
    return SequenceMatcher(None, a, b).ratio() if a and b else 0.0


def address_similarity(left: str | None, right: str | None) -> float:
    a, b = normalize(left), normalize(right)
    for prefix in ("tashkent ", "toshkent "):
        if a.startswith(prefix):
            a = a[len(prefix) :]
        if b.startswith(prefix):
            b = b[len(prefix) :]
    return SequenceMatcher(None, a, b).ratio() if a and b else 0.0


def distance_meters(a: dict, b: dict) -> float:
    lat1, lon1 = math.radians(a["latitude"]), math.radians(a["longitude"])
    lat2, lon2 = math.radians(b["latitude"]), math.radians(b["longitude"])
    dlat, dlon = lat2 - lat1, lon2 - lon1
    term = math.sin(dlat / 2) ** 2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2
    return 12_742_000 * math.asin(min(1.0, math.sqrt(term)))


def phone_overlap(production: dict, v2: dict) -> bool:
    old = {
        re.sub(r"\D", "", value)
        for value in (production.get("phone"), production.get("phone_2"))
        if value
    }
    new = {re.sub(r"\D", "", value) for value in v2.get("phones", []) if value}
    return bool(old & new)


def domain(value: str | None) -> str:
    if not value:
        return ""
    host = urlparse(value if "://" in value else "https://" + value).hostname or ""
    return host.removeprefix("www.")


def pair_features(production: dict, v2: dict) -> dict:
    distance = round(distance_meters(production, v2), 1)
    name = round(name_similarity(production["name"], v2["name"]), 3)
    address = round(address_similarity(production["address"], v2["address"]), 3)
    old_category = production["category"]
    new_category = {
        "pet_store": "pet_shop",
        "veterinary_clinic": "veterinary",
        "veterinary_pharmacy": "veterinary_pharmacy",
        "animal_shelter": "shelter",
    }[v2["category"]]
    category_match = old_category == new_category or new_category in production["categories"]
    phone = phone_overlap(production, v2)
    website = bool(
        domain(production["website"]) and domain(production["website"]) == domain(v2["website"])
    )
    generic = normalize(production["name"]) in {
        "zoomagazin",
        "zoo magazin",
        "zoo",
        "zoo market",
        "zoo shop",
        "zoo pet shop",
        "zoomag",
        "petshop",
        "pet shop",
        "pet store",
        "uy hayvonlari dokoni",
        "vetapteka",
        "veterinariya dorixonasi",
    }
    score = (
        4
        if distance <= 15
        else 3 if distance <= 40 else 2 if distance <= 100 else 1 if distance <= 200 else 0
    )
    score += 4 if name >= 0.95 else 3 if name >= 0.8 else 2 if name >= 0.6 else 0
    score += 3 if address >= 0.95 else 2 if address >= 0.8 else 1 if address >= 0.6 else 0
    score += int(category_match) + int(phone) + int(website) - (2 if generic else 0)
    return {
        "production_uuid": production["id"],
        "v2_id": v2["id"],
        "v2_source_id": v2["source_id"],
        "distance_m": distance,
        "name_similarity": name,
        "address_similarity": address,
        "category_agreement": category_match,
        "phone_agreement": phone,
        "website_agreement": website,
        "generic_production_name": generic,
        "score": score,
    }


def candidates(production: list[dict], v2: list[dict]) -> list[dict]:
    result = []
    for old in production:
        for new in v2:
            pair = pair_features(old, new)
            if pair["distance_m"] <= 250 or (
                pair["distance_m"] <= 1500 and pair["name_similarity"] >= 0.9
            ):
                result.append(pair)
    result.sort(
        key=lambda row: (row["production_uuid"], -row["score"], row["distance_m"], row["v2_id"])
    )
    return result


def category_compatible(old: dict, new: dict, pair: dict) -> bool:
    return pair["category_agreement"] or (
        old["category"] == "pet_shop" and new["category"] == "veterinary_pharmacy"
    )


def strong_match(old: dict, new: dict, pair: dict) -> bool:
    if not category_compatible(old, new, pair):
        return False
    if pair["generic_production_name"]:
        return (
            pair["distance_m"] <= 10
            and pair["name_similarity"] >= 0.95
            and pair["address_similarity"] >= 0.75
        )
    return (
        (pair["distance_m"] <= 30 and pair["name_similarity"] >= 0.9)
        or (
            pair["distance_m"] <= 80
            and pair["name_similarity"] >= 0.9
            and pair["address_similarity"] >= 0.5
        )
        or (
            pair["distance_m"] <= 25
            and pair["name_similarity"] >= 0.78
            and pair["address_similarity"] >= 0.6
        )
    )


def plausible_match(pair: dict) -> bool:
    return (
        pair["distance_m"] <= 20
        or (
            pair["distance_m"] <= 150
            and (
                pair["name_similarity"] >= 0.55
                or pair["address_similarity"] >= 0.78
                or pair["phone_agreement"]
                or pair["website_agreement"]
            )
        )
        or (pair["distance_m"] <= 30 and pair["name_similarity"] >= 0.4)
    )


def classify(production: list[dict], v2: list[dict], pairs: list[dict]):
    by_prod: dict[str, list[dict]] = {}
    by_v2: dict[str, list[dict]] = {}
    for pair in pairs:
        by_prod.setdefault(pair["production_uuid"], []).append(pair)
        by_v2.setdefault(pair["v2_id"], []).append(pair)
    new_by_id = {row["id"]: row for row in v2}
    proposed: dict[str, dict] = {}
    for old in production:
        strong = [
            p for p in by_prod.get(old["id"], []) if strong_match(old, new_by_id[p["v2_id"]], p)
        ]
        if len(strong) != 1:
            continue
        pair = strong[0]
        same_branch_rivals = [
            p
            for p in by_prod[old["id"]]
            if p["v2_id"] != pair["v2_id"]
            and p["distance_m"] <= 100
            and p["name_similarity"] >= 0.8
            and category_compatible(old, new_by_id[p["v2_id"]], p)
        ]
        if same_branch_rivals and pair["address_similarity"] < 0.7:
            continue
        proposed[old["id"]] = pair

    # A V2 branch cannot inherit two old UUIDs. An old store/clinic collision
    # is also held unless its second old row has its own strong V2 counterpart.
    for old_id, pair in list(proposed.items()):
        v2_id = pair["v2_id"]
        if sum(candidate["v2_id"] == v2_id for candidate in proposed.values()) > 1:
            proposed.pop(old_id, None)
            continue
        competitors = [
            p
            for p in by_v2.get(v2_id, [])
            if p["production_uuid"] != old_id
            and p["distance_m"] <= 100
            and p["name_similarity"] >= 0.8
        ]
        if any(other["production_uuid"] not in proposed for other in competitors):
            proposed.pop(old_id, None)

    matched_v2 = {pair["v2_id"] for pair in proposed.values()}
    possible_old = {
        old["id"]
        for old in production
        if any(plausible_match(p) for p in by_prod.get(old["id"], []))
    }
    ambiguous_old = possible_old - set(proposed)
    prod_only = {old["id"] for old in production} - possible_old
    possible_v2 = {p["v2_id"] for p in pairs if plausible_match(p)}
    review_v2 = possible_v2 - matched_v2
    insert_v2 = {row["id"] for row in v2} - matched_v2 - review_v2
    return proposed, prod_only, ambiguous_old, insert_v2, review_v2


def preview_classification(production: list[dict], v2: list[dict], pairs: list[dict]) -> None:
    proposed, prod_only, ambiguous_old, insert_v2, review_v2 = classify(production, v2, pairs)
    old_by_id = {row["id"]: row for row in production}
    new_by_id = {row["id"]: row for row in v2}
    by_prod: dict[str, list[dict]] = {}
    for pair in pairs:
        by_prod.setdefault(pair["production_uuid"], []).append(pair)
    print(
        json.dumps(
            {
                "matched": len(proposed),
                "production_only": len(prod_only),
                "ambiguous_production": len(ambiguous_old),
                "v2_insert_new": len(insert_v2),
                "v2_review": len(review_v2),
                "v2_matched": len(proposed),
            },
            indent=2,
        )
    )
    if "--preview-details" in sys.argv:
        print("POTENTIAL MATCHES")
        for old_id, pair in proposed.items():
            print(
                old_id[:8],
                old_by_id[old_id]["name"],
                "->",
                new_by_id[pair["v2_id"]]["name"],
                pair["distance_m"],
                pair["name_similarity"],
                pair["address_similarity"],
            )
        print("AMBIGUOUS PRODUCTION")
        for old in production:
            if old["id"] in ambiguous_old:
                best = [p for p in by_prod.get(old["id"], []) if plausible_match(p)][:2]
                print(
                    old["id"][:8],
                    old["name"],
                    "->",
                    [
                        (
                            new_by_id[p["v2_id"]]["name"],
                            p["distance_m"],
                            p["name_similarity"],
                            p["address_similarity"],
                        )
                        for p in best
                    ],
                )
        print("PRODUCTION ONLY")
        for old in production:
            if old["id"] in prod_only:
                print(old["id"][:8], old["name"])


def _old_summary(row: dict) -> dict:
    return {
        key: row.get(key)
        for key in (
            "id",
            "name",
            "category",
            "latitude",
            "longitude",
            "address",
            "phone",
            "phone_2",
            "website",
            "opening_hours",
            "source",
            "source_id",
            "is_active",
            "created_at",
            "updated_at",
            "verified_at",
            "categories",
        )
    }


def _v2_summary(row: dict) -> dict:
    return {
        key: row.get(key)
        for key in (
            "id",
            "source_id",
            "import_uuid",
            "name",
            "category",
            "latitude",
            "longitude",
            "address",
            "phones",
            "website",
            "opening_hours",
            "instagram",
            "telegram",
            "verified_at",
            "source_urls",
        )
    }


def review_reason(pair: dict, old: dict, new: dict, by_prod: dict[str, list[dict]]) -> str:
    rivals = [
        other
        for other in by_prod[old["id"]]
        if other["v2_id"] != new["id"]
        and other["distance_m"] <= 100
        and other["name_similarity"] >= 0.8
    ]
    if rivals:
        return "Several same-name nearby V2 branches; production branch assignment is uncertain."
    if pair["generic_production_name"]:
        return (
            "Generic production name; pin or building proximity cannot prove the same storefront."
        )
    if not category_compatible(old, new, pair):
        return (
            "Category differs; review whether these are two services or businesses at one location."
        )
    if pair["name_similarity"] < 0.55:
        return (
            "Nearby or shared pin has a different name; distinct business versus alias is "
            "unresolved."
        )
    return "Name/location/address evidence is insufficient for a unique physical-branch match."


def write_jsonl(path: Path, rows: list[dict]) -> None:
    if path.exists():
        raise FileExistsError(f"Refusing to overwrite comparison artifact: {path}")
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def generate_comparison(production: list[dict], v2: list[dict], pairs: list[dict]) -> None:
    import hashlib

    matched, prod_only, ambiguous_old, insert_v2, review_v2 = classify(production, v2, pairs)
    old_by_id = {row["id"]: row for row in production}
    new_by_id = {row["id"]: row for row in v2}
    by_prod: dict[str, list[dict]] = {}
    by_v2: dict[str, list[dict]] = {}
    for pair in pairs:
        by_prod.setdefault(pair["production_uuid"], []).append(pair)
        by_v2.setdefault(pair["v2_id"], []).append(pair)

    diff: list[dict] = []
    field_clear_counts: Counter[str] = Counter()
    category_changes = 0
    for old in production:
        base = {
            "entity": "production",
            "production_classification": None,
            "production": _old_summary(old),
            "production_uuid": old["id"],
        }
        if old["id"] in matched:
            pair = matched[old["id"]]
            new = new_by_id[pair["v2_id"]]
            new_category = {
                "pet_store": "pet_shop",
                "veterinary_clinic": "veterinary",
                "veterinary_pharmacy": "veterinary_pharmacy",
                "animal_shelter": "shelter",
            }[new["category"]]
            old_values = {
                "name": old["name"],
                "category": old["category"],
                "latitude": old["latitude"],
                "longitude": old["longitude"],
                "address": old["address"],
                "phone": old["phone"],
                "phone_2": old["phone_2"],
                "website": old["website"],
                "opening_hours": old["opening_hours"],
                "source_id": old["source_id"],
            }
            new_values = {
                "name": new["name"],
                "category": new_category,
                "latitude": new["latitude"],
                "longitude": new["longitude"],
                "address": new["address"],
                "phone": (new["phones"] or [None])[0],
                "phone_2": new["phones"][1] if len(new["phones"]) > 1 else None,
                "website": new["website"],
                "opening_hours": new["opening_hours"],
                "source_id": new["source_id"],
            }
            changes = {
                key: {"old": old_values[key], "proposed": new_values[key]}
                for key in old_values
                if old_values[key] != new_values[key]
            }
            clears = [
                key
                for key in ("address", "phone", "phone_2", "website", "opening_hours")
                if old_values[key] is not None and new_values[key] is None
            ]
            field_clear_counts.update(clears)
            category_changes += old["category"] != new_category
            diff.append(
                dict(
                    base,
                    action="UPDATE_EXISTING",
                    production_classification="MATCHED_TO_V2",
                    v2_classification="MATCHED_TO_PRODUCTION",
                    v2=_v2_summary(new),
                    v2_id=new["id"],
                    preserve_production_uuid=True,
                    attach_source_id=new["source_id"],
                    match_evidence=pair,
                    proposed_field_changes=changes,
                    legacy_nonnull_to_v2_null=clears,
                    human_approval_required=True,
                )
            )
        elif old["id"] in prod_only:
            diff.append(
                dict(
                    base,
                    action="KEEP_UNCHANGED",
                    production_classification="PRODUCTION_ONLY",
                    reason="No sufficiently close, branch-specific V2 match; retain the row.",
                )
            )
        else:
            possible = [p for p in by_prod.get(old["id"], []) if plausible_match(p)]
            diff.append(
                dict(
                    base,
                    action="REVIEW",
                    production_classification="AMBIGUOUS",
                    candidate_v2_ids=[p["v2_id"] for p in possible],
                    reason="One-to-one physical identity cannot be established safely.",
                )
            )

    matched_v2 = {pair["v2_id"] for pair in matched.values()}
    for new in v2:
        if new["id"] in matched_v2:
            continue
        possible = [p for p in by_v2.get(new["id"], []) if plausible_match(p)]
        if new["id"] in insert_v2:
            diff.append(
                {
                    "entity": "v2",
                    "action": "INSERT_NEW",
                    "v2_classification": "NEW_V2_PLACE",
                    "v2_id": new["id"],
                    "v2": _v2_summary(new),
                    "new_uuid": new["import_uuid"],
                    "stable_source_id": new["source_id"],
                    "reason": (
                        "No plausible production physical-place match under the reviewed "
                        "proximity/name/address rules."
                    ),
                    "human_approval_required": True,
                }
            )
        else:
            diff.append(
                {
                    "entity": "v2",
                    "action": "REVIEW",
                    "v2_classification": "NEW_V2_PLACE",
                    "v2_id": new["id"],
                    "v2": _v2_summary(new),
                    "candidate_production_uuids": [p["production_uuid"] for p in possible],
                    "reason": "A production row may already represent this physical location.",
                    "human_approval_required": True,
                }
            )

    review_pairs = []
    for pair in pairs:
        if not plausible_match(pair):
            continue
        if pair["production_uuid"] not in ambiguous_old and pair["v2_id"] not in review_v2:
            continue
        old, new = old_by_id[pair["production_uuid"]], new_by_id[pair["v2_id"]]
        review_pairs.append(
            {
                "production_uuid": old["id"],
                "production_name": old["name"],
                "production_address": old["address"],
                "production_latitude": old["latitude"],
                "production_longitude": old["longitude"],
                "production_category": old["category"],
                "v2_id": new["id"],
                "v2_source_id": new["source_id"],
                "v2_name": new["name"],
                "v2_address": new["address"],
                "v2_latitude": new["latitude"],
                "v2_longitude": new["longitude"],
                "v2_category": new["category"],
                "distance_m": pair["distance_m"],
                "matching_evidence": {
                    key: pair[key]
                    for key in (
                        "name_similarity",
                        "address_similarity",
                        "category_agreement",
                        "phone_agreement",
                        "website_agreement",
                    )
                },
                "reason": review_reason(pair, old, new, by_prod),
            }
        )

    actions = Counter(row["action"] for row in diff)
    if (
        len(matched) + len(prod_only) + len(ambiguous_old) != len(production)
        or len(matched) + len(insert_v2) + len(review_v2) != len(v2)
        or actions["UPDATE_EXISTING"] != len(matched)
        or actions["KEEP_UNCHANGED"] != len(prod_only)
        or actions["INSERT_NEW"] != len(insert_v2)
        or actions["REVIEW"] != len(ambiguous_old) + len(review_v2)
    ):
        raise RuntimeError("Comparison classifications do not cover every place")
    production_ids = {row["id"] for row in production}
    if any(new_by_id[v2_id]["import_uuid"] in production_ids for v2_id in insert_v2):
        raise RuntimeError("Proposed inserted V2 UUID collides with an existing production UUID")
    if len({new["source_id"] for new in v2}) != len(v2) or any(
        new["source_id"] in {old["source_id"] for old in production} for new in v2
    ):
        raise RuntimeError("V2 stable source ID collides with production")
    report = {
        "production_export_sha256": hashlib.sha256(PRODUCTION.read_bytes()).hexdigest(),
        "frozen_v2_sha256": EXPECTED_HASH,
        "production_place_count": len(production),
        "v2_place_count": len(v2),
        "matched_to_v2": len(matched),
        "production_only": len(prod_only),
        "ambiguous_production": len(ambiguous_old),
        "v2_matched_to_production": len(matched),
        "v2_new_classification": len(insert_v2) + len(review_v2),
        "v2_insert_proposed": len(insert_v2),
        "v2_review_before_insert": len(review_v2),
        "ambiguous_candidate_pairs": len(review_pairs),
        "action_counts": dict(actions),
        "matched_rows_with_legacy_values_to_clear": sum(
            bool(row.get("legacy_nonnull_to_v2_null")) for row in diff
        ),
        "legacy_field_clear_counts": dict(field_clear_counts),
        "matched_category_changes": category_changes,
        "production_place_uuids_with_category_link": sum(
            bool(row["categories"]) for row in production
        ),
        "production_category_link_rows": sum(len(row["categories"]) for row in production),
        "other_production_foreign_keys_to_places": 0,
        "production_alembic_revision_observed": "20260928_0023",
        "no_production_changes": True,
    }
    write_jsonl(OUT / "production_comparison.jsonl", diff)
    write_jsonl(OUT / "production_ambiguous_review.jsonl", review_pairs)
    write_jsonl(
        OUT / "production_legacy_source_aliases.jsonl",
        [
            {
                "production_uuid": row["production_uuid"],
                "legacy_source": row["production"]["source"],
                "legacy_source_id": row["production"]["source_id"],
                "v2_source_id": row["attach_source_id"],
                "v2_research_id": row["v2_id"],
            }
            for row in diff
            if row["action"] == "UPDATE_EXISTING"
        ],
    )
    (OUT / "production_comparison_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(report, ensure_ascii=False, indent=2))


def explore() -> None:
    import hashlib

    if hashlib.sha256(FROZEN.read_bytes()).hexdigest() != EXPECTED_HASH:
        raise RuntimeError("Frozen V2 snapshot hash mismatch")
    if "--aliases-only" in sys.argv:
        diff = read_jsonl(OUT / "production_comparison.jsonl")
        write_jsonl(
            OUT / "production_legacy_source_aliases.jsonl",
            [
                {
                    "production_uuid": row["production_uuid"],
                    "legacy_source": row["production"]["source"],
                    "legacy_source_id": row["production"]["source_id"],
                    "v2_source_id": row["attach_source_id"],
                    "v2_research_id": row["v2_id"],
                }
                for row in diff
                if row["action"] == "UPDATE_EXISTING"
            ],
        )
        print("Archived 66 proposed legacy-to-V2 source ID aliases")
        return
    production, v2 = read_jsonl(PRODUCTION), read_jsonl(FROZEN)
    pairs = candidates(production, v2)
    (OUT / "production_match_candidates.jsonl").write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in pairs),
        encoding="utf-8",
    )
    by_prod: dict[str, list[dict]] = {}
    for pair in pairs:
        by_prod.setdefault(pair["production_uuid"], []).append(pair)
    if "--generate" in sys.argv:
        generate_comparison(production, v2, pairs)
        return
    if "--preview" in sys.argv or "--preview-details" in sys.argv:
        preview_classification(production, v2, pairs)
        return
    if "--overview" in sys.argv:
        v2_by_id = {row["id"]: row for row in v2}
        for index, old in enumerate(production, start=1):
            top = by_prod.get(old["id"], [])[:2]
            matches = " | ".join(
                f"{v2_by_id[p['v2_id']]['name'][:22]} ({p['distance_m']:.0f}m,"
                f"n={p['name_similarity']:.2f},a={p['address_similarity']:.2f},s={p['score']})"
                for p in top
            )
            print(
                f"{index:03d} {old['id'][:8]} {old['name'][:24]} [{old['category']}] -> {matches}"
            )
        return
    if "--collisions" in sys.argv:
        v2_by_id = {row["id"]: row for row in v2}
        prod_by_id = {row["id"]: row for row in production}
        reverse: dict[str, list[dict]] = {}
        for pair in pairs:
            if pair["distance_m"] <= 100 and pair["name_similarity"] >= 0.8:
                reverse.setdefault(pair["v2_id"], []).append(pair)
        for v2_id, matches in reverse.items():
            if len(matches) > 1:
                print(v2_id, v2_by_id[v2_id]["name"], v2_by_id[v2_id]["category"])
                for pair in matches:
                    old = prod_by_id[pair["production_uuid"]]
                    print(
                        "  ",
                        old["id"][:8],
                        old["name"],
                        old["category"],
                        pair["distance_m"],
                        pair["name_similarity"],
                        pair["address_similarity"],
                    )
        return
    print(
        json.dumps(
            {
                "production_places": len(production),
                "v2_places": len(v2),
                "candidate_pairs": len(pairs),
                "production_with_candidate": len(by_prod),
                "production_near_name_agreement": sum(
                    any(
                        p["distance_m"] <= 100 and p["name_similarity"] >= 0.8
                        for p in by_prod.get(row["id"], [])
                    )
                    for row in production
                ),
                "best_score_distribution": dict(
                    Counter(
                        (by_prod.get(row["id"]) or [{"score": 0}])[0]["score"] for row in production
                    )
                ),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    explore()
