# Places V2 production comparison — review package, 2026-10-03

**Historical status on 2026-10-03: ready for deployment review, not yet approved
for production writes.** The final review superseded this initial proposal,
and the approved deployment later completed. See
`docs/PLACES_V2_FINAL_DEPLOYMENT_REVIEW.md` and
`docs/PLACES_V2_PRODUCTION_DEPLOYMENT_20261004.md`.
No production place was inserted, updated, deleted or deactivated; no migration
or deployment was run. The frozen V2 snapshot was read only and still has 217
rows and SHA-256
`8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be`.

## Read-only baseline

The existing SSH route reached the active VPS. The database container is
`mushukistan-db`, and the deployed backend reported Alembic revision
`20260928_0023`. The export SQL uses `BEGIN TRANSACTION READ ONLY` and
`ROLLBACK`, selects only place comparison fields, and was transferred as raw
UTF-8. Its local SHA-256 is
`27ae3058ad6ce114a117b8d8ab04876c86dd8beef4f24761dc1f57d2566c395c`.
The export has **149** active places: 142 primary `pet_shop`, seven primary
`veterinary`; all use source `manual` and have `manual_file:` source IDs.

Actual PostgreSQL catalog inspection found exactly one foreign key to
`places.id`: `place_category_links.place_id` with `ON DELETE CASCADE`.
All 149 place UUIDs have category links (153 link rows; four places have both
shop and veterinary links). No other production column with `place` in its name
or foreign key to `places` was found. Repository model/code inspection also
found no post, observation, user, favorite or report place-ID reference. This
does not justify changing UUIDs: preserve them for matched places and retain
the category links in the same transaction.

## Proposed classification

| Classification/action | Count |
| --- | ---: |
| Production `MATCHED_TO_V2` / `UPDATE_EXISTING` | 66 |
| Production `PRODUCTION_ONLY` / `KEEP_UNCHANGED` | 31 |
| Production `AMBIGUOUS` / `REVIEW` | 52 |
| V2 `MATCHED_TO_PRODUCTION` | 66 |
| V2 `NEW_V2_PLACE` / `INSERT_NEW` proposal | 97 |
| V2 `NEW_V2_PLACE` / `REVIEW` before insert | 54 |

The machine-readable diff contains 300 action rows: 66 updates, 97 inserts,
31 unchanged production rows, and 106 review rows. The review file contains
69 possible production/V2 pairs. It covers every ambiguous production row and
every held V2 row. Every production-only place is listed individually in the
diff and in the workbook; all 31 are kept unchanged in this release plan.
There is **no DELETE action**.

The matcher requires geographic proximity **plus** distinctive normalized
name evidence, with address or category evidence for larger pin differences.
Cyrillic names are transliterated for candidate comparison. Generic names,
multiple nearby chain branches, same-pin different-name businesses, category
collisions, and competing production UUIDs are held. Phone/domain agreement is
recorded but cannot by itself make a match: legacy contacts may be wrong.
Different branches remain distinct. The pair file records distance, name and
address similarity, category and contact agreement, and a specific ambiguity
reason. All automated proposals require human approval before a write.

Of the 66 proposed updates, 59 would clear at least one non-null legacy field
when the V2 value is NULL. Across these rows there are 46 phone, 31 second
phone, 56 hours, nine website and three address clearances (counts overlap).
These are **review items**, not executed changes. Three proposed matches change
the primary category from `pet_shop` to `veterinary_pharmacy`; those category
decisions also require approval. One proposed matched row, Deep Forest Animals,
has an existing secondary shop category link. Preserve secondary links by
default; change them only with a separate explicit decision.

## Identity and deterministic deployment plan

The V2 source ID, `places_v2:<research ID>`, is the update key. For each
approved matched row, **keep its existing production UUID**, update its
approved attributes, and attach the V2 source ID in `places.source_id` while
keeping `source='manual'`. The 66 old `manual_file:` IDs and their proposed V2
IDs are archived in `production_legacy_source_aliases.jsonl`; do not run the
legacy manual-file importer again. For an approved genuinely new V2 place,
insert its deterministic `import_uuid` and stable source ID. The isolated gate
importer assumes new deterministic UUIDs for all rows and must **not** be used
unchanged for this production mapping.

The proposed 97 inserts comprise 36 stores, 33 clinics and 28 pharmacies. If
all currently proposed actions are approved without changes, the production
primary-category counts would become 175 shops, 40 clinics and 31 pharmacies,
246 places total. These are planned checks, not observed production results.
The 31 production-only and 52 ambiguous production rows stay intact; the 54
held V2 rows are not inserted.

At the time, the proposed next steps before an authorized deployment were:

1. Approve every one-to-one UUID mapping, the 69 ambiguous pair decisions,
   and the 97 proposed inserts. Record explicit keep-separate decisions.
   Approve each disputed legacy-field clearance and the three pharmacy
   recategorizations. Leave the 31 production-only rows unchanged unless a
   separate decision changes that policy. Regenerate only this comparison
   package if approvals alter the actions; never regenerate the V2 snapshot.
2. Re-export production places read-only immediately before deployment. If
   the place baseline or Alembic revision differs from this package, stop and
   recompare. Verify the frozen V2 hash again.
3. Follow `docs/DEPLOYMENT.md`: take a timestamped full custom-format
   `pg_dump -Fc` outside the database volume, verify it is non-empty and
   inspect it with `pg_restore --list`. Restore-test it into an isolated
   database before a production write. This task did not make a backup because
   no production write was performed.
4. With separately authorized release code, apply migration
   `20261002_0024` after the backup. Bring up a backend version that supports
   `veterinary_pharmacy` and verify its health and serialization **before**
   writing any pharmacy rows. Production was at `0023` at the time of this review;
   it is now at `20261002_0024`.
5. Run a purpose-built, approved importer in **one place-data transaction**.
   It must lock `places` and `place_category_links`, recheck the approved
   baseline, check `source/source_id` uniqueness and UUID collisions, and
   abort on any mismatch. For matched rows, look up the approved production
   UUID and preserve it; for inserts, use the V2 deterministic UUID. Apply
   category links in the same transaction, retaining approved secondary links.
   Skip all `KEEP_UNCHANGED` and `REVIEW` rows. There is no delete or automatic
   deactivation.
6. The importer must recognize either the exact approved **pre-import** state
   or the exact approved **post-import** state. On a repeat run, find existing
   V2 rows by `(source, source_id)`, verify their approved UUIDs and values,
   then report skips. A mixed or unexpected state must abort; it must never
   insert a second row for a matched branch.
7. Before commit, verify the approved update/insert counts, no duplicate
   source IDs, preserved matched UUIDs, and the expected category-link state.
   Roll back the transaction on any failed invariant. After commit, recheck
   total and V2-key counts, category filters, map bounds, nearby queries and
   all approved UUID mappings through the public API.

**Rollback:** Before the place-data transaction commits, issue `ROLLBACK`.
The enum migration commits separately from the place-data transaction, so
rolling back DML does not undo it. If a post-commit error appears, stop further release actions and application
writes, retain the custom backup, and restore it first to a fresh isolated
database for validation. Prepare a separately reviewed targeted compensation
or a controlled full restore to a replacement database during a maintenance
window. Do not run `pg_restore --clean` against a live database with concurrent
writes; that could erase unrelated user changes. No rollback or production
write was executed here.

## Review files

- `data/places_v2/output/production_places_readonly_export.jsonl`: the
  byte-preserved production baseline, including the minimum place fields.
- `data/places_v2/output/production_match_candidates.jsonl`: proximity/name
  candidates with evidence scores; discovery only, not approved matches.
- `data/places_v2/output/production_comparison.jsonl`: every proposed action.
- `data/places_v2/output/production_ambiguous_review.jsonl`: 69 ambiguous
  production/V2 pairs with distance, evidence and reason.
- `data/places_v2/output/production_legacy_source_aliases.jsonl`: 66 proposed
  legacy-to-V2 source-ID mappings with preserved production UUIDs.
- `data/places_v2/output/production_comparison_report.json`: counts and hashes.
- `data/places_v2/output/production_comparison_review.xlsx`: filterable human
  review sheets for matches, production-only rows, ambiguous pairs and V2 rows.
