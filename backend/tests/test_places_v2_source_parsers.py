"""Fixture-based checks for public-page research parsers."""

from __future__ import annotations

import pytest

from scripts.probe_places_v2_yandex import extract


def test_yandex_search_map_center_is_not_a_business_pin() -> None:
    search_page = (
        '<link rel="canonical" href="https://yandex.com/maps/10335/tashkent/search/vet/">'
        '<div data-coordinates="69.3,41.3"></div>'
    )
    assert extract(search_page)["result_coordinates"] is None

    organization_page = (
        '<link rel="canonical" href="https://yandex.com/maps/org/example/123/">'
        '<div data-coordinates="69.3,41.3"></div>'
    )
    assert extract(organization_page)["result_coordinates"] == [41.3, 69.3]


def test_2gis_route_point_must_match_firm_id() -> None:
    pytest.importorskip("bs4")
    from scripts.harvest_2gis_chain_v2 import parse_firm

    page = (
        "<h1>Example Vet</h1>"
        '<a href="/tashkent/geo/123">Example Street, 2</a>'
        '<a href="/tashkent/directions/points/%7C69.2%2C41.3%3B999">Route</a>'
    )
    url = "https://2gis.uz/tashkent/firm/123"
    assert parse_firm(page, url, "Example Vet", "veterinary_clinic") is None
    own_page = page.replace("%3B999", "%3B123")
    assert parse_firm(own_page, url, "Example Vet", "veterinary_clinic")["coordinates"] == [
        41.3,
        69.2,
    ]
