"""Add read-only frozen-release and gate-decision views to the V2 workbook.

This reads the immutable snapshot. It changes only places_review.xlsx.
"""

from __future__ import annotations

import json
from pathlib import Path

from openpyxl import load_workbook
from openpyxl.styles import Font, PatternFill

OUT = Path(__file__).resolve().parents[2] / "data" / "places_v2" / "output"


def read(name: str) -> list[dict]:
    return [json.loads(line) for line in (OUT / name).read_text(encoding="utf-8").splitlines()]


def sheet(workbook, title: str, headers: list[str], records: list[list]) -> None:
    if title in workbook:
        del workbook[title]
    page = workbook.create_sheet(title, 0)
    page.append(headers)
    for record in records:
        page.append(record)
    page.freeze_panes = "C2"
    page.auto_filter.ref = page.dimensions
    for cell in page[1]:
        cell.font = Font(bold=True, color="FFFFFF")
        cell.fill = PatternFill("solid", fgColor="244268")
    page.column_dimensions["A"].width = 18
    page.column_dimensions["B"].width = 40
    page.column_dimensions["C"].width = 38
    for row in page.iter_rows(min_row=2):
        if row[0].value == "HOLD":
            for cell in row:
                cell.fill = PatternFill("solid", fgColor="FFF1CF")
        elif row[0].value == "CORRECT":
            for cell in row:
                cell.fill = PatternFill("solid", fgColor="DBF0FF")


def main() -> None:
    path = OUT / "places_review.xlsx"
    workbook = load_workbook(path)
    frozen = read("places_frozen_release.jsonl")
    decisions = read("places_gate_decisions.jsonl")
    aliases = read("places_release_aliases.jsonl")
    by_id = {place["id"]: place for place in frozen}
    if len(frozen) != 217 or len(decisions) != 225 or len(aliases) != 3:
        raise ValueError("Unexpected frozen V2 gate input counts")
    if "Release candidate" in workbook:
        candidate = workbook["Release candidate"]
        if candidate.max_row != 226:
            raise ValueError("Original release-candidate sheet changed")
        decision_by_source = {"places_v2:" + row["place_id"]: row for row in decisions}
        for row in candidate.iter_rows(min_row=2):
            source_id = row[1].value
            decision = decision_by_source[source_id]
            row[0].value = decision["decision"]
            row[16].value = decision["reason"]
            accepted = by_id.get(decision["place_id"])
            if accepted:
                row[4].value = accepted["district"]
                row[5].value = accepted["address"]
                row[6].value = accepted["latitude"]
                row[7].value = accepted["longitude"]
                row[13].value = ", ".join(accepted["field_conflicts"])
        candidate.auto_filter.ref = candidate.dimensions

    sheet(
        workbook,
        "Frozen release",
        [
            "include",
            "source_id",
            "name",
            "category",
            "district",
            "address",
            "latitude",
            "longitude",
            "phones",
            "opening_hours",
            "website",
            "instagram",
            "telegram",
            "confidence",
            "source_count",
            "field_conflicts",
            "qa_warnings",
            "gate_reason",
            "source_urls",
        ],
        [
            [
                p["include"],
                p["source_id"],
                p["name"],
                p["category"],
                p["district"],
                p["address"],
                p["latitude"],
                p["longitude"],
                ", ".join(p["phones"]),
                p["opening_hours"],
                p["website"],
                p["instagram"],
                p["telegram"],
                p["entity_confidence"],
                p["source_count"],
                ", ".join(p["field_conflicts"]),
                ", ".join(p["qa_warnings"]),
                p["gate_decision_reason"],
                "\n".join(p["source_urls"]),
            ]
            for p in frozen
        ],
    )
    sheet(
        workbook,
        "Gate decisions",
        [
            "decision",
            "place_id",
            "coordinate_review",
            "original_coordinates",
            "corrected_coordinates",
            "qa_warnings",
            "reason",
            "coordinate_evidence_urls",
        ],
        [
            [
                d["decision"],
                d["place_id"],
                d["coordinate_review"],
                json.dumps(d["original_coordinates"]),
                (
                    json.dumps(d.get("corrected_coordinates"))
                    if d.get("corrected_coordinates")
                    else None
                ),
                ", ".join(d["qa_warnings"]),
                d["reason"],
                "\n".join(d["coordinate_evidence_urls"]),
            ]
            for d in decisions
        ],
    )
    sheet(
        workbook,
        "Retired ID aliases",
        [
            "decision",
            "retired_source_id",
            "survivor_source_id",
            "case",
            "reason",
        ],
        [
            ["ALIAS", a["retired_source_id"], a["survivor_source_id"], a["case"], a["reason"]]
            for a in aliases
        ],
    )
    workbook.save(path)


if __name__ == "__main__":
    main()
