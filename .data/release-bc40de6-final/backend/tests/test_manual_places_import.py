from __future__ import annotations

from scripts.import_manual_places import (
    parse_manual_place_row,
    parse_manual_places,
)


def _valid_row(**overrides: object) -> dict[str, object]:
    row: dict[str, object] = {
        "name": " PetZoo ",
        "type": "pet store",
        "latitude": 41.300642,
        "longitude": 69.264158,
        "address": " улица Сарабустан, 3А/2 ",
        "phone": "+998 77 095 07 70",
        "phone 2": None,
        "instagram": "https://www.instagram.com/petzoo.uz/",
        "telegram": "https://t.me/aquamarine_zoo",
        "opening_hours": "10:00-20:00",
        "days_off": "",
        "website": "petzoo.uz",
        "description": None,
    }
    row.update(overrides)
    return row


def test_parse_row_normalizes_text_and_maps_pet_store_type() -> None:
    place = parse_manual_place_row(2, _valid_row())

    assert place.name == "PetZoo"
    assert place.category.value == "pet_shop"
    assert [category.value for category in place.categories] == ["pet_shop"]
    assert place.address == "улица Сарабустан, 3А/2"
    assert place.days_off is None
    assert place.description is None
    assert place.source_id.startswith("manual_file:")


def test_parse_row_keeps_optional_fields_null_without_nan_strings() -> None:
    place = parse_manual_place_row(
        2,
        _valid_row(
            phone=float("nan"),
            instagram=" nan ",
            telegram=None,
            website="",
        ),
    )

    assert place.phone is None
    assert place.instagram is None
    assert place.telegram is None
    assert place.website is None


def test_parse_row_rejects_invalid_coordinates() -> None:
    rows = [(2, _valid_row(latitude=91)), (3, _valid_row(longitude="not-a-number"))]

    places, report = parse_manual_places(rows)

    assert places == []
    assert len(report.invalid_rows) == 2
    assert report.invalid_rows[0].message == "latitude is out of range"
    assert report.invalid_rows[1].message == "longitude must be a number"


def test_parse_rows_skips_duplicate_name_category_coordinates() -> None:
    rows = [
        (2, _valid_row(name="PetZoo")),
        (3, _valid_row(name="  PetZoo  ")),
    ]

    places, report = parse_manual_places(rows)

    assert len(places) == 1
    assert report.duplicates_skipped == 1


def test_parse_rows_accepts_multiple_supported_types() -> None:
    rows = [
        (2, _valid_row(type="pet store")),
        (3, _valid_row(name="Vet", type="veterinary clinic", latitude=41.31)),
        (4, _valid_row(name="Shelter", type="animal shelter", latitude=41.32)),
    ]

    places, report = parse_manual_places(rows)

    assert [place.category.value for place in places] == ["pet_shop", "veterinary", "shelter"]
    assert [[category.value for category in place.categories] for place in places] == [
        ["pet_shop"],
        ["veterinary"],
        ["shelter"],
    ]
    assert report.invalid_rows == []


def test_parse_rows_accepts_combined_place_type() -> None:
    places, report = parse_manual_places([(2, _valid_row(type="pet store,vet"))])

    assert len(places) == 1
    assert places[0].category.value == "veterinary"
    assert [category.value for category in places[0].categories] == ["veterinary", "pet_shop"]
    assert report.invalid_rows == []


def test_parse_rows_reports_unknown_type() -> None:
    places, report = parse_manual_places([(2, _valid_row(type="grooming salon"))])

    assert places == []
    assert len(report.invalid_rows) == 1
    assert report.invalid_rows[0].message == "unsupported type: grooming salon"
