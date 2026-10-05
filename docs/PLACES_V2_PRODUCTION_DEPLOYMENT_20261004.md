# Places V2 production deployment record

This records the completed 2026-10-03 deployment. Production remains at
Alembic revision `20261002_0024` as of 2026-10-05; later application releases
superseded the release path named below.

The authorized Places V2 deployment completed on 2026-10-03 UTC / 2026-10-04
Asia/Tashkent. No place was deleted or automatically deduplicated. The release
was built from base commit `e5abd4f8eb3001056d2f8a8195115f590b48f389` with
only the reviewed Places V2 backend, migration, importer, and map/web changes
staged into a versioned release directory. The deployed release archive is
`places_v2_reviewed_release_20261003.tar.gz` (SHA-256
`f26fce2d22ad9f87cd5a19e03ea30ef0eee006212c95f38d4411e8fc5f44174d`).
The server release path is
`/opt/mushukistan-releases/20261003-e5abd4f-places-v2`.

## Immutable inputs and baseline

| Input | SHA-256 | Result |
| --- | --- | --- |
| Frozen 217-place snapshot | `8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be` | Matched before deployment and again afterward |
| Reviewed action diff | `dcbd169f467f89fdbd133a277c95435077891a1e5587f1ae4894fa2eb25577ee` | Matched before deployment and again afterward |
| Reviewed 149-row production baseline | `27ae3058ad6ce114a117b8d8ab04876c86dd8beef4f24761dc1f57d2566c395c` | Two fresh read-only exports matched byte for byte |

The action file was checked for exactly 89 `UPDATE_EXISTING`, 107
`INSERT_NEW`, 36 `KEEP_UNCHANGED`, and 45 `SKIP_UNRESOLVED` rows. It contained
no `DELETE` action, implicit NULL overwrite, unapproved UUID change, or write
to a skipped row. The second fresh production export was obtained immediately
before the first schema write. No material baseline drift was found.

## Backup and execution

Before the migration or any place-data write, a PostgreSQL custom-format
backup was written on the production host to
`/root/mushukistan-backups/mushukistan-20261003-164109-places-v2.dump`.
Its size is 122,146 bytes and SHA-256 is
`531cf816c5a28ef7a4f61e59c55cd22b2cdb61a8d5f74dae79fb1d569fb3fd4e`.
`pg_restore --list` succeeded. A full restore rehearsal of this backup was
not part of the documented production procedure and was not performed.

Alembic moved from `20260928_0023` to revision `20261002_0024`
(`20261002_0024_veterinary_pharmacy_category.py`), then reported it as head.
A read-only importer preflight reported `READY` with 149 existing rows.
The guarded transaction applied exactly 89 updates and 107 inserts, with zero
deletes and 45 skipped action rows. It reported 256 final places. A second,
read-only run reported `ALREADY_APPLIED`, zero inserts, zero updates, and zero
writes. There was no unexpected collision or reviewed-plan deviation.

The importer preserved all 89 mapped production UUIDs, retained 195 existing
production field values where V2 was NULL, cleared zero fields, and retained
all existing category links. All 36 `KEEP_UNCHANGED` rows, including the 31
production-only rows, and all 24 production `SKIP_UNRESOLVED` rows remained
unchanged. The remaining 21 skips are V2 places that were not inserted.

## Verification

Production SQL readback found 256 places, 196 distinct V2 source IDs, and all
196 approved V2 locations inside the supported map bounds. No approved V2 pin
was outside those bounds. Primary-category counts were 183 `pet_shop`, 42
`veterinary`, and 31 `veterinary_pharmacy`. The three approved pharmacy
recategorizations retained their shop links. Category-link and API filter
counts were 193 `pet_shop`, 42 `veterinary`, 57
`veterinary_pharmacy`, and zero shelters. The frozen V2 has 33 pharmacy places;
31 were in the approved action set and two remain skipped for review.

Public health was healthy. Six public detail samples covering updates,
inserts, and the three populated categories serialized correctly. Category
filters, a bounded map query, and a nearby pharmacy query succeeded. The
served Flutter bundle SHA-256 matched the tested build
(`f65a531bd24b016acb6e23b5188319eaaa84b11e1cfd1af43b9e9d4bc2bb8995`).
A headless Chrome screenshot of the public `/map` route visibly showed map
tiles, place markers, and clusters. The browser required a local
`--ignore-certificate-errors` flag because of this workstation's certificate
chain; separate Windows `curl.exe` requests verified the public TLS connection
normally. This browser flag was local only and did not alter the deployment.

The isolated release rehearsal completed the full Alembic chain, applied and
reapplied the diff, read all 196 approved places through repository/API paths,
and exercised category and spatial queries. Focused backend tests in a local
test-only image passed: seven unit tests and seven PostGIS-backed place/map
tests. Thirty-four unrelated database tests were skipped in the unit-only run;
the seven relevant database tests were then run against a separate isolated
PostGIS test database. Eleven focused Flutter tests passed; focused analysis
and the production web build succeeded. No test was pointed at production.

Evidence artifacts:

- `data/places_v2/output/production_places_predeploy_20261003.jsonl`
- `data/places_v2/output/production_places_pre_migration_20261003.jsonl`
- `data/places_v2/output/production_deployment_sql_verification.json`
- `data/places_v2/output/production_deployment_public_verification.json`
- `data/places_v2/output/production_map_screenshot.png`
- `backend/scripts/apply_reviewed_places_v2_diff.py`

Unresolved identity and category decisions remain exactly as in the reviewed
action file. This deployment made no decision about them.
