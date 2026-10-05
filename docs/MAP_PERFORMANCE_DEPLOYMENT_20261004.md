# Map performance Flutter Web deployment — 2026-10-04

Historical release record. The later web release at
`/opt/mushukistan-releases/20261005-a2ff885-ui` superseded this web release.

The reviewed Map optimization was deployed as a **web-only** release. No place
dataset, backend container, database container, schema, migration, or Android
release was changed.

## Release identity and safety

- Base Git commit: `e5abd4f8eb3001056d2f8a8195115f590b48f389`.
- Reviewed overlay: 15 Map source, dependency, and test files listed with hashes
  in `data/map_performance/output/MAP_OPTIMIZATION_RELEASE_MANIFEST.json`.
  It was built from an isolated copy of the already deployed Places V2 source,
  excluding unrelated dirty working-tree files.
- Release activated on 2026-10-04:
  `/opt/mushukistan-releases/20261004-e5abd4f-map-perf-70949a28`.
- Rollback target retained at the time:
  `/opt/mushukistan-releases/20261003-e5abd4f-places-v2`.
- Production web `main.dart.js` SHA-256:
  `70949a2832319be08dcf883c3ae764511fcb581a9eb0738d04a9a6edc319f9b8`.
  The public HTTPS download, staged bundle, and active Nginx bind-mounted file
  matched this hash. The previous bundle remains at SHA-256
  `f65a531bd24b016acb6e23b5188319eaaa84b11e1cfd1af43b9e9d4bc2bb8995`.
- Reviewed release archive:
  `data/map_performance/output/map_web_release_70949a28.tar.gz`, SHA-256
  `c0354f3dd14b534f376fd7eef531fc56505cd10d00f2cdecbe1669317f0830ca`.
  Its 61 members are 15 reviewed overlay files, 45 complete web artifacts, and
  the release manifest; it contains no backend or place-data files.
- Alembic stayed at `20261002_0024` (head). The backend and database container
  IDs were identical before and after. Compose recreated only Nginx using
  `up -d --no-deps --no-build --force-recreate nginx` from the new release.
- A custom-format PostgreSQL backup was created **before** the Nginx switch:
  `/root/mushukistan-backups/mushukistan-20261004-113826-map-web.dump`,
  133,441 bytes, SHA-256
  `e4b9f8c4402576b74b1382e9fa4d401795fd376366beb2e5670cd98c7aac0f66`.
  `pg_restore --list` passed. No restore rehearsal was performed.

## Pre-release checks

The isolated release passed focused Flutter analysis with no issues and all 38
Map tests. The canonical production Web build passed, including production API,
Google OAuth ID, local CanvasKit, first-frame handling, and service-worker
retirement checks. Nineteen text files in the generated web artifact were
scanned; none contained localhost, emulator, or loopback API URLs. The
unchanged frozen Places V2 snapshot still had its expected SHA-256
`8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be`.

## Live verification

The public health endpoint returned `ok`. A read-only Flutter integration
probe exercised the actual `MapPlacesController` against the production API:
four category requests loaded **256 unique UUIDs**, with 183 primary pet shops,
42 primary veterinary clinics, 31 primary veterinary pharmacies, and zero
public shelters. Both a second open and a new controller using the stored
snapshot made zero additional place requests. No place was modified.

Browser screenshots showed live production tiles, place pins and clusters,
observation pins, Needs Help, and Lost Pet markers. The layer sheet exposed all
four place categories, including shelters with no current record. Selecting a
place opened its detail card. Cluster selection expanded/zoomed the group;
zoom, pan, synthetic Tashkent location, and light/dark rendering retained
markers. Feed-to-Map navigation also returned to the same working Map. The
browser recorded no Flutter Map runtime exception in the final probes.

| Browser action | Before: place / dynamic API requests | After: place / dynamic API requests |
| --- | ---: | ---: |
| First cold Map load | old code used one viewport place query / two dynamic | four category queries / two dynamic |
| Warm Map reload | 1 / 2 | 0 / 2 |
| Settled pan | 1 / 2 | 0 / 2 |
| Place-only filter | previous code path reloaded all three | 0 / 0 |
| Dynamic filter | previous code path reloaded all three | 0 / 2 |
| Cluster selection and zoom | previous code path reloaded all three | 0 / 2 each |
| Place marker selection | detail request separate | 0 place-list requests; one detail request |
| Feed-to-Map return within response-reuse window | not measured | 0 / 0 |

The browser's persisted cache held 256 items with 256 distinct IDs after the
cold load and across later page/browser reloads. A warm Map screenshot showed
these markers with zero place API requests. Stale-cache background refresh,
failure fallback, unchanged-response suppression, in-flight deduplication, and
the 350 ms viewport debounce were covered by the focused Flutter tests; the
production browser was not artificially aged by six hours. The selection test
recorded zero full Map builds and zero place-cluster recomputations when a
marker was selected. Release-mode browser builds do not expose those debug
counters.

### Browser measurement limitation

On this workstation, an unmodified headless Chrome/Edge session stalled while
downloading even the **previous** 4.7 MB `main.dart.js`; a separate public
HTTPS `curl` download completed in 20–47 seconds. To inspect actual Map
behavior, DevTools fulfilled only the JS request with a local copy whose
SHA-256 matched the production-served bundle. The page shell, CanvasKit,
tiles, API requests, and other assets still came from public production, and a
separate public HTTPS download confirmed the new JS hash. The browser used a
local certificate-error override because of this workstation's chain; public
`curl` validated TLS normally. This is a limit on natural cold-load timing
measurements, not evidence of a new application regression.

Some OpenStreetMap tile requests were canceled during movement; visible tiles
continued loading. One Lost Pet map request returned HTTP 429 after repeated
automated browser sessions from the same workstation; the Map remained visible,
and there was no repeated request loop. This rate-limit response is recorded as
a smoke-test limitation, not a Flutter exception. Frame build/raster times and
Android performance were not measured. Android was not published.

## Rollback

At the time of this deployment, the prior release remained intact. The
recorded rollback procedure used the existing Compose project from
`/opt/mushukistan-releases/20261003-e5abd4f-places-v2` with
`docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
--no-deps --no-build --force-recreate nginx`, then recheck the public bundle
hash and Map. No rollback was needed in this deployment.
