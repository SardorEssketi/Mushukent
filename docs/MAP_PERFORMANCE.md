# Map performance audit and local optimization

Status: Flutter Web optimization deployed on 2026-10-04; see
`docs/MAP_PERFORMANCE_DEPLOYMENT_20261004.md` for the release and live checks.
The audit and implementation did not change place data or production database
contents. The measurements below describe the local pre-deployment work.

## Evidence before the change

The Map originally requested three independent datasets together after a
350 ms movement debounce: recent cats (ordinary observations and needs-help),
places, and lost-pet map markers. Places were queried by viewport with a
200-row API limit and no local cache. Any filter change altered the combined
request key, so changing only a place filter requested all three datasets
again. The three futures were awaited together, delaying all new markers until
the slowest response completed.

A read-only public API sample on 2026-10-04 measured the full-city place query
at 1.409 s / 38,012 bytes and a central viewport place query at 1.330 s /
38,433 bytes. Both returned the 200-row cap. The same central viewport's cat
and lost-pet requests took 0.850 s / 528 bytes and 0.786 s / 282 bytes. A
separate full-city per-category sample took 0.975 s for pet shops, 0.771 s for
veterinary, and 1.032 s for veterinary pharmacies. These are one-pass network
samples, not controlled latency benchmarks.

Four read-only category queries returned 193 shop, 42 veterinary, 57 pharmacy,
and zero shelter results; deduplication by place UUID yielded 256 physical
places. Thus, the original single 200-row query could omit visible pins when a
large viewport contained more than 200 matching places.

The prior `_loadViewport` called `setState` for loading, results, and completion:
three whole Map screen builds per successful request. Marker specs, marker
widgets, and clusters were recreated on each build. Selecting one marker also
called `setState` on the entire screen. In the installed `flutter_map` 8.3.1,
`MarkerLayer.didUpdateWidget` discards its cached point projections whenever
the parent supplies a new MarkerLayer widget. That made these rebuilds more
costly than changing a small loading indicator alone.

Using the 256 public place coordinates and the map's world-grid clustering
rules, full-city grouping produced 154 marker widgets at zoom 13.6 (54 clusters,
100 singles), 212 at zoom 15 (25 clusters, 187 singles), and 256 individual
pins at zoom 16. The map culls offscreen markers afterward. Clustering reduces
low-zoom load, but does not eliminate marker work. Individual shadow/raster
cost and frame build/raster times were not isolated on a physical device, so
they are not claimed as proven primary causes.

## Local changes

- Place map pins have a versioned `shared_preferences` snapshot scoped to the
  API origin. It contains only compact public marker fields. The memory copy
  survives Map navigation; persistent storage survives app restart. Six hours
  after the last successful fetch, opening Map shows cached pins and starts a
  background refresh. Manual refresh always checks the API. A failed refresh
  leaves stale pins visible and the next open can retry. An unchanged response
  does not notify the Map.
- A cold place fetch requests all four categories concurrently. If any category
  reaches the 200-row API cap, the client splits that bbox and deduplicates by
  UUID. It fails safely instead of accepting a still-capped final region.
- Cats and lost pets remain viewport based. They retain the 350 ms movement
  debounce, use separate request keys, coalesce identical in-flight requests,
  and reuse identical completed responses for only 15 seconds. Place-only
  filter changes send no map data request. Dynamic layer changes and post
  mutations force fresh dynamic requests.
- Place, dynamic, and fixed pins use separate marker layers. The place layer
  retains `flutter_map`'s projected-point cache during pans and unrelated
  state updates. Cluster grouping changes when zoom or relevant data changes.
  Each marker listens only to its own selection state, so selecting a marker
  changes at most the old and new marker visuals. The OpenStreetMap TileLayer
  widget is retained across parent builds. Marker colors, shadows, icons,
  themes, and category semantics remain unchanged.

## Before and after checks

With all layers visible and a changed bbox, the source paths imply these
request counts. A marker detail request is separate and remains one request.

| Representative action | Previous requests | Local implementation |
| --- | ---: | ---: |
| Cold first Map open | 3 | 6 (four parallel place categories, two dynamic) |
| Warm Map open, same app or fresh local cache | 3 | 2 dynamic, 0 place |
| Settled pan to changed bbox | 3 | 2 dynamic, 0 place |
| Place-only layer/filter change | 3 | 0 |
| Post mutation with same viewport | 3 | 2 dynamic, 0 place |

Focused widget tests at 256 synthetic places confirmed that a cached pin can
render before the viewport debounce dispatches any request. A dynamic-state
update caused one Map screen build but zero place-cluster recomputations and
retained the identical TileLayer widget. A forced dynamic refresh caused two
dynamic requests, zero place requests, one Map screen build, and zero
place-cluster recomputations. Marker selection caused zero Map screen builds
and zero place-cluster recomputations. A place-only filter change caused zero
API calls and zero dynamic-cluster recomputations. A direct layer test found
zero cluster recomputations on a same-zoom pan and one on a zoom change. These
are deterministic debug/widget-test counts; they are not frame-time
measurements.

A widget drag test also confirmed that no request was sent during the first
100 ms of a pan; after the 350 ms debounce, exactly two dynamic requests were
sent and no place request was sent.

The place cache tests cover hit, miss, stale display before refresh, failed
refresh with cached pins, unchanged responses, and API cap splitting. Dynamic
request tests cover debounce, stale-response guards, short-lived reuse,
in-flight deduplication, expiry, and forced refresh. The full Map test group
passed (38 tests), focused Flutter analysis reported no issues, and the local
release web build succeeded.

An Android debug build was attempted but could not finish on this workstation:
the Gradle 9.1 JVM, configured with an 8 GB maximum heap, exited after a
native-memory allocation failure. Windows reported roughly 1.65 GB free RAM
afterward. The crash log is
`frontend/build/map_performance_logs/android_gradle_hs_err_pid29780.log`. This is a
host-resource validation blocker, not a reported Dart or Android compile error.

## Remaining validation

Build/raster frame times and the actual time to painted pins on Android/iOS
hardware were not measured. A device profile session should measure the
map during first open, warm open, pan,
pinch zoom, filter changes, and marker selection. Tile-server latency and GPU
raster cost can vary by device and network. The Android optimization still needs
staging/product review. An Android build on a machine with sufficient free RAM
and a device profile pass remain before a mobile production release. The web
release and its checks are documented separately.
