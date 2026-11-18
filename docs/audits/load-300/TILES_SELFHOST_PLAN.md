# Self-hosted map tiles: plan (not built)

Status: plan for the owner's decision (2026-11-18), to be built before any promotion. The comparison
and the measured volumes are in `TILE_PROVIDERS.md`.

**Rule: we render every tile ourselves from OpenStreetMap data** (a Geofabrik extract). No tile is
ever bulk-downloaded from `tile.openstreetmap.org` or from any tile provider.

Labels: **Verified** = measured or calculated; **From code** = read in this repository;
**Estimate**; **Not checked**.

## 1. Area and zoom

- **Bounds:** the union of the three maps (From code):
  - main map (`tashkentMapBounds`): lat 41.18–41.43, lon 69.05–69.47, zoom 12.5–18;
  - observation and lost-pet pickers: lat 41.18–41.43, lon 69.05–**69.42**, zoom **11**–18.

  So the render area is lat 41.18–41.43, lon 69.05–69.47, plus a one-tile margin per zoom, because
  flutter_map loads one tile beyond the visible edge.
  - The three bounds are separate constants and the east edges differ. The switch will put them
    in one shared constant.
- **Zoom:** render **z10–z17**. z18 shows z17 scaled up (`maxNativeZoom: 17`, `maxZoom: 18`).
- **Tile count with the margin (Verified by calculation):**

| Zoom | Tiles | Cumulative |
|---|---|---|
| 10–12 | 94 | 94 |
| 13 | 120 | 214 |
| 14 | 396 | 610 |
| 15 | 1,353 | 1,963 |
| 16 | 4,977 | 6,940 |
| 17 | 19,344 | **26,284** |
| (18, if ever rendered) | 75,705 | 101,989 |

- **Size (Estimate):** 10–30 KB per 256-px PNG, so **~0.3–0.8 GB** for z10–17 per language.
  The spike (section 8) measures it.
- **Tile size:** 256 px, as today. `@2x` (512 px) tiles for sharper text on dense screens would
  be a later option, at 2–3× the storage, still within R2's free tier.

## 2. Toolchain (on the workstation, all in Docker)

1. **Data:** `uzbekistan-latest.osm.pbf` from Geofabrik, downloaded once per rebuild. Its size and
   the exact URL are **Not checked**.
2. **Clip:** `osmium extract --bbox 69.0,41.13,69.52,41.48` (the bounds plus ~5 km), giving a
   few MB.
3. **Vector tiles:** **Planetiler** with the OpenMapTiles profile, from the clip to `.mbtiles`.
   One Java process; minutes and under 2 GB of RAM for a city (Estimate).
4. **Render:** **tileserver-gl** (MapLibre Native) serves the `.mbtiles` with our style on
   `localhost`. A script requests every z10–17 tile in the area **from that local server** and
   writes `{z}/{x}/{y}.png`. Estimate: 20–100 tiles/s, so 5–20 min for 26k tiles.
5. **Style:** start from **OSM Bright (OpenMapTiles)**, the closest open style to today's OSM look.
   Positron is a quieter option if cat markers should stand out more. Fonts are Noto Sans, which
   covers Latin and Cyrillic. The style, fonts and sprites are versioned in the repo under
   `infrastructure/tiles/`.
   - Rejected: openstreetmap-carto with Mapnik (the exact OSM look). It needs a PostGIS import and
     renderd, and is heavier to run and script for one city.

**Label language (uz/ru):**
- The style's label expression picks the name. For example, Uzbek is
  `coalesce(name:uz, name:latin, name)` and Russian is `coalesce(name:ru, name)`.
- **One tile set per app language:** `uz` and `ru`, plus `en` if needed. That is 2–3× the tiles,
  still well under 2 GB.
- **Not checked:**
  - whether Planetiler's OpenMapTiles profile keeps `name:uz` (its language list, `--languages`);
  - how complete `name:uz` / `name:ru` are for Tashkent streets.

  The spike counts both (`osmium tags-filter` + `osmium fileinfo`). If `name:uz` is sparse, the uz
  set falls back to `name`, which is what users see on the OSM map today.

## 3. Hosting: R2 + Cloudflare

- **Bucket:** `mushukistan-tiles`, separate from media. It has a custom domain
  (`tiles.<our domain>`) on the Cloudflare zone the web app already uses; no `r2.dev` URL.
- **Layout:** `/<style>-<lang>/{z}/{x}/{y}.png`, e.g. `/bright-uz/15/21961/12216.png`.
  - The path is stable across monthly rebuilds, so old Android builds keep working.
  - A new style gets a new name.
- **Object metadata:** `Content-Type: image/png` and `Cache-Control: public, max-age=604800`
  (7 days in browsers and in the app's disk cache).
- **Cloudflare cache rule** for the tiles host: eligible for cache, edge TTL 30 days, browser TTL
  "respect origin". Tiles then rarely reach R2.
- **After a rebuild:** purge the tiles host from the cache. Whether "purge by hostname" is on our
  plan is **Not checked**; otherwise use "purge everything", which also clears the web app's
  cached assets (harmless).
- **CORS on the bucket:** `GET` from `https://mushukistan.uz` and `https://www.mushukistan.uz`.
  The web build fetches tiles from script (CanvasKit). Android needs none.
- **CSP:** add `https://tiles.<our domain>` to `connect-src` in `infrastructure/nginx/default.conf`
  (a web release). Remove `tile.openstreetmap.org` once the fallback is retired (section 4).
- **Upload:** `rclone sync --checksum` with an R2 API token scoped to this bucket only, kept on the
  workstation and never in the repo. Only changed tiles are written. A full first upload is ~26k
  Class A writes per language, inside the free 1M a month.
- **Cost:** **$0** at every volume in `TILE_PROVIDERS.md`: storage under 10 GB, reads under 10M a
  month even before the edge cache, egress free.

## 4. Client switch, with a fallback

- **One constant** for the tile URL: `MUSHUKISTAN_TILE_URL` via `--dart-define`. The default is
  the new host; the template carries the language (`.../bright-{lang}/{z}/{x}/{y}.png`, with
  `{lang}` from the app language).
- **The three `TileLayer`s** get it plus `maxNativeZoom: 17`, keeping `userAgentPackageName`.
- **Fallback during rollout:**
  - `fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'`, used only for a tile that
    fails on our host. flutter_map then skips its in-memory tile cache (From package source); the
    disk cache stays.
  - Remove the fallback in the next release, once the logs show no errors, to regain the memory
    cache and leave OSM's servers entirely.
- **Kill switch:**
  - web: a web release with the old URL (minutes, `release-web`);
  - Android: the fallback covers outages of our host until the next build.
- **Tests:** a widget test pins the URL template, `maxNativeZoom` and the attribution. A golden of
  one rendered tile is not needed.

## 5. Monthly rebuild (scripted)

`scripts/tiles/rebuild.sh` (to write) runs on the workstation. Each step stops on error:

1. Download the Geofabrik extract and verify its `.md5`.
2. Clip, run Planetiler, and render each language set into `build/tiles/<style>-<lang>/`.
3. **Checks:**
   - tile count per zoom equals the table in section 1;
   - no zero-byte PNG;
   - 5 sample tiles per language compared to last month's by size (a sudden drop means broken
     data).
4. `rclone sync --checksum --dry-run`, print the number of changed objects, then sync for real.
5. Purge the tiles host from the cache.
6. Fetch 3 tiles through the public URL (status 200, `image/png`).

- **When:** monthly (calendar reminder), or after a style change.
- **Cost:** about 30 min of workstation time, run when no load test is active (Estimate).
- **Record:** the date and the extract's timestamp go into `TILE_BUILDS.md` (gitignored), not
  committed.

## 6. Attribution

- **"© OpenStreetMap contributors"**, linked to openstreetmap.org/copyright, stays on every map.
  It is already enforced by `OsmAttribution` and its test (branch `fix/osm-attribution`). The data
  is still OSM data under ODbL. Since we render our own design, "Map data from OpenStreetMap" is
  also allowed.
- **Add "© OpenMapTiles"** (schema and style licence) to the same widget as a second line.
  The exact wording the style's licence asks for is **Not checked** (spike).
- We serve **raster** tiles only, a Produced Work. No ODbL share-alike obligation applies to the
  PNGs. The vector `.mbtiles` stays on the workstation; publishing it later would need it offered
  under ODbL.

## 7. If the map ever grows beyond Tashkent

All three bounds must change together (one constant after the switch). Tile counts for z10–17
with the margin (Verified by calculation):

| Area | Tiles z10–17 | Size (Estimate) | Approach |
|---|---|---|---|
| Tashkent city (today) | 26,284 | 0.3–0.8 GB per language | pre-rendered raster, this plan |
| Tashkent region (~lat 40.6–41.9, lon 68.6–70.4) | 557k | 5–15 GB per language | still pre-rendered: renders in hours; storage ~$0.1–0.3 a month above the free 10 GB |
| All Uzbekistan | 34.8M | hundreds of GB | **not pre-rendered** |

For all of Uzbekistan, the options are:
- (a) pre-render z10–14 country-wide (549k tiles) and z15–17 only around cities;
- (b) vector PMTiles on R2 (one file, a few hundred MB, Estimate), rendered on the device. This
  needs `vector_map_tiles` in the app, with device QA on low-end phones;
- (c) a small render server (tileserver-gl) behind the Cloudflare cache, rendering on demand. It
  needs a server and is a hosting change;
- (d) a paid provider (`TILE_PROVIDERS.md`).

Decide when the bounds change; (a) is the natural next step.

## 8. Effort (Estimate)

| Step | Who | Time |
|---|---|---|
| Spike: toolchain in Docker, render z14–15 for one language, measure tile size, count `name:uz`/`name:ru`, pick the style | agent | ½ day |
| `rebuild.sh` with its checks; first full render, uz + ru | agent | 1 day |
| R2 bucket, custom domain, cache rule, CORS, scoped API token | owner (dashboard) | 1–2 h |
| Client: URL constant, `maxNativeZoom`, fallback, OpenMapTiles line, CSP; tests | agent | ½ day |
| Device QA: Android low-end + web, both languages, pickers | owner + agent | ½ day |
| **Total** | | **~3 days**, then ~30 min a month |

The release is a web release (with the CSP change) plus an Android build. Nothing on the API
server changes.
