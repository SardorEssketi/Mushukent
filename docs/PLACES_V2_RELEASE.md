# Places V2 first release candidate

This document records the **2026-10-02 pre-deployment review candidate**.
The approved import later completed; see
`docs/PLACES_V2_PRODUCTION_DEPLOYMENT_20261004.md`. Broad
discovery is paused. The original candidate contained 225 V2 verified physical
places. The pre-production gate below froze 217 eligible places after explicit
evidence review; the original 225-row candidate remains as a research artifact.
The workbook now shows ACCEPT, CORRECT and HOLD decisions for all 225 rows.

## Rebuild and QA

From the repository root:

```text
python -m backend.scripts.build_places_v2
python -m backend.scripts.qa_places_v2_release
python -m backend.scripts.dry_run_places_v2
```

The first command rebuilds source-backed V2 research outputs. The second
writes `places_release_candidate.jsonl`, `places_qa_warnings.jsonl`,
`places_coordinate_review.jsonl`, `release_quality_report.json`, and adds
Release candidate and RC QA warnings sheets to `places_review.xlsx`. The third
uses an isolated SQLite in-memory database and writes
`isolated_dry_run_report.json`. These commands have no production connection.

## QA snapshot, 2026-10-02

There are 225 candidate places: 142 pet stores, 50 veterinary clinics, 33
veterinary pharmacies, and no public shelters. QA raised 140 warning events
on 70 places, with **zero automatic merges and zero blocking missing-field
failures**. Sixty-five places appear in the coordinate visual-review list.
There are eight identical-coordinate pairs, five same-name pairs within 150 m,
29 different-name pairs within 20 m, 58 same-address/different-name pairs,
11 dense-cluster warnings, five district spatial outliers, one nearby category
difference, one place with two 2GIS firm IDs, one missing
district, two mixed-script names, three addresses without a house number, eight places with null address but alternate
location evidence, and eight field-conflict warnings. Warning classes overlap;
counts are not additive place counts. A shared building can legitimately hold
multiple businesses.

The five same-name nearby pairs need an explicit branch decision: Zoopolis
Sebzar/Yangi Sebzor, Force Bio Trade Yunusabad 3/1, Vet+Zoo House Mirzo
Tursunzoda 14, Animal Planet Bayqara/Suvsoz, and Animal Planet Askiya/Shota
Rustaveli. The first four have especially strong same-branch signals, but
street aliases and separately listed services make a silent merge unsafe.
Kuzya Universal at Obikhayot 5 has separate 2GIS firm IDs for clinic and pet
store evidence; inspect whether these identify one mixed-use storefront or
distinct businesses. Inspect the cited source pages and map pins, then record an approved
survivor/alias mapping or keep distinct branches with a reason. Eight shared
pin pairs also require visual inspection; some may be separate shops or a
shop and clinic in one building. The complete pair IDs are in the QA file.

Three of the original 11 field conflicts were resolved from branch-specific
official PetZoo evidence: Katartal and Buyuk Ipak Yuli hours, plus the
Chilanzar house number corroborated by 2GIS. The prior alternatives remain
in the audit. Eight conflicts remain; their disputed values are null. Six
concern addresses and two concern opening hours. The physical places remain;
conflicting hours do not affect map eligibility. Eight records have null display address in
total and use explicit location evidence. The QA checks field-level coordinate
sources, Tashkent bounds, exact/shared pins, close pairs, explicit district
text and neighborhood outliers. It cannot prove that every building pin is
the correct entrance or that district boundaries are precise; the coordinate
review list is the required visual inspection queue.

## Identity and category strategy

The immutable research ID, such as `v2_petzoo_katartal_60_1`, is the identity
anchor. The import key is `places_v2:<research ID>` stored in the existing
`places.source_id` column with source `manual`. A fixed UUID namespace derives
a deterministic `places.id` for new rows. Names, addresses, categories and
coordinates are attributes and **do not determine identity**; their correction
does not create a new place. A confirmed branch move keeps its ID, while a
genuinely new branch gets a new research ID. If two research IDs prove to be
the same branch, human review must choose a survivor and record the retired ID
as an alias before import. The unique `(source, source_id)` database index
protects repeated imports. The V2 importer maps only the verified **primary**
category in this release; secondary category evidence remains internal so the
published category counts and map labels match the review sheet.

The backend and Flutter recognize `veterinary_pharmacy` separately. Alembic
revision `20261002_0024` added the PostgreSQL enum value and was applied to
production during the approved 2026-10-03 deployment. The gate steps below
record the checks performed before that deployment.

## Isolated rehearsal and required PostGIS gate

The SQLite in-memory rehearsal inserted 225, updated 0, skipped 0, conflicted
0 and failed 0. All 225 rows were read back through `PlaceListItem` response
schema validation; an unchanged second pass skipped 225. The upsert test also
covers a changed name/coordinate updating under the same key and a UUID/key
collision being reported as a conflict. This validates mapping and API schema
serialization, **not** the PostGIS model, Alembic migration, spatial queries,
or HTTP endpoint. At the time of this first rehearsal, Docker was unavailable
and the installed local PostgreSQL 14 service had no PostGIS extension. The
required isolated PostGIS gate was completed later, as recorded below.

## Historical production-comparison plan

The research scripts were kept separate from production. The later authorized
read-only export used a read-only transaction to capture every place, including
inactive rows, with its UUID, `source`, `source_id`,
name, category, address, coordinates, contact fields, `verified_at`,
`is_active`, and category links. The core query is:

```sql
BEGIN TRANSACTION READ ONLY;
SELECT p.id, p.source, p.source_id, p.name, p.category, p.address,
       ST_Y(p.location::geometry) AS latitude,
       ST_X(p.location::geometry) AS longitude,
       p.phone, p.phone_2, p.website, p.instagram, p.telegram,
       p.opening_hours, p.verified_at, p.is_active,
       COALESCE(array_agg(DISTINCT l.category) FILTER (WHERE l.category IS NOT NULL),
                ARRAY[]::place_category[]) AS categories
FROM places AS p
LEFT JOIN place_category_links AS l ON l.place_id = p.id
GROUP BY p.id;
ROLLBACK;
```

Compare exact V2 `source_id` first. For legacy OSM/manual rows, generate
possible matches from distance, normalized name, address and branch-specific
evidence; **do not** match on name alone. Have a human approve a mapping of
`production UUID -> V2 source_id`, including explicit keep-separate decisions.
Do not delete or deactivate unmatched production rows automatically.

The remaining steps are in the pre-production gate section below. Provenance
and QA remain internal.

## Pre-production gate, 2026-10-02

The frozen snapshot is `data/places_v2/output/places_frozen_release.jsonl`,
with SHA-256
`8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be`.
It contains **217** places: 136 pet stores, 48 veterinary clinics, 33
veterinary pharmacies, and no public shelters. The 225 original rows received
215 ACCEPT, two CORRECT, and eight HOLD decisions. Three HOLD rows are confirmed
duplicates retired into explicit aliases; five are unresolved identities. The
two coordinate corrections use stronger, firm-specific 2GIS points for Force
Bio Trade and Vet+Zoo House. The 65 coordinate-review entries received 55
ACCEPT, two CORRECT, and eight HOLD decisions. Each decision records its reason,
original pin and source URLs in `places_gate_decisions.jsonl`.

All five same-name nearby pairs and eight identical-pin pairs have explicit
case decisions in `places_gate_pair_decisions.jsonl`. A fourteenth decision
covers Kuzya Universal's two 2GIS firm IDs: one physical place with clinic and
store evidence, with only its primary category mapped for this release. Three
pairs are confirmed duplicates, two pairs remain ambiguous, and the generic
Parkent 74 shop is held as a possible alias of Animal Planet. Same-address
cases with separately named business evidence are retained; a shared building
pin is not by itself a duplicate. The three retired research IDs and their
survivors are in `places_release_aliases.jsonl`.

Four district labels sourced only from search filters were cleared while their
firm-specific coordinates and addresses were retained. The Yangihayot clinic
kept its explicitly sourced district despite the proximity to Sergeli; the
previously unknown Exo Avia district remains null. Five frozen rows have null
districts. Nine frozen rows have null display addresses, supported by named
organization/firm pages and coordinate evidence. Eight frozen places retain
null values for disputed fields: seven addresses and one opening-hours field.
One original conflict row is on HOLD; the Animal Planet duplicate decision
introduced one disputed address, so the frozen count remains eight.

The 62 frozen rows that carry original QA flags have been adjudicated; their
flags remain visible for human filtering. The unresolved entity cases are the
Zoopolis Sebzar/Yangi Sebzor pair, the ZooCenter shop/clinic pair, and the
generic Parkent 74 shop. None is included in the frozen snapshot. Human visual
review can focus on these five rows and on the retained shared-building pins;
do not silently promote held rows or merge separate branches.

`python -m backend.scripts.freeze_places_v2_release --verify` verifies the
snapshot checksum without writing it. The freezer refuses to overwrite the
snapshot. `python -m backend.scripts.update_places_v2_gate_workbook` refreshes
the workbook's Frozen release, Gate decisions, and Retired ID aliases sheets
without changing the snapshot. Do not rerun the source builder/QA commands and
assume they regenerate this exact frozen release.

The Flutter map bounds now include all frozen coordinates, including three
eastern pins beyond the former east limit of 69.4200. Focused Flutter tests
cover all four category filters, marker kinds, localized labels, API parsing,
empty shelter data, and the map viewport. Seventeen tests passed and focused
Flutter analysis found no issues. Three read-only backend snapshot integrity
tests passed.

**PostGIS technical gate: PASSED on 2026-10-03.** Docker Desktop's UI process
was present without a backend or Linux engine. An initial WSL `E_ACCESSDENIED`
was caused by the execution sandbox: outside it, `wsl --status` worked. A
graceful Desktop stop hung; terminating only the orphaned UI process and
starting Desktop restored the Linux engine. The deeper reason the backend had
stopped was not established. No reset, VHDX operation, WSL unregister,
reinstall, or Docker data deletion was used.

The snapshot's SHA-256 was recomputed before any database operation and again
afterward; both matched the checksum above. A new `v2_gate` database in a new
`postgis/postgis:15-3.4` container, on a dedicated Docker network with no
host-published port, received the **complete** Alembic chain from an empty
application schema to `20261002_0024` (head). The enum includes
`veterinary_pharmacy`. The gate backend container mounted the repository
read-only and used only `gate-db/v2_gate`; its gate importer refuses any other
database URL.

The first import inserted 217, updated 0, skipped 0, conflicted 0 and failed
0. The identical second import inserted 0, updated 0, skipped 217, conflicted
0 and failed 0. SQL confirmed 217 total places, 217 distinct UUIDs, 217
distinct V2 source IDs, 136 stores, 48 clinics, 33 pharmacies, and 217
SRID-4326 geometries. All 217 places were read through
`SqlAlchemyPlaceRepository` and through the actual FastAPI place-detail route.
Category and map-bbox API filters returned 136/48/33/0 for the four categories.
All 217 pins were within the map bounds in a PostGIS envelope query, five
nearby API spatial queries found their expected pins, and none of the three
retired aliases created an extra place. Four existing database-backed place
endpoint tests passed in a **second** isolated database, leaving the imported
snapshot database untouched.

The test command is `python -m backend.scripts.postgis_gate_places_v2
import|verify` inside the dedicated backend container with
`PLACES_V2_GATE_ONLY=1`. The gate script checks the frozen hash before each
operation and writes no dataset file. The two test containers were stopped,
not removed, after validation. The earlier SQLite rehearsal remains historical
and is not the basis for this PostGIS result.

Passing this technical gate did not itself authorize production. The later
read-only export and approved deployment are recorded in
`docs/PLACES_V2_PRODUCTION_DEPLOYMENT_20261004.md`. The five held identities
remained outside the frozen snapshot; the final reviewed transaction updated
approved matches, inserted approved new branches, and left unmatched production
rows unchanged.
