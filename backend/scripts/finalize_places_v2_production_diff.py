"""Build a read-only, deterministic Places V2 deployment review from saved evidence.

Never connects to a database. Never writes the frozen release or the production
export. Pair decisions below are deliberate, branch-specific review decisions.
"""

# Review reasons below preserve the exact historical wording used to produce
# the frozen deployment diff, including long source-evidence descriptions.
# ruff: noqa: E501

from __future__ import annotations

import hashlib
import json
import re
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "data" / "places_v2" / "output"
FROZEN = OUT / "places_frozen_release.jsonl"
PRODUCTION = OUT / "production_places_readonly_export.jsonl"
EXPECTED_FROZEN = "8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be"
EXPECTED_PRODUCTION = "27ae3058ad6ce114a117b8d8ab04876c86dd8beef4f24761dc1f57d2566c395c"

# Same place means the business/branch identity matches. In three cases a
# second legacy row also represents the same clinic: it cannot inherit the
# single V2 source ID and is therefore skipped pending a UUID decision.
DECISIONS = {
    1: (
        "SAME_PLACE",
        "Distinctive clinic name, Beshkurgon 1st quarter, 13 m; 2GIS clinic listing.",
    ),
    2: (
        "DIFFERENT_PLACES",
        "This V2 listing is the StarVet store; production row is the separately listed clinic.",
    ),
    3: (
        "UNRESOLVED",
        "Generic legacy store name and different street addresses; 16 m alone cannot identify storefront.",
    ),
    4: (
        "UNRESOLVED",
        "Versele-laga may be a product brand or old storefront; adjacent 54/4 versus 54/2 cannot prove separation.",
    ),
    5: (
        "UNRESOLVED",
        "Generic legacy name in the same building; storefront identity or rebrand is unproved.",
    ),
    6: (
        "DIFFERENT_PLACES",
        "Ekovet shop at block 40A versus Laykis clinic at block 43, 96 m apart.",
    ),
    7: (
        "DIFFERENT_PLACES",
        "PetZoo at 60/1 has its own domain; generic Pet Shop listing is at 60/4, 70 m away.",
    ),
    8: (
        "UNRESOLVED",
        "Zoo house at 31/1 versus Zoo aqua at 30a are only 6 m apart; old pin/address accuracy is uncertain.",
    ),
    9: (
        "UNRESOLVED",
        "Royal Canin may be a brand label or another store at near-identical pin; no contact agreement.",
    ),
    10: (
        "UNRESOLVED",
        "Both labels are generic pet shop names at house 62; a shared building does not prove one storefront.",
    ),
    11: (
        "SAME_PLACE",
        "MyVet name and Chigil 32A agree; production phone and domain agree with official V2 evidence.",
    ),
    12: ("SAME_PLACE", "Zoo Market name, Sayram 3A address, and coordinates agree exactly."),
    13: (
        "UNRESOLVED",
        "Zoo Shop and Zoomagazin are generic names at one building; no branch-specific contact confirmation.",
    ),
    14: (
        "SAME_PLACE",
        "Distinctive Zoo+Vet Market name and Sagbon 9th 8 address agree within 1 m.",
    ),
    15: (
        "DIFFERENT_PLACES",
        "Production Animal Planet already has a branch-specific V2 match at Shota Rustaveli 50A; this is Askia 44/7.",
    ),
    16: (
        "UNRESOLVED",
        "Generic Zoomagazin versus named Pritage zoo at same building; rebrand or separate storefront unknown.",
    ),
    17: (
        "SAME_PLACE",
        "Zoo pet shop name and Uchtepa G9A 17 address agree at virtually identical coordinates.",
    ),
    18: (
        "UNRESOLVED",
        "Similar Sh suffix but Qoraqamish 2/1 house 1 versus 1/3 house 41; address equivalence is unproved.",
    ),
    19: ("SAME_PLACE", "Distinctive Vet+ZooPlaneta name, Gagarin 65 address, and phone agree."),
    20: (
        "DIFFERENT_PLACES",
        "This is the separately listed Vet+ZooPlaneta branch at Chilanzar 1st quarter 62, not Gagarin 65.",
    ),
    21: (
        "DIFFERENT_PLACES",
        "Golden Cat shop and Impuls clinic have distinct names and categories at a commercial building.",
    ),
    22: (
        "DIFFERENT_PLACES",
        "Production Prestige Zoo already matches its own V2 firm at 54/4; Zoo City has a separate 2GIS firm ID.",
    ),
    23: (
        "DIFFERENT_PLACES",
        "Production Zoofood already matches its own V2 firm at Quyliq 5th 31a; Zoo xvostiki is at 30a.",
    ),
    24: (
        "SAME_PLACE",
        "Doctor & Animals distinctive name, Yalangach 27A address and coordinates agree; category decision is separate.",
    ),
    25: (
        "SAME_PLACE",
        "Vet Lider name, ToshGRES 26 address and pin agree exactly; use the veterinary production UUID.",
    ),
    26: (
        "UNRESOLVED",
        "Zoo and Zoomagazin are generic labels at house 21; no unique business evidence.",
    ),
    27: (
        "DIFFERENT_PLACES",
        "Anvar don is a separately named 2GIS firm; production Zoo Sale already matches V2 Zoo Sale.",
    ),
    28: (
        "DIFFERENT_PLACES",
        "Zoo City is a separately named 2GIS firm; production Zoo Sale already matches V2 Zoo Sale.",
    ),
    29: (
        "DIFFERENT_PLACES",
        "Zoo Amazon has a different name and 54/2 address; production Zoo Sale matches its own V2 firm.",
    ),
    30: (
        "SAME_PLACE",
        "Doctor Vet distinctive name and Barkamol/Aviasozlar branch area agree; use veterinary production UUID.",
    ),
    31: (
        "DIFFERENT_PLACES",
        "Production Vet+Zoo Planet already matches its own V2 firm at Mirabad 33; Zoo Doctor is a separate named firm.",
    ),
    32: ("SAME_PLACE", "Zoomag name and Yunusabad 15th 69/69a building pin agree exactly."),
    33: ("DIFFERENT_PLACES", "Zoo Market at Qoraqamish 14D versus Zoo Amazon at 54/2, 82 m apart."),
    34: ("DIFFERENT_PLACES", "Zoo Market at 14D versus Zoo Sale at 54/4, 104 m apart."),
    35: ("DIFFERENT_PLACES", "Zoo Market at 14D versus Zoo City at 54/4, 127 m apart."),
    36: (
        "UNRESOLVED",
        "Vetmedical name agrees but old Quyliq block 7 versus V2 block 8; possible adjacent branch or pin drift.",
    ),
    37: (
        "DIFFERENT_PLACES",
        "ZooMir on Sagbon 11th 54 versus ZO_OMagazin on Qoraqamish 2nd 54/1, 112 m.",
    ),
    38: (
        "DIFFERENT_PLACES",
        "ZooMir on Sagbon versus Zoo City on Qoraqamish; distinct names and addresses.",
    ),
    39: (
        "UNRESOLVED",
        "My pet and Happypeet have different names at the same pin; rebrand or separate shop unproved.",
    ),
    40: (
        "SAME_PLACE",
        "Zoocenter distinctive name and Sergeli block 1 location agree within 6 m; category differs.",
    ),
    41: (
        "SAME_PLACE",
        "Vet Alliance name/Navoi 6 address and phone agree; use veterinary production UUID.",
    ),
    42: (
        "UNRESOLVED",
        "Generic Zoomarket at Yunusabad 3/4 versus NEKO pharmacy; same building alone cannot resolve identity.",
    ),
    43: (
        "UNRESOLVED",
        "Petshop and Pet shop market are generic names at Aviasozlar 1st 20; storefront identity unproved.",
    ),
    44: (
        "SAME_PLACE",
        "StarVet store names, Beshkurgon 1st address and pin agree; use pet-shop production UUID.",
    ),
    45: (
        "DIFFERENT_PLACES",
        "This V2 entity is the separately listed StarVet clinic; production row is the store.",
    ),
    46: (
        "SAME_PLACE",
        "Legacy Doctor Vet shop row has the same name and exact clinic pin; second legacy UUID needs review.",
    ),
    47: (
        "SAME_PLACE",
        "Legacy Vet Alliance shop row has the same name/address and clinic location; second UUID needs review.",
    ),
    48: (
        "DIFFERENT_PLACES",
        "V2 Animal planet at Gulsanam 7B is already matched to its own production branch; Vernie Druzya is at 3.",
    ),
    49: (
        "UNRESOLVED",
        "Zooline and Kw Zoo Product share house 84 but names and phone differ; possible rebrand or separate store.",
    ),
    50: (
        "UNRESOLVED",
        "Zoo pet shop is a generic name; old street-only address and near-exact pin do not prove same storefront.",
    ),
    51: (
        "UNRESOLVED",
        "Generic Zoomarket shop and Felix zoo pharmacy are only 7 m apart with different address labels; branch identity is uncertain.",
    ),
    52: (
        "UNRESOLVED",
        "Generic old pet store at Yunusabad 5th 1A and ZooMarket at Maykurgan 3/1 are 19 m apart; address equivalence unknown.",
    ),
    53: (
        "DIFFERENT_PLACES",
        "Zoomag at Sayram 39 versus Zoo Market at Sayram 3A, 85 m apart; different premises.",
    ),
    54: (
        "SAME_PLACE",
        "ZooPolis distinctive name and near-identical pin; Qovunchi 11A/31st block 11/1 are location aliases.",
    ),
    55: (
        "SAME_PLACE",
        "Doctor vet house distinctive name, Chilanzar 5th block 46 and pin agree exactly.",
    ),
    56: (
        "SAME_PLACE",
        "Buyuk Turon 73 address and production phone agree with Kupi Slona V2 evidence.",
    ),
    57: (
        "SAME_PLACE",
        "Sevimlilar/Любимцы are Uzbek/Russian translations; Karasu 11 location agrees within 4 m.",
    ),
    58: (
        "SAME_PLACE",
        "LaykisVet/Laykis name, Traktorsozlar block 43 and location agree; legacy domain supports identity.",
    ),
    59: (
        "SAME_PLACE",
        "Exact Zoomagazin name, Buyuk Ipak Yuli 77 address and identical pin match the specific Yandex firm listing.",
    ),
    60: (
        "UNRESOLVED",
        "Koshkin dom at Izzat 20 and Pet shop market at Aviasozlar 2nd block 32 are only 10 m apart; old address may be inaccurate.",
    ),
    61: (
        "SAME_PLACE",
        "Vet+ZooPlaneta name, Toytepa 1 address and phone agree; 57 m building/pin offset.",
    ),
    62: (
        "SAME_PLACE",
        "Charley name and Yunusabad 19th 45 agree; phone and official website confirm branch.",
    ),
    63: (
        "DIFFERENT_PLACES",
        "Production Vet+ZooPlaneta already matches its own V2 Sergeli II firm; Aqua Mir has a separate listing.",
    ),
    64: (
        "UNRESOLVED",
        "Zoo Magazin/Зоомагазин are generic labels at Kurgantepa 25; 25 m pin cannot prove storefront.",
    ),
    65: (
        "SAME_PLACE",
        "Distinctive Zoo.M name and Yunusabad 4th block 1 address agree despite 87 m pin offset.",
    ),
    66: (
        "SAME_PLACE",
        "Legacy Vet Lider shop row has the same name and exact clinic pin; second legacy UUID needs review.",
    ),
    67: (
        "DIFFERENT_PLACES",
        "Production Zoo Terrarium already matches its own V2 firm at Qoraqamish 10A; ZO_OMagazin is separately listed.",
    ),
    68: (
        "UNRESOLVED",
        "Generic Zoo Shop/Zooshop names at Farogat 3rd 2 versus 2nd 40a; pin proximity is insufficient.",
    ),
    69: (
        "SAME_PLACE",
        "Tri Kota/Three Cats are translations; Quyliq 4th block 41 and phone agree; category differs.",
    ),
}

CATEGORY_MAP = {
    "pet_store": "pet_shop",
    "veterinary_clinic": "veterinary",
    "veterinary_pharmacy": "veterinary_pharmacy",
    "animal_shelter": "shelter",
}
FIELDS = (
    "name",
    "category",
    "latitude",
    "longitude",
    "address",
    "phone",
    "phone_2",
    "website",
    "opening_hours",
    "source_id",
)


def read_jsonl(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines()]


def write_jsonl(path: Path, rows: list[dict]) -> None:
    path.write_text(
        "".join(json.dumps(row, ensure_ascii=False, sort_keys=True) + "\n" for row in rows),
        encoding="utf-8",
    )


def normalized_phone(value: str | None) -> str:
    return re.sub(r"\D", "", value or "")


def field_value(v2: dict, field: str):
    if field == "category":
        return CATEGORY_MAP[v2["category"]]
    if field == "phone":
        return (v2.get("phones") or [None])[0]
    if field == "phone_2":
        return v2.get("phones", [])[1] if len(v2.get("phones", [])) > 1 else None
    return v2.get(field)


def equivalent(field: str, old, new) -> bool:
    if field in ("phone", "phone_2"):
        return normalized_phone(old) == normalized_phone(new)
    if field == "website" and old and new:
        return old.lower().removeprefix("https://").removeprefix("http://").rstrip(
            "/"
        ) == new.lower().removeprefix("https://").removeprefix("http://").rstrip("/")
    return old == new


def operation(old: dict, v2: dict, field: str, sources: dict[str, list[dict]]) -> dict:
    before, candidate = old.get(field), field_value(v2, field)
    evidence_field = (
        "phones"
        if field in ("phone", "phone_2")
        else "coordinates" if field in ("latitude", "longitude") else field
    )
    evidence = [
        s
        for s in sources.get(evidence_field, [])
        if s.get("status") == "verified" and s.get("confidence") in ("high", "medium")
    ]
    base = {
        "field": field,
        "production_value": before,
        "v2_value": candidate,
        "v2_confidence": v2.get("field_confidence", {}).get(evidence_field),
        "evidence_urls": sorted({s["source_url"] for s in evidence if s.get("source_url")}),
    }
    if field == "source_id":
        return dict(
            base,
            operation="UPDATE_FROM_V2",
            result_value=candidate,
            reason="Attach reviewed stable V2 source ID; preserve production UUID and archive old source ID.",
        )
    if candidate is None:
        if before is None:
            return dict(
                base, operation="NO_CHANGE", result_value=None, reason="Both values absent."
            )
        return dict(
            base,
            operation="PRESERVE_PRODUCTION",
            result_value=before,
            reason="V2 NULL means no verified replacement; existing production value is retained.",
        )
    if equivalent(field, before, candidate):
        return dict(
            base,
            operation="NO_CHANGE",
            result_value=before,
            reason="Values agree, allowing phone/URL formatting differences.",
        )
    if (
        field == "category"
        and before != candidate
        and before == "pet_shop"
        and candidate == "veterinary"
    ):
        return dict(
            base,
            operation="REVIEW",
            result_value=before,
            reason="Identity matches, but shop-to-clinic primary category change needs explicit product review.",
        )
    if field == "category" and before == "pet_shop" and candidate == "veterinary_pharmacy":
        # Category-specific decision: the detailed firm/independent map listing
        # verifies pharmacy. Preserve the legacy shop link as secondary.
        return dict(
            base,
            operation="UPDATE_FROM_V2",
            result_value=candidate,
            reason="Branch-specific V2 source verifies veterinary pharmacy; retain old pet_shop category link as secondary.",
        )
    if not evidence and field not in ("latitude", "longitude"):
        return dict(
            base,
            operation="REVIEW",
            result_value=before,
            reason="V2 field differs but has no verified field-level source.",
        )
    if not evidence and field in ("latitude", "longitude"):
        return dict(
            base,
            operation="REVIEW",
            result_value=before,
            reason="Coordinate change lacks verified field-level source.",
        )
    return dict(
        base,
        operation="UPDATE_FROM_V2",
        result_value=candidate,
        reason="Verified branch-specific V2 field evidence supports replacement.",
    )


def build() -> dict:
    if hashlib.sha256(FROZEN.read_bytes()).hexdigest() != EXPECTED_FROZEN:
        raise ValueError("Frozen V2 SHA-256 mismatch; stopped without output")
    if hashlib.sha256(PRODUCTION.read_bytes()).hexdigest() != EXPECTED_PRODUCTION:
        raise ValueError("Production export SHA-256 mismatch; comparison must be reviewed anew")
    v2 = read_jsonl(FROZEN)
    production = read_jsonl(PRODUCTION)
    pairs = read_jsonl(OUT / "production_ambiguous_review.jsonl")
    original = read_jsonl(OUT / "production_comparison.jsonl")
    sources = read_jsonl(OUT / "places_sources.jsonl")
    if (
        len(v2) != 217
        or len(production) != 149
        or len(pairs) != 69
        or set(DECISIONS) != set(range(1, 70))
    ):
        raise ValueError("Unexpected baseline dimensions or incomplete pair review")
    v2_by_id = {x["id"]: x for x in v2}
    prod_by_id = {x["id"]: x for x in production}
    sources_by_v2: dict[str, dict[str, list[dict]]] = defaultdict(lambda: defaultdict(list))
    for source in sources:
        sources_by_v2[source["record_id"]][source["field"]].append(source)

    pair_decisions = []
    same_by_v2: dict[str, list[dict]] = defaultdict(list)
    same_by_prod: dict[str, list[dict]] = defaultdict(list)
    for index, pair in enumerate(pairs, 1):
        decision, reason = DECISIONS[index]
        row = dict(
            pair,
            pair_number=index,
            decision=decision,
            decision_reason=reason,
            v2_evidence_urls=v2_by_id[pair["v2_id"]].get("source_urls", []),
        )
        pair_decisions.append(row)
        if decision == "SAME_PLACE":
            same_by_v2[pair["v2_id"]].append(row)
            same_by_prod[pair["production_uuid"]].append(row)

    old_matches = {
        x["production_uuid"]: x["v2_id"] for x in original if x["action"] == "UPDATE_EXISTING"
    }
    assert len(old_matches) == 66
    matches = dict(old_matches)
    duplicate_legacy_uuids = set()
    for v2_id, rows in same_by_v2.items():
        if len(rows) > 1:
            veterinary = [
                r for r in rows if prod_by_id[r["production_uuid"]]["category"] == "veterinary"
            ]
            if len(veterinary) != 1:
                raise ValueError(f"Cannot select unique existing UUID for {v2_id}")
            survivor = veterinary[0]["production_uuid"]
            duplicate_legacy_uuids.update(
                r["production_uuid"] for r in rows if r["production_uuid"] != survivor
            )
            for r in rows:
                r["actionable_mapping"] = r["production_uuid"] == survivor
                r["uuid_decision"] = (
                    "PRESERVE_SURVIVOR" if r["actionable_mapping"] else "SECOND_LEGACY_UUID_REVIEW"
                )
        else:
            rows[0]["actionable_mapping"] = True
            rows[0]["uuid_decision"] = "PRESERVE_PRODUCTION_UUID"
        for r in rows:
            if r["actionable_mapping"]:
                prod_id = r["production_uuid"]
                if prod_id in matches and matches[prod_id] != v2_id:
                    raise ValueError("Conflicting old and new mappings")
                matches[prod_id] = v2_id
    if len(matches) != len(set(matches.values())):
        raise ValueError("Two production UUIDs would receive one V2 source ID")

    unresolved_prod = {
        r["production_uuid"] for r in pair_decisions if r["decision"] == "UNRESOLVED"
    }
    unresolved_v2 = {r["v2_id"] for r in pair_decisions if r["decision"] == "UNRESOLVED"}
    unresolved_prod.update(duplicate_legacy_uuids)
    matched_v2 = set(matches.values())
    if unresolved_prod & matches.keys() or unresolved_v2 & matched_v2:
        raise ValueError("A mapped entity still has an unresolved pairing")

    field_decisions = []
    diff = []
    for old in production:
        prod_id = old["id"]
        base = {
            "entity": "production",
            "production_uuid": prod_id,
            "production_name": old["name"],
            "production_category": old["category"],
            "production_address": old["address"],
            "production_latitude": old["latitude"],
            "production_longitude": old["longitude"],
        }
        if prod_id in matches:
            new = v2_by_id[matches[prod_id]]
            ops = [
                dict(
                    operation(old, new, field, sources_by_v2[new["id"]]),
                    production_uuid=prod_id,
                    v2_id=new["id"],
                )
                for field in FIELDS
            ]
            field_decisions.extend(ops)
            old_links = set(old.get("categories", []))
            category_review = any(
                op["field"] == "category" and op["operation"] == "REVIEW" for op in ops
            )
            verified_secondary = {CATEGORY_MAP[c] for c in new.get("secondary_categories", [])}
            links_after = sorted(
                old_links
                if category_review
                else old_links | verified_secondary | {CATEGORY_MAP[new["category"]]}
            )
            diff.append(
                dict(
                    base,
                    action="UPDATE_EXISTING",
                    v2_id=new["id"],
                    v2_source_id=new["source_id"],
                    preserve_production_uuid=True,
                    legacy_source_id=old["source_id"],
                    field_operations=ops,
                    category_links_before=sorted(old_links),
                    category_links_after=links_after,
                    category_link_rule=(
                        "PRESERVE_UNTIL_CATEGORY_REVIEW"
                        if category_review
                        else "ADD_VERIFIED_AND_PRESERVE_EXISTING"
                    ),
                    human_approval_required=True,
                )
            )
        elif prod_id in unresolved_prod:
            relevant = [
                r
                for r in pair_decisions
                if r["production_uuid"] == prod_id
                and (r["decision"] == "UNRESOLVED" or prod_id in duplicate_legacy_uuids)
            ]
            diff.append(
                dict(
                    base,
                    action="SKIP_UNRESOLVED",
                    candidate_v2_ids=sorted({r["v2_id"] for r in relevant}),
                    reason="Ambiguous physical identity or duplicate legacy UUID; row remains unchanged.",
                    human_decision_required=True,
                )
            )
        else:
            was_prod_only = any(
                x.get("production_uuid") == prod_id
                and x.get("production_classification") == "PRODUCTION_ONLY"
                for x in original
            )
            diff.append(
                dict(
                    base,
                    action="KEEP_UNCHANGED",
                    reason=(
                        "Original production-only row; no research or mutation."
                        if was_prod_only
                        else "Reviewed candidate pairs are different physical places; keep legacy row."
                    ),
                )
            )

    for new in v2:
        if new["id"] in matched_v2:
            continue
        base = {
            "entity": "v2",
            "v2_id": new["id"],
            "v2_source_id": new["source_id"],
            "v2_name": new["name"],
            "v2_category": new["category"],
            "v2_address": new["address"],
            "v2_latitude": new["latitude"],
            "v2_longitude": new["longitude"],
        }
        if new["id"] in unresolved_v2:
            diff.append(
                dict(
                    base,
                    action="SKIP_UNRESOLVED",
                    candidate_production_uuids=sorted(
                        {
                            r["production_uuid"]
                            for r in pair_decisions
                            if r["v2_id"] == new["id"] and r["decision"] == "UNRESOLVED"
                        }
                    ),
                    reason="Unresolved production match; do not insert a possible duplicate.",
                    human_decision_required=True,
                )
            )
        else:
            diff.append(
                dict(
                    base,
                    action="INSERT_NEW",
                    new_uuid=new["import_uuid"],
                    insert_values={field: field_value(new, field) for field in FIELDS},
                    category_links=sorted(
                        {CATEGORY_MAP[new["category"]]}
                        | {CATEGORY_MAP[c] for c in new.get("secondary_categories", [])}
                    ),
                    reason="No unresolved production match; use frozen V2 values and deterministic UUID.",
                    human_approval_required=True,
                )
            )

    counts = Counter(row["action"] for row in diff)
    pair_counts = Counter(row["decision"] for row in pair_decisions)
    field_counts = Counter(row["operation"] for row in field_decisions)
    null_preserves = [row for row in field_decisions if row["operation"] == "PRESERVE_PRODUCTION"]
    assert len(diff) == len(production) + len(v2) - len(matches)
    assert len([r for r in diff if r["entity"] == "production"]) == len(production)
    assert len([r for r in diff if r["entity"] == "v2"]) + len(matches) == len(v2)
    assert not any(r["action"] == "DELETE" for r in diff)
    assert not any(
        r["operation"] == "UPDATE_FROM_V2" and r["result_value"] is None for r in field_decisions
    )
    assert not any(r["operation"] == "CLEAR_WITH_EVIDENCE" for r in field_decisions)
    assert (
        len({r["v2_source_id"] for r in diff if r["action"] in ("UPDATE_EXISTING", "INSERT_NEW")})
        == counts["UPDATE_EXISTING"] + counts["INSERT_NEW"]
    )
    existing_uuids = {r["id"] for r in production}
    inserted_uuids = [r["new_uuid"] for r in diff if r["action"] == "INSERT_NEW"]
    assert len(set(inserted_uuids)) == len(inserted_uuids)
    assert not existing_uuids.intersection(inserted_uuids)
    existing_source_ids = {r["source_id"] for r in production}
    assert not existing_source_ids.intersection(
        r["v2_source_id"] for r in diff if r["action"] in ("UPDATE_EXISTING", "INSERT_NEW")
    )
    assert all(
        r["action"] == "KEEP_UNCHANGED"
        for r in diff
        if r.get("production_uuid")
        in {x["production_uuid"] for x in original if x["action"] == "KEEP_UNCHANGED"}
    )
    assert all(
        set(r["category_links_before"]) <= set(r["category_links_after"])
        for r in diff
        if r["action"] == "UPDATE_EXISTING"
    )

    report = {
        "frozen_sha256": EXPECTED_FROZEN,
        "production_export_sha256": EXPECTED_PRODUCTION,
        "production_count": len(production),
        "v2_count": len(v2),
        "confident_mappings_before_review": len(old_matches),
        "additional_actionable_same_place_mappings": len(matches) - len(old_matches),
        "same_place_pair_decisions": pair_counts["SAME_PLACE"],
        "same_place_pairs_with_secondary_legacy_uuid_review": len(duplicate_legacy_uuids),
        "different_places_pair_decisions": pair_counts["DIFFERENT_PLACES"],
        "unresolved_pair_decisions": pair_counts["UNRESOLVED"],
        "duplicate_legacy_uuids_requiring_review": sorted(duplicate_legacy_uuids),
        "action_counts": dict(sorted(counts.items())),
        "production_action_counts": dict(
            sorted(Counter(r["action"] for r in diff if r["entity"] == "production").items())
        ),
        "v2_action_counts": dict(
            sorted(Counter(r["action"] for r in diff if r["entity"] == "v2").items())
        ),
        "field_operation_counts": dict(sorted(field_counts.items())),
        "v2_null_fields_preserving_production": len(null_preserves),
        "matched_rows_with_v2_null_preserves": len({r["production_uuid"] for r in null_preserves}),
        "fields_cleared_with_evidence": 0,
        "pharmacy_primary_category_updates": [
            r["production_uuid"]
            for r in field_decisions
            if r["field"] == "category"
            and r["result_value"] == "veterinary_pharmacy"
            and r["operation"] == "UPDATE_FROM_V2"
        ],
        "secondary_category_links_removed": 0,
        "no_production_changes": True,
    }
    write_jsonl(OUT / "production_pair_decisions_final.jsonl", pair_decisions)
    write_jsonl(OUT / "production_field_decisions_final.jsonl", field_decisions)
    final_diff = OUT / "production_deployment_review_final.jsonl"
    write_jsonl(final_diff, diff)
    report["final_diff_sha256"] = hashlib.sha256(final_diff.read_bytes()).hexdigest()
    (OUT / "production_deployment_review_report_final.json").write_text(
        json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8"
    )
    return report


if __name__ == "__main__":
    print(json.dumps(build(), ensure_ascii=False, indent=2))
