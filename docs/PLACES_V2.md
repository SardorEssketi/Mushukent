# Tashkent places V2: independent research dataset

Current production status (2026-10-05): the approved Places V2 deployment has
completed. Production is at Alembic revision `20261002_0024` and has 256 places,
including 196 approved V2 source IDs. See
`docs/PLACES_V2_PRODUCTION_DEPLOYMENT_20261004.md` for the deployment record.
The places API accepts `pet_shop`, `veterinary`, `veterinary_pharmacy`, and
`shelter`.

The research snapshot and review process below describe the historical
2026-10-02 pre-deployment state. At that time it was **review only; not ready to
replace production places**.
The release-candidate QA, stable-ID and dry-run procedure is in
`docs/PLACES_V2_RELEASE.md`. Run
`python backend/scripts/build_places_v2.py` to rebuild offline. V2 inputs are in
`data/places_v2/`; generated files are in `data/places_v2/output/`. The old
Yandex dataset is not an attribute source. No database connection, import, or
deployment is part of this pipeline.

## Historical research snapshot (2026-10-02)

There are **505 raw discovery observations**, **427 grouped candidates**, and
**225 unique source-backed physical places proposed for human review**: 142 pet stores,
50 veterinary clinics, 33 veterinary pharmacies, and no public shelter. The
candidate queue has 123 discovery-only leads, 46 ambiguous entities held for
review, and 10 candidates excluded from the map. Eight verified places have
unresolved *field* conflicts; those places remain in Verified with the
disputed fields null. The Needs review sheet has 187 rows because it also
includes excluded candidates and field-review annotations.
Release QA resolved three of the former eleven field conflicts using
branch-specific official evidence; the prior alternatives remain in the audit.

The continuation added 247 net grouped candidates relative to the
180-candidate starting snapshot. Both public Yandex name and name/address
searches were attempted for all original 164 discovery-only leads (322 probe
attempts); 43 are now linked to independently verified physical places, 120
remain discovery-only, and one is excluded. A second 2GIS pass searched 127
then-unresolved original leads by name and district. Of 82 long queries that
returned HTTP 404, shorter-name retries yielded usable results for some; 73
unique leads had at least one 2GIS search result across the two passes. Seven
exact branch links were accepted after checking detailed firm pages and map
points. A search result alone was never treated as an entity match. Many
additional places came from 2GIS district,
branch, and pagination searches. The 86 removed duplicates are duplicate
**observations**, not a count of duplicate physical businesses.

| Verified-field completeness | Percent |
| --- | ---: |
| Address | 96.4% |
| Coordinates | 100.0% |
| Phone | 15.1% |
| Opening hours | 4.9% |
| Website | 3.6% |
| Instagram | 0.0% |
| Telegram | 0.9% |

These percentages use 225 unique verified records as the denominator. Optional fields
are deliberately null when their branch-level evidence is missing. A building
coordinate is a map point, not a surveyed entrance coordinate.

## Files and review workflow

| File | Purpose |
| --- | --- |
| `output/places_candidates.jsonl` | Grouped location leads with raw observation IDs and source URLs |
| `output/places_verified.jsonl` | Physical locations with sourced identity, category, address and point |
| `output/places_needs_review.jsonl` | Discovery-only, held, and field-conflict review rows |
| `output/places_verification_queue.jsonl` | One row per candidate with next action; explicit research decisions replace generic notes |
| `output/places_sources.jsonl` | Field-level value, source, status and confidence; kept out of public API |
| `output/places_search_log.jsonl` | Source pages, actual first-seen candidate yield, executed queries and separate planned queries |
| `output/places_audit.jsonl` | Validation, grouping, shared-contact, chain, held-location and confidence decisions |
| `output/quality_report.json` | Computed totals, completeness, per-district statistics and discovery yield |
| `output/places_review.xlsx` | Filterable Verified, Needs review, Candidates, Verification queue, Sources, Audit and Summary sheets |
| `shelter_investigation.jsonl` | Organization existence versus public visitor-location decisions |

Start with the Verified sheet, filter by category and district, inspect every
point against its Sources rows, then review conflicts and held candidates.
The Verification queue is a worklist; **being in the queue does not mean that
an individual lead was fully researched**. The original 164 leads all received
public Yandex search probes, and the remaining 127 also received 2GIS searches;
120 still lack enough branch-specific
location evidence. `candidate_research_decisions.jsonl` records explicit
identity, category, location and address holds. Other discovery-only rows still
require a detailed listing or official branch evidence. Do not infer that an
older directory address and a current map address refer to the same branch.

## Evidence and deduplication rules

Identity/location verification is independent of optional-field verification.
A detailed current map building listing that names the business and category,
states the address, and provides the building coordinate can establish a
high-confidence physical place by itself. One ordinary map organization page
may support medium confidence for an optional contact field. Official direct
claims or multiple independent providers may support high confidence. A field
with credible conflicting values is null and flagged without suppressing a
well-established physical location.

Raw observations are grouped when compatible normalized names and full house/
block addresses agree, or when close coordinates plus matching contact data
establish the entity. Identical brand names at different addresses remain
separate branches; different businesses in one building remain separate.
Points over 150 m apart cannot automatically merge. Curated links from a lead
to a 2GIS firm must also pass a 150 m firm-pin distance check. Directory records with
alternate house numbers stay visible for review rather than being forced into
current map branches. Validation checks required evidence, `+998` phone form,
HTTP(S) URLs, coordinate bounds, shared coordinates and contacts, and branch
attribution. Original raw files remain unchanged.

## Geographic coverage and discovery status

Verified counts by district: Bektemir 6, Chilanzar 15, Mirobad 24,
Mirzo Ulugbek 46, Olmazor 14, Sergeli 15, Shaykhantahur 4, Uchtepa 11,
Yakkasaray 11, Yangihayot 7, Yashnabad 39, Yunusabad 32. These are map-ready
research proposals, **not a coverage estimate**. Candidate district hints are
missing for 72 records and are not a complete distribution. The full
category-by-district table is in `quality_report.json` and the workbook.

**Discovery is not saturated.** Yandex pet-goods pages 7–10 yielded 5, 4, 4,
and 5 first-seen name/address pairs before page 11 returned zero. Yandex
veterinary-pharmacy pages 3 and 4 each yielded five before page 5 returned
zero. For the 2GIS district pet-store query, six districts exposed page 2,
three exposed page 3, and Mirzo Ulugbek exposed page 4. The ten later pages
produced 28 individually accepted physical places; even the last page produced
two. Two later 2GIS veterinary-pharmacy pages produced seven accepted places.
Clinic district searches exposed no page-2 links. Other source/query variations
can still add places, and 123 leads remain discovery-only. The search log records
executed page yields and access limits; no CAPTCHA, authentication, or anti-bot
control was bypassed.

A separate 12-district 2GIS `Зоотовары` wording sweep exposed 19 unfamiliar
firm IDs, but none had a new target-category firm page with a reliable branch
address and point. This is useful convergence evidence for that wording, while
the nonzero yields above and unresolved leads prevent a citywide saturation
claim. The pipeline also caught an earlier duplicate Green Vet stable ID:
its 2GIS firm point and Yandex house evidence now form one place, with the
42 m point change recorded in the audit.

2GIS detailed firm pages were accepted when the name, category, address, and
firm-specific route point belonged to the same firm ID. Searches returned
some apparent aliases and several separately named stalls at shared market
addresses; uncertain matches remain in Needs review. PetZoo's official store
locator and map evidence support separate branches. The Chilanzar branch now
uses house 23, supported by the official locator and 2GIS;
the Osiyo branch is likewise mapped with several conflicting street-address
variants and a null display address. Darel also has a null address because
Yandex and 2GIS place the same clinic point under different street addresses.
An independent OpenStreetMap Overpass sweep was attempted, but the public
endpoints returned HTTP 406 or timed out; no OSM observations were added.

No shelter in Tashkent city has a verified **public visitor location** in this
dataset. Kotomania and Milye Koshki appear to exist, but their public sources
do not identify a map-suitable location. Mehr and Hayot shelter listings are
outside the city. Do not publish private or inferred shelter addresses. Other
service categories found were grooming, boarding, pet taxi and animal-welfare
organizations; these remain outside the four final categories.

## Import context and historical preparation

As of 2026-10-05, the production backend accepts `pet_shop`, `veterinary`,
`veterinary_pharmacy`, and `shelter`. Production Alembic is already at revision
`20261002_0024`, and the database enum includes `veterinary_pharmacy`.
Place details include name, point, address, two phone slots, website,
Instagram, Telegram, hours, description and verification timestamp. Flutter
displays the contact fields. Mapping pharmacies to `veterinary` would claim
clinic services that may not exist. The following research and import notes
record the earlier review plan.

At the time, the proposed next steps were to approve a frozen, versioned V2 snapshot and
source log. Resolve the eight remaining field conflicts and held branch/address cases
where possible, leaving unresolved optional fields null. Spot-check branch
pins, especially shared buildings and the Fergana Road 4 veterinary-pharmacy
market stalls. Broad discovery is paused for this first release candidate;
the search log remains available for a later refresh. Prepare an import
dry run only against an isolated database. Use V2 stable IDs as import source
IDs, compare inserts/updates/deactivations with the current map, and seek a
separate explicit production decision. Provenance, confidence and audit stay
internal; only approved display fields belong in the public API.
