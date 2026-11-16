# Map tile providers: comparison for the owner's choice

Status: comparison only. Nothing is integrated (owner decision, 2026-11-16; memo 7.3 in
`FIXES_RESULTS.md`). Prices and limits are from the providers' public pricing pages, read on
2026-11-16. They change, so re-check them on the day of the decision.

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

**How many tiles we need: Not checked.** Tiles per map session were not measured. A first screen
at 256-px tiles on a phone is a few dozen tiles, and every pan or zoom adds more. Measure on a
device (count tile requests for one typical map session) before picking a tier: 360k tiles/month
covers ~10,000 sessions at ~36 tiles each, but not at 100.

**Reading:**
- **Geoapify** is the only one whose free tier allows commercial production use without a card.
  It is the cheapest start.
- **Mapbox** has the largest free raster volume and the most polished styles. It bills
  automatically beyond 200k tiles, so set a budget alert.
- **MapTiler**'s free tier does not allow this app's use, so it starts at $30/month.

The choice is the owner's.

Sources (2026-11-16): geoapify.com/pricing, geoapify.com/pricing-details, mapbox.com/pricing,
maptiler.com/cloud/pricing.
