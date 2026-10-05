# Places V2 final pre-deployment review (no production changes during review)

This is the historical approved review package. The deployment subsequently
completed; see `docs/PLACES_V2_PRODUCTION_DEPLOYMENT_20261004.md`. Production is
now at Alembic revision `20261002_0024`.

This package supersedes the field-merge proposal in
`docs/PLACES_V2_PRODUCTION_COMPARISON.md`. It uses the saved read-only production
export and the immutable 217-place V2 snapshot. It did not query or modify
production, run migrations, or deploy. The frozen snapshot SHA-256 is
`8e8084232e806caab17c6d8c699ae3072720f721944ca6f622a8232853f510be`;
the production export SHA-256 is
`27ae3058ad6ce114a117b8d8ab04876c86dd8beef4f24761dc1f57d2566c395c`.

## Reviewed pair decisions

All 69 formerly ambiguous candidate pairs have an individual decision and
reason in `production_pair_decisions_final.jsonl`: 26 `SAME_PLACE`, 22
`DIFFERENT_PLACES`, and 21 `UNRESOLVED`. Of the 26 same-place decisions, 23
create new one-to-one mappings. The other three identify a second legacy shop
UUID at a clinic already mapped through its legacy veterinary UUID: Doctor Vet,
Vet Alliance, and Vet Lider. The veterinary UUID survives in the proposed V2
mapping. The extra legacy shop rows stay unchanged under `SKIP_UNRESOLVED` until
a person decides their long-term identity and category treatment. No UUID is
deleted or merged automatically.

The resulting 89 one-to-one mappings preserve the production UUID and attach
the frozen V2 `source_id`; they also retain the old `manual_file:` identifier
in the review diff as an alias for migration planning. The action file has 89
`UPDATE_EXISTING`, 107 `INSERT_NEW`, 36 `KEEP_UNCHANGED`, and 45
`SKIP_UNRESOLVED` rows. `KEEP_UNCHANGED` includes all 31 originally
production-only rows plus five rows whose nearby V2 candidates were determined
to be different places. The 45 skips consist of 24 production rows and 21 V2
places. No action is `DELETE`.

The exact final action file SHA-256 is
`dcbd169f467f89fdbd133a277c95435077891a1e5587f1ae4894fa2eb25577ee`.

## Field merge policy

`production_field_decisions_final.jsonl` contains an explicit operation for
each supported backend field on all 89 proposed updates. A V2 NULL preserves
the production value: 195 field operations across 81 matched rows, including
all 59 previously identified legacy rows that might otherwise have lost a
value. Zero fields are cleared. Verified, non-conflicting V2 values can update
the corresponding production field. An equivalent phone or URL spelling is
`NO_CHANGE`. The five remaining `REVIEW` operations are primary category
changes from `pet_shop` to `veterinary`; the primary category and category
links remain as currently stored until a human approves each one. Source IDs
may still be attached only when the complete row action is approved.

The three pharmacy decisions are individual and supported by branch-specific
category evidence:

| Production UUID prefix | Place | V2 source evidence | Proposed primary category | Existing shop link |
| --- | --- | --- | --- | --- |
| `6dff24af` | NEKO, Amir Temur | Detailed 2GIS firm listing, medium confidence | `veterinary_pharmacy` | Retain as secondary |
| `d0704c94` | Felix zoo, Chilanzar 1st 60 | Detailed 2GIS firm listing, medium confidence | `veterinary_pharmacy` | Retain as secondary |
| `df11ba81` | Felix Zoo, Buyuk Ipak Yuli 60 | Agreeing Yandex/2GIS evidence, high confidence; V2 also lists `pet_store` as secondary | `veterinary_pharmacy` | Retain as secondary |

For Deep Forest Animals (`682650e9-5bb9-4dc8-9087-08cec9deb2e3`), the
existing `pet_shop` and `veterinary` category links are both retained. The
frozen V2 record also lists `pet_store` as a secondary category. The plan
removes **zero** category links.

## Artifacts

- `data/places_v2/output/production_pair_decisions_final.jsonl`: all 69
  individual pair decisions, evidence links, and same-place UUID handling.
- `data/places_v2/output/production_field_decisions_final.jsonl`: field-level
  old, V2, and result values with evidence and operation.
- `data/places_v2/output/production_deployment_review_final.jsonl`: the final
  action per production row and unmatched V2 row, with update operations.
- `data/places_v2/output/production_deployment_review_report_final.json`:
  counts and input hashes.
- `data/places_v2/output/production_deployment_review_final.xlsx`: filterable
  actions, pair decisions, field operations, and remaining decisions.
- `backend/scripts/finalize_places_v2_production_diff.py`: deterministic
  read-only builder with input-hash, coverage, UUID, link, and no-null-clear
  checks.
- `backend/scripts/build_places_v2_final_deployment_workbook.py`: workbook
  builder from those reviewed artifacts.

## Historical approval decisions

These decisions were recorded before the 2026-10-03 deployment. The 21 V2
places and extra legacy rows that remained unresolved were held outside the
approved write set.

1. Decide the 21 unresolved candidate pairs. The paired 21 V2 places remain
   uninserted; their corresponding production rows remain unchanged.
2. Decide what to do with the three extra legacy shop UUIDs at Doctor Vet,
   Vet Alliance, and Vet Lider. They are retained untouched for now.
3. Approve or decline five shop-to-clinic primary category changes recorded as
   `REVIEW`; no category change is implied by the update action.
4. Approve the 89 UUID mappings, 107 inserts, 195 production-value preserves,
   and three pharmacy category changes. Review any field differences that are
   material to the product. The final workbook groups these decisions.

## Deployment safeguards

No importer should consume the old `production_comparison.jsonl`, because its
earlier hypothetical V2-NULL merge could clear production fields. The approved
2026-10-03 importer consumed this final action and field-operation file and
rejected `REVIEW` fields and `SKIP_UNRESOLVED` rows for writes. A later importer
needs a new reviewed diff against the current baseline. It must
preserve the matched production UUID and all existing category links unless a
separate approved decision changes them. Inserts must use the frozen
`import_uuid` and V2 source ID. There is no automatic deletion or deactivation.

For the 2026-10-03 write, the team re-exported production read-only, checked
the baseline and frozen snapshot hashes, and took a backup before applying
revision `20261002_0024`. That revision is already present in production; do
not reapply it for a later change. Any future place-data write needs a fresh
comparison against the then-current database and revision, plus a new backup
following `docs/DEPLOYMENT.md`. The place-data importer should run in one transaction with
precondition checks, uniqueness checks, and post-write count/readback checks.
On a rerun it must recognize the approved post-state by V2 source ID and
preserved UUID, then skip without creating duplicates. Roll back the DML
transaction on any failed invariant. After commit, a post-commit problem
requires a separately reviewed compensation or controlled restore; do not
blindly restore a backup into a live database with concurrent writes.
