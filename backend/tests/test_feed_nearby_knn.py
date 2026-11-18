"""`nearby` feed via KNN (load audit LT-03, FIX-2) and the cats nearby box (LT-14).

The feed must keep its contract while switching to an index-ordered nearest-first scan:
* the set of items is exactly the set inside the radius (same spheroid ST_DWithin as before);
* the order is (distance, created_at DESC, type_rank DESC, id DESC), where distance is the sphere
  distance used for ordering and the cursor alike (it may differ from the old spheroid
  ordering only within the sphere/spheroid tolerance);
* paging to the end never duplicates or skips, including many items at the same spot.
"""

from __future__ import annotations

import math
from datetime import UTC, datetime, timedelta

from sqlalchemy import text
from test_feed_map import (  # noqa: F401 - fixtures are used by name
    _create_cat,
    _create_lost_pet,
    _create_post,
    _create_user_with_token,
    client,
    feed_runtime,
)

LAT, LON, RADIUS = 41.30, 69.25, 3000
TYPE_RANK = {"lost_pet": 2, "observation": 3}  # FEED_ITEM_TYPE_RANK


def _offset(lat_m: float, lon_m: float) -> tuple[float, float]:
    return LAT + lat_m / 110_574.0, LON + lon_m / (111_320.0 * math.cos(math.radians(LAT)))


def _seed(feed_runtime) -> tuple[object, set[str]]:
    """A dense neighbourhood: 25 posts and 4 lost pets on ONE spot, 12 posts on another, a few
    single points, items just outside the radius, a deleted and a private post."""
    manager = feed_runtime.db_session_manager
    author, _ = _create_user_with_token(
        manager, feed_runtime.token_service, email="knn-author@example.com"
    )
    cat = _create_cat(manager, creator_id=author.id)
    base = datetime.now(UTC) - timedelta(days=1)
    expected: set[str] = set()
    spot_a = _offset(400, 300)
    spot_b = _offset(-900, 1200)
    for index in range(25):  # identical location AND some identical timestamps
        expected.add(
            str(
                _create_post(
                    manager,
                    cat_id=cat.id,
                    user_id=author.id,
                    latitude=spot_a[0],
                    longitude=spot_a[1],
                    created_at=base - timedelta(minutes=index // 3),
                )
            )
        )
    for index in range(4):
        expected.add(
            str(
                _create_lost_pet(
                    manager,
                    user_id=author.id,
                    latitude=spot_a[0],
                    longitude=spot_a[1],
                    created_at=base - timedelta(minutes=index),
                )
            )
        )
    for index in range(12):
        expected.add(
            str(
                _create_post(
                    manager,
                    cat_id=cat.id,
                    user_id=author.id,
                    latitude=spot_b[0],
                    longitude=spot_b[1],
                    created_at=base - timedelta(hours=index),
                )
            )
        )
    for meters in (10, 250, 1700, 2600, 2990):
        point = _offset(meters * 0.6, meters * 0.8)
        expected.add(
            str(
                _create_post(
                    manager, cat_id=cat.id, user_id=author.id, latitude=point[0], longitude=point[1]
                )
            )
        )
    outside = _offset(0, RADIUS + 60)
    _create_post(
        manager, cat_id=cat.id, user_id=author.id, latitude=outside[0], longitude=outside[1]
    )
    _create_lost_pet(manager, user_id=author.id, latitude=outside[0], longitude=outside[1])
    _create_post(
        manager,
        cat_id=cat.id,
        user_id=author.id,
        latitude=spot_a[0],
        longitude=spot_a[1],
        deleted_at=datetime.now(UTC),
    )
    _create_post(
        manager,
        cat_id=cat.id,
        user_id=author.id,
        latitude=spot_a[0],
        longitude=spot_a[1],
        is_public=False,
    )
    return author, expected


def _page_through(client, *, limit: int, headers=None) -> list[dict]:
    items, cursor = [], None
    for _ in range(200):
        params = {
            "filter": "nearby",
            "lat": LAT,
            "lon": LON,
            "radius_meters": RADIUS,
            "limit": limit,
        }
        if cursor:
            params["cursor"] = cursor
        response = client.get("/api/v1/feed", params=params, headers=headers or {})
        assert response.status_code == 200, response.text
        data = response.json()["data"]
        items.extend(data["items"])
        cursor = data["next_cursor"]
        if not cursor:
            return items
    raise AssertionError("pagination did not terminate")


def _distances(feed_runtime, ids: list[str]) -> dict[str, tuple[float, float]]:
    """(sphere, spheroid) distance per id, computed by Postgres."""
    sql = text(
        """
        SELECT id::text,
               geography(location) <-> geography(ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)),
               ST_Distance(geography(location),
                           geography(ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)))
        FROM posts WHERE id::text = ANY(:ids)
        UNION ALL
        SELECT id::text,
               geography(last_seen_location)
                 <-> geography(ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)),
               ST_Distance(geography(last_seen_location),
                           geography(ST_SetSRID(ST_MakePoint(:lon, :lat), 4326)))
        FROM lost_pets WHERE id::text = ANY(:ids)
    """
    )
    with feed_runtime.db_session_manager.session_scope() as session:
        rows = session.execute(sql, {"lat": LAT, "lon": LON, "ids": ids}).all()
    return {row[0]: (float(row[1]), float(row[2])) for row in rows}


def test_nearby_pages_to_the_end_without_duplicates_or_skips(client, feed_runtime) -> None:
    _, expected = _seed(feed_runtime)
    for limit in (5, 7, 20):
        items = _page_through(client, limit=limit)
        ids = [item["id"] for item in items]
        assert len(ids) == len(set(ids)), f"duplicates at limit {limit}"
        assert set(ids) == expected, f"wrong set at limit {limit}"


def test_nearby_order_is_distance_then_newest_then_type_then_id(client, feed_runtime) -> None:
    _, expected = _seed(feed_runtime)
    items = _page_through(client, limit=6)
    distances = _distances(feed_runtime, [item["id"] for item in items])

    def key(item):
        kind = "lost_pet" if item.get("item_type") == "lost_pet" else "observation"
        return (
            round(distances[item["id"]][0], 6),
            -datetime.fromisoformat(item["created_at"].replace("Z", "+00:00")).timestamp(),
            -TYPE_RANK[kind],
            [-ord(c) for c in item["id"]],
        )

    assert [item["id"] for item in items] == [item["id"] for item in sorted(items, key=key)]


def test_nearby_order_matches_the_old_spheroid_order_within_tolerance(client, feed_runtime) -> None:
    _seed(feed_runtime)
    items = _page_through(client, limit=20)
    distances = _distances(feed_runtime, [item["id"] for item in items])
    spheroid = [distances[item["id"]][1] for item in items]
    for earlier, later in zip(spheroid, spheroid[1:], strict=False):
        # Sphere and spheroid distances differ by < 0.5% here; order may only swap within it.
        assert later >= earlier * 0.995 - 1.0


def test_nearby_includes_the_authors_own_private_post(client, feed_runtime) -> None:
    author, expected = _seed(feed_runtime)
    token = feed_runtime.token_service.issue_access_token(
        __import__("app.core.auth", fromlist=["AuthenticatedPrincipal"]).AuthenticatedPrincipal(
            user_id=author.id,
            role=__import__("app.core.auth", fromlist=["Role"]).Role.USER,
        )
    )
    guest_ids = {item["id"] for item in _page_through(client, limit=20)}
    author_ids = {
        item["id"]
        for item in _page_through(client, limit=20, headers={"Authorization": f"Bearer {token}"})
    }
    assert guest_ids == expected
    assert len(author_ids - guest_ids) == 1  # the private post, visible to its author only


def test_cats_nearby_finds_cats_east_and_west_inside_the_radius(client, feed_runtime) -> None:
    manager = feed_runtime.db_session_manager
    user, _ = _create_user_with_token(
        manager, feed_runtime.token_service, email="cats-east-west@example.com"
    )
    cats = {}
    for label, (north_m, east_m) in {
        "east 4.5 km": (0, 4500),
        "west 4.5 km": (0, -4500),
        "north 4.5 km": (4500, 0),
        "outside 5.1 km east": (0, 5100),
    }.items():
        lat, lon = _offset(north_m, east_m)
        cat = _create_cat(manager, creator_id=user.id, canonical_location=(lat, lon))
        _create_post(manager, cat_id=cat.id, user_id=user.id, latitude=lat, longitude=lon)
        cats[label] = str(cat.id)

    response = client.get(
        "/api/v1/cats",
        params={"filter": "nearby", "lat": LAT, "lon": LON, "radius_meters": 5000, "limit": 50},
    )
    assert response.status_code == 200
    ids = {item["id"] for item in response.json()["data"]["items"]}
    assert cats["east 4.5 km"] in ids
    assert cats["west 4.5 km"] in ids
    assert cats["north 4.5 km"] in ids
    assert cats["outside 5.1 km east"] not in ids
