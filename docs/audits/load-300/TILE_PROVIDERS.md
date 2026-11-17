# Map tile providers: comparison for the owner's choice

Status: comparison only. Nothing is integrated (owner decision, 2026-11-16; memo 7.3 in
`FIXES_RESULTS.md`). Prices and limits are from the providers' public pricing pages, read on
2026-11-16 and 2026-11-17. They change, so re-check them on the day of the decision. Extended
2026-11-17 with measured tiles per session, projected volumes, cost at those volumes, a
self-hosted option and a recommendation.

**Today (From code):** three places load raster tiles straight from `tile.openstreetmap.org`:
`map_screen.dart:86`, `add_observation_location_screen.dart:223` and
`lost_pet_create_screen.dart:483`. That server is donated, has no SLA, and its usage policy
does not cover a growing app.

All three candidates draw the map from OpenStreetMap data, so coverage of Tashkent is the same OSM
coverage the app shows today. Label language (Uzbek / Russian / English) differs per style and was
**Not checked** for any of them.

| | **Geoapify** | **Mapbox** | **MapTiler** |
|---|---|---|---|
| Free tier | 3,000 credits/day; 1 tile = 0.25 credit → ~12,000 tiles/day (~360k/month) | 200,000 raster tiles/month (Static Tiles API); vector tiles 200,000/month | 100,000 requests and 5,000 map sessions/month |
| Commercial use on free | **Yes**, stated in their FAQ, including production | Yes (the free tier is the start of usage pricing) | **No**: "testing, PoC, prototyping, personal, or non-commercial use" |
| When the free tier runs out | no overage on Free; exact behaviour at the limit **Not checked** | billed per use: raster $0.50 per 1,000 tiles from 200,001 (whether a card is required: **Not checked**) | the service pauses until the next month |
| Cheapest paid | $59/month, 10,000 credits/day | pay as you go (above) | Flex $30/month: 500k requests, 25k sessions; overage $0.15 per 1,000 requests |
| Attribution | "Powered by Geoapify" link plus OSM data attribution | Mapbox logo and text attribution (exact wording **Not checked**) | MapTiler logo on Free (not on Flex); OSM attribution |
| flutter_map URL (raster; form from provider docs, not tried against the live API) | `https://maps.geoapify.com/v1/tile/<style>/{z}/{x}/{y}.png?apiKey=…` | `https://api.mapbox.com/styles/v1/<user>/<style>/tiles/256/{z}/{x}/{y}@2x?access_token=…` | `https://api.maptiler.com/maps/<style>/{z}/{x}/{y}.png?key=…` |

**Integration effort (same for all three; From code):**
- Change `urlTemplate` in the three places, and put it in one shared constant.
- Pass the key with `--dart-define`, not in source. The key is in the APK and web bundle anyway.
  Restrict it by HTTP referrer for the web build; on Android, rely on a per-key quota and
  rotation.
- Replace the attribution widget text.
- Keep `userAgentPackageName`.
- Estimate: about half a day, plus a device check of the map and both pickers (**Estimate**).

A fourth hosted option, **Stadia Maps** (prices read 2026-11-17): the free tier (200k credits/month)
is for non-commercial use only. Starter is $20/month for 1M credits, Standard $80 for 7.5M,
Professional $250 for 25M; 1 raster tile = 1 credit; published overage 3¢ / 2¢ / 1.5¢ per 1,000 on
those plans. Whether overage is automatic or needs opting in: **Not checked**.

## Tiles per map session (Verified, 2026-11-17)

The current web build (release, CanvasKit, `flutter_map` 8.3.1, `ace5bc8`) was opened in headless
Chrome at `/map`. Requests to `tile.openstreetmap.org` were answered locally with a blank PNG and
counted; nothing reached OSM or production (the API host was unreachable, so no pins). The session
script: cold open, 4 half-screen pans, 2 zoom-ins, 2 more pans, 1 zoom-out. The map opens at zoom
13.6 and so loads z14 tiles; the zoom-ins reach z16.

flutter_map requests 256-px tiles per *logical* pixel (no `retinaMode`; From code), so the count
depends on the viewport in logical pixels, not the pixel ratio. The viewports were therefore run at
pixel ratio 1, which also makes wheel zoom behave the same in each.

| Viewport (logical px) | Cold open | After 4 pans | After 2 zoom-ins | End of session: distinct tiles | End of session: requests |
|---|---|---|---|---|---|
| 360×800 (Android) | 35 | 77 | 136 | **170** | 209 |
| 390×844 (iPhone-class) | 35 | 88 | 147 | **181** | 220 |
| 412×915 (large Android) | 35 | 96 | 155 | **193** | 232 |
| 1366×768 (desktop web) | 63 | 192 | 288 | **370** | 444 |

- "Requests" includes tiles requested again after being pruned off-screen. The blank test PNG had
  no cache headers; real tile servers send them, so the browser serves most repeats from its cache.
  Distinct tiles is the better estimate of what one session costs a provider.
- **Repeat sessions cost less (From package source):** on Android, flutter_map 8.3.1 caches tiles on
  disk by default (`BuiltInMapCachingProvider`, 1 GB, freshness from the server's HTTP headers). On
  the web, the browser cache does the same. A user who comes back to the same part of the city
  re-downloads little. How much is **Not checked**; the projection below ignores it, so it is an
  upper bound.
- **Planning figure: 200 tiles per phone session** (rounded up from 170–193), 400 per desktop
  session.

## Daily volume at 30 and 300 users (Estimate from the measurement)

How often an active user opens the map is **Not checked** (no PostHog event counts map opens
today), so two rates are shown. "Users" here means daily active users who open the map, on phones.

| | 1 map session per user per day | 3 map sessions per user per day |
|---|---|---|
| **30 users** | 6,000 tiles/day (~180k/month) | 18,000/day (~540k/month) |
| **300 users** | 60,000/day (~1.8M/month) | 180,000/day (~5.4M/month) |

The 30-user figure matches the current box's measured capacity of 30 *concurrent* users. Thirty
concurrent users means far more than 30 daily users, so at the box's limit the right-hand column of
the 300-user row is the realistic one.

## Monthly cost at those volumes (published prices, read 2026-11-17)

| Option | 180k/month | 540k/month | 1.8M/month | 5.4M/month |
|---|---|---|---|---|
| Geoapify (limit is per day: tiles/4 credits) | $0 (Free, 1.5k credits/day) | $59 (API 10) | $109 (API 25) | $179 (API 50) |
| Stadia Maps (commercial use needs a paid plan) | $20 (Starter) | $20 | $44 (Starter + overage) or $80 (Standard) | $80 (Standard) |
| MapTiler (Free not allowed) | $30 (Flex) | $36 | $225 | $765 (Flex + overage; higher plans **Not checked**) |
| Mapbox raster (at the first paid rate; volume discounts **Not checked**) | $0 | $170 | $800 | $2,600 |
| **Self-hosted on R2 + Cloudflare** (below) | **$0** | **$0** | **$0** | **$0** |

Geoapify's limit is per day, so peaks count, not the monthly average. Its paid plans are also
rate-limited to 5–30 requests per second; one phone cold-opening the map asks for 35 tiles at once.
Whether bursts are queued or rejected is **Not checked**.

## Self-hosted: pre-rendered tiles of the Tashkent area on R2, served through Cloudflare

The map cannot leave `tashkentMapBounds` (lat 41.18–41.43, lon 69.05–69.47; `map_viewport.dart`), and
its zoom is limited to 12.5–18 (`map_screen.dart`). The location pickers use the same tile layer. So a
fixed tile set covers every map view the app can show.

**Tile count over the bounds** (Web Mercator, **Verified** by calculation):

| Zoom | Tiles | Cumulative |
|---|---|---|
| 10–12 | 40 | 40 |
| 13 | 80 | 120 |
| 14 | 320 | 440 |
| 15 | 1,209 | 1,649 |
| 16 | 4,697 | 6,346 |
| 17 | 18,788 | **25,134** |
| 18 | 74,601 | 99,735 |

- **Recommended range: z10–z17.** At zoom 18 the app shows z17 tiles scaled up (flutter_map
  `maxNativeZoom: 17`, `maxZoom: 18`). Street-level z17 tiles stay readable at 18 on phones, and
  rendering z18 natively would quadruple the set for little gain.
- **Storage (Estimate):** 256-px PNG raster tiles of a dense city average roughly 10–30 KB, so z10–17
  is about 0.25–0.75 GB, and z10–18 about 1–3 GB. Vector tiles (one PMTiles file for the area) would
  be tens of MB.
- **Cost (Cloudflare R2, published prices 2026-11-17):**
  - Storage: $0.015 per GB-month, with 10 GB free.
  - Reads (Class B): $0.36 per million, with 10 million free per month.
  - Writes (Class A): $4.50 per million, with 1 million free.
  - Egress is free.

  At 5.4M tiles a month, even with no edge cache every read fits the free tier. A tiles subdomain on
  the Cloudflare zone the web app already uses adds the edge cache, so most requests never reach
  R2.

**Build and update process (one script run on the workstation; Estimate: about a day to set up):**
1. Download the Uzbekistan extract from Geofabrik and clip it to the bounds plus a margin
   (`osmium extract --bbox`).
2. Build vector tiles for the area with Planetiler (OpenMapTiles schema). For a city this takes
   minutes.
3. Render z10–17 PNG tiles from them with a MapLibre-based renderer (tileserver-gl in Docker) and a
   chosen style.
4. Upload them to R2 under a versioned prefix (`tiles/v<date>/{z}/{x}/{y}.png`). A new prefix per
   rebuild means the cache never needs invalidating, and the app reads the prefix from config.
5. Rebuild monthly, or when the style changes. Delete an old prefix once no client uses it.

**ODbL and attribution:**
- The tiles are a Produced Work of OpenStreetMap. They must show "© OpenStreetMap contributors"
  with a link to the copyright page.
- The main map and the lost-pet picker show this today. **The observation location picker
  (`add_observation_location_screen.dart`) has no attribution** (From code). That is a gap under
  OSM's terms with any tile source. It should be fixed with the switch, or before it.
- Raster tiles are not a database. If vector tiles are served publicly they may count as a
  Derivative Database and must be offered under ODbL. That is acceptable here, because it is
  unmodified public OSM data.

**Label language (Uzbek / Russian):**
- The style chooses which name field the labels use, so this is the only option with real control:
  for example `coalesce(name:uz, name:ru, name)`. A per-language tile set is possible, at 2–3×
  storage, still free.
- **How complete `name:uz` and `name:ru` are for Tashkent streets is Not checked.** A count with
  `osmium tags-filter` on the extract answers it before choosing a style.
- For the hosted providers, the label language is set per style or URL parameter, and their Uzbek
  coverage is **Not checked**.

**flutter_map support (From code and package docs):**
- **Raster:** today's `TileLayer` with a new `urlTemplate` plus `maxNativeZoom: 17`. It is the same
  change as for a hosted provider, but needs no key. The Android disk cache and the browser cache
  work as they do today.
- **Vector PMTiles:** needs extra packages (`vector_map_tiles` with a PMTiles provider). Rendering
  then moves to the device, which is heavier on low-end Android and on CanvasKit web, and the style
  is maintained in the app. That means several days plus device QA (**Estimate**). It is worth it
  only for per-user language switching or offline maps.

## Recommendation

**Self-hosted raster tiles, z10–17, on R2 behind Cloudflare.**
- The map is fenced to one city, so the whole tile set is small (~25k tiles, under 1 GB).
- It costs $0 at every volume above, with no daily caps, no rate limits and no key to protect in
  the APK.
- It is the only option where we choose the label language.
- It removes the dependency on the OSM tile server's usage policy entirely.
- The cost is one day to build the pipeline and a monthly rebuild. The app change is the same
  URL-and-attribution change as for any provider.

**If the owner prefers no pipeline: Stadia Maps Starter ($20/month).**
- It allows commercial use.
- It covers up to ~1M tiles/month, about 5,000 phone sessions, and grows to $80/month for 7.5M.
- Geoapify's free tier is the cheapest start, but its per-day cap and per-second rate limits make
  launch-day peaks a risk.

Either way, add the missing OSM attribution to the observation picker first; it is needed with
every option.

The choice is the owner's.

Sources (2026-11-16/17): geoapify.com/pricing, geoapify.com/pricing-details, mapbox.com/pricing,
maptiler.com/cloud/pricing, stadiamaps.com/pricing, developers.cloudflare.com/r2/pricing,
operations.osmfoundation.org/policies/tiles, osmfoundation.org/wiki/Licence; flutter_map 8.3.1
package source.
