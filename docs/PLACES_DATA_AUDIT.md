# Tashkent places data audit — 2026-10-01

This is the historical pre-deployment source audit. Places V2 was subsequently
reviewed and deployed; see `docs/PLACES_V2_PRODUCTION_DEPLOYMENT_20261004.md`.

## Scope and finding

The repository contains **one tracked manual place workbook**, `Mushukistan_map.xlsx` (SHA-256 `4d59c5ce0e75716176ddfc15767a5e9d6b53f7a41d8691fcb752d52287ded7ac`). It has 84 physical rows, of which 28 are blank and **56 are populated candidates**. The reported historical 1,336 raw / 1,334 filtered / 176 candidates / 165 reviewed records and the Yandex extraction code are **not present** in this repository or its visible branches. Release copies of the same workbook exist under ignored `.data`, but have the same hash. The current production database was not queried. Therefore, the identity of the historical 165 records and the exact extraction bug cannot be established from available evidence.

Documentation (`PROJECT_BIBLE.md`, `DATABASE.md`, `API.md`, `PRD.md`) defines product and schema behavior. The root workbook is the only available tracked manual import input; it is **not** an independently verified authoritative data source. The current backend may also contain OSM and manual rows from past imports, but its actual contents have not been audited.

## Repository path and likely failure

- `backend/scripts/import_manual_places.py` reads the active XLSX sheet by header, validates required name/type/coordinates, copies optional contact fields as text, and computes `source_id` from name, categories, and rounded coordinates. Reimport skips an existing `source_id`. It does **not** verify phones, URLs, branch identity, source provenance, or changes to an existing row. An address or coordinate edit changes the key and can produce a second database row.
- `backend/scripts/import_osm_places.py` fetches OSM objects from Overpass in a fixed Tashkent bbox and upserts only by OSM object ID. It uses selected OSM tags for phone, website, address, and hours. It does not resolve OSM/manual duplicates.
- `backend/app/infrastructure/db/models/schema.py` and the 20260730/20260818 migrations define `places` and category links. `backend/app/features/places/application/schemas.py` exposes contact fields directly. Flutter `frontend/lib/core/network/mushukistan_api.dart` reads them and `frontend/lib/features/map/presentation/screens/map_screen.dart` displays them.
- The workbook itself contains a proven address mismatch: PetZoo Chilanzar at row 5 says building **25**, while [PetZoo's branch list](https://petzoo.uz/index.php?dispatch=store_locator.search) and the [2GIS point](https://2gis.uz/tashkent/directions/points/%7C69.226577%2C41.286058%3B70000001036765852) identify building **23**. It also has a non-Uzbekistan-format `+7` number at row 18 and the same phone on two differently named rows (34 and 48). Those two phone anomalies are review flags, not proven bad matches.

The importer reads optional values from their named columns, so there is no evidence that it shifts columns itself. The verified bad address is already in the workbook. The likely failure is upstream association or manual matching, combined with an importer that accepts unverified fields and has no per-field provenance. The exact Yandex extraction/parsing mechanism is unavailable and should not be asserted as fact.

## Trust boundary

The 56 workbook names, categories, coordinates, addresses, phones, sites, social links, and hours are **candidate assertions only**. Coordinates are within the configured Tashkent bbox and unique, but that validates geometry only. None of its contact or address fields should be copied to the public map without independent evidence. `null` in the reviewed output means the legacy claim was withheld, not that the business lacks the field.

The audit searched all 56 candidate identities: 7 have field-level cited evidence and 49 have only search attempts pending adjudication. `data/places_review/search_attempts.json` records the 50 name-and-address queries used for the rows outside the initial six evidence records; Charley was then adjudicated separately. Search snippets alone did not promote any field.

## Canonical review schema

Each JSONL record has a stable `place_id` (UUIDv5), `origin`, `legacy_row`, `name`, `alternative_names`, `category`, `subcategory`, `latitude`, `longitude`, `address`, `district`, `phone_numbers`, `website`, `instagram`, `telegram`, `other_contacts`, `opening_hours`, `description`, `source_references`, `evidence_checked_at`, `last_verified_at`, `field_evidence`, `review_status`, `review_reasons`, and `validation_flags`. `last_verified_at` is set only for high-confidence records. `field_evidence` carries each field's value, source URLs, and confidence. The raw candidate is retained in `legacy_candidate`; it is not a public value. The original workbook hash is pinned in `evidence.json` so reordering rows cannot silently associate cited evidence with another business.

Categories are `pet_store`, `veterinary_clinic`, `veterinary_pharmacy`, and `animal_shelter`. A physical branch is one place. Multiple businesses at one address remain separate. At audit time the product enum had `pet_shop`, `veterinary`, and `shelter`; the research schema required a separate pharmacy mapping decision. Production now also supports `veterinary_pharmacy` after revision `20261002_0024`.

## Evidence and conflict rules

- High: a directly relevant official business page, or an official branch page paired with a map point whose name and address agree. The coordinate evidence is the exact cited map/building point.
- Medium: one credible branch source without an independently resolved map location.
- Conflict: credible sources disagree. The public value remains null and the alternatives remain in `field_evidence`.
- Needs review: identity, address, or coordinate evidence is missing, or a conflict exists. No guess fills a missing field.

Sources actually used for promoted or candidate fields: [PetZoo branch list](https://petzoo.uz/index.php?dispatch=store_locator.search), [MyVet](https://myvet.uz/ru), [Puls](https://puls-vet.uz/), [Charley](https://charley.uz/kontakty), cited Yandex building/business pages, cited 2GIS points/listings, and the [Vet Medical Telegram page](https://t.me/VetMedicalHome). The [NEKO 2GIS listing](https://2gis.uz/tashkent/firm/70000001045615515/tab/photos) is a medium-confidence discovery lead. OSM code was inspected but no fresh OSM data was fetched. Google Maps was not used. No access control was bypassed.

The [Charley site](https://charley.uz/kontakty) says `10:00–21:00`, while its [Yandex listing](https://yandex.uz/maps/org/zoomag_charley/241071305184/) shows `09:00–22:00`. The record's opening hours are null with both values retained as a conflict. The site and map provide two distinct phone numbers already present in the legacy row; neither is counted as a corrected phone.

## Measured result

| Measure | Count |
| --- | ---: |
| Existing populated candidates examined | 56 |
| Existing candidates with adjudicated cited evidence | 7 |
| Existing high-confidence map records | 3 |
| New candidates discovered | 3 |
| New high-confidence map records | 1 |
| Final high-confidence review records | 4 |
| Existing records materially corrected | 3 |
| Wrong phone / website values conclusively corrected | 0 / 0 |
| Existing phone records enriched with a verified additional number | 1 |
| Existing addresses corrected | 1 |
| Existing coordinates moved more than 10 m | 2 |
| Confirmed duplicate records | 0 |
| Unresolved field conflicts | 1 (Charley hours) |
| Records requiring further review | 55 (53 existing, 2 new) |

The last row is **53 existing plus 2 new**, totaling 55. The three new candidates are Puls (reviewed), Vet Medical (needs location review), and NEKO veterinary pharmacy (needs location and independent confirmation). No Tashkent-city shelter passed location and identity checks; the discovered Piskent shelter is outside the city scope, and FPZH's citywide contact page does not establish a physical shelter point.

For the **four high-confidence records only**, coordinates, address, phone, official website, and opening hours are each **4/4 = 100%**. Instagram and Telegram are **0/4 = 0%**; district, description, and subcategory are also 0/4. These percentages are deliberately narrow and should not be read as coverage of all 56 legacy candidates.

| Field present in unverified workbook | Count | Raw completeness |
| --- | ---: | ---: |
| Coordinates | 56/56 | 100% |
| Address | 56/56 | 100% |
| Primary phone | 50/56 | 89.3% |
| Opening hours | 53/56 | 94.6% |
| Website | 16/56 | 28.6% |
| Instagram | 23/56 | 41.1% |
| Telegram | 34/56 | 60.7% |

These are presence rates for candidate claims, not trusted field completeness.

`places_audit_log.jsonl` contains 471 field transitions, including 425 legacy values withheld pending verification. The only validation flags observed were one phone that fails the Uzbekistan format check and one phone shared across two differently named rows. There are no confirmed duplicates in the available 56-row slice. This does not rule out duplicates in the missing historical 165 or the production database.

## Deduplication and repeatable workflow

Run from the repository root:

```powershell
python backend/scripts/audit_places.py
```

The script reads the immutable workbook, checks its hash, validates fields, keeps raw claims in `places_raw_snapshot.jsonl`, applies the curated `evidence.json` by pinned workbook row, and writes reviewed, pending, new-candidate, audit, flags, and XLSX files under `data/places_review/output`. It never opens a database connection. Reverification is done by adding field-specific evidence with URLs and confidence, then rerunning the script. Evidence is never taken from a neighboring row or inferred from a shared chain name.

Deduplication is a **review suggestion**, never an automatic merge. It compares physical distance, normalized name, exact address, and phone agreement. Rows within 10 m are flagged as a shared site; rows within 80 m with the same name plus the same address or phone are possible duplicates. Shared websites, social accounts, and chain phone numbers are corroborating evidence only and cannot merge branches. Two branches at different addresses remain separate. The later production comparison used source IDs, geographic distance, and branch addresses.

## Historical import preparation

**A. Product at audit time:** name, category/categories, point, address, up to two verified phones, website, Instagram, Telegram, hours, description, and verification date. The backend then supported these except an explicit veterinary-pharmacy category; support was added later. Additional phone numbers remain internal unless the product/API is expanded deliberately.

**B. Internal review:** source URLs, field confidence, candidate old values, alternatives, audit history, match status, and validation flags. Keep these outside the public place API.

**C. Later use:** district/locality, subcategory, more than two phones, additional social links, and structured hours. No database migration is needed just to retain these in the offline review dataset.

At the time of this audit, the proposed next step was to obtain missing historical raw/reviewed Yandex files and a read-only database export, then reconcile them with the 56-row workbook and OSM rows before any import. The four-record reviewed file was an audit artifact, **not a complete replacement dataset**. This audit did not modify production; the later Places V2 review and deployment are recorded separately.
