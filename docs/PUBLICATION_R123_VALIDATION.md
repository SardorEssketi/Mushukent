# Publication reliability R1-R3 correction validation

Starting reviewed commit: `2712c3f4503d56a81afdb1d317f0f91ac55c2800`.
Corrected implementation commit: `736b66bd8d4dbd3742405ad282461485559d75e5`.
Branch: `fix/publication-reliability`.
Worktree: `D:/Data science/mushukent-publication-reliability`.
Shared main remained clean at `8c273a877cebdf02ee8dbf7b130f91cd3a8dfce3`.

## Assessment

**READY WITH CONDITIONS** for separately authorized integration review. No known
remaining R1-R3 integration blocker was found after correction and cumulative
review. This is not production-release approval. R4's fleet/migration/rollback
conditions remain mandatory; R5 remains a MEDIUM follow-up.

## Corrections and local commits

- `1e61f30`: R1 dispatch/reconciliation binding, session epochs, cancellation and
  deterministic transition tests.
- `7113296`: R3 publication-specific exception containment before Uvicorn logging,
  sanitized media diagnostics, actual-server privacy regression coverage.
- `acb7c51`: deterministic pool-state observation and direct Uvicorn log capture.
- `736b66b`: R2 explicit per-draft UUIDs, coordinated durable journal bindings,
  distinct identical drafts, browser locking/fresh reads and fail-closed behavior.
  Also completes R1 lifecycle wiring: guarded login differs from refresh, Web
  account-change events invalidate sessions, prior-account drafts are cleared and
  late asynchronous results are ignored.

Credential and journal failures after a potentially committed request preserve
the original ID and uncertain state. Saved bindings never contain tokens, draft
text or images. A completed binding is retained for delayed/recreated callers.
Caller APIs require the original ID for a retry; fingerprints validate content
rather than selecting a logical draft.

## Executed validation

| Check | Final result |
|---|---|
| Full backend suite, Python 3.13, disposable PostgreSQL/PostGIS | **628 passed, 2 skipped** |
| Focused publication idempotency, ambiguous commits, pool and privacy | **44 passed** |
| Full Flutter VM suite | **601 passed, 4 skipped** |
| Chrome publication coordination/session checks | **3 passed** |
| Ruff, application and publication regression files | Passed |
| Flutter analysis, whole frontend | No issues |
| Migration graph static verification | One head, no duplicate revisions or missing parents |
| Whitespace checks | Passed |

The Chrome cases verify: external account-change cancellation; an exclusive lock
held by another same-origin browsing context together with fresh preferences
visibility; and blocking without Web Locks before any request. The mock-client
cases additionally cover independent concurrent clients, recreation with the same
ID, unrelated identical drafts, changed-payload rejection, account isolation,
refresh/replay transitions and credential-store failure after server success.

The 16 server privacy cases use local Uvicorn sockets and capture application
output, stderr and `uvicorn.error`. Synthetic markers represent post text,
filenames, contact data and credentials. Coverage includes database/media errors,
three creation routes, three update routes, operation status, started responses
and a control proving unrelated errors retain their existing diagnostics.

The first broader backend run had 626 passes, 2 skips and two test failures.
The pool assertion sampled a connection before session closure; it now waits for
both all authentication queries and zero checked-out connections. A control test
relied on logger propagation changed by earlier tests; it now attaches its capture
handler directly to Uvicorn. The focused rerun and full rerun both passed.

## Isolation and browser-runner qualification

Backend tests used uniquely labelled, disposable containers, an internal Docker
network, no published ports, a tmpfs database, read-only source mounts and mock
storage. Test dependencies were copied between owned containers from cached
images; no shared service was rebuilt or changed. Ownership and network membership
were checked before cleanup.

Flutter 3.44.8's Windows browser test runner returned 404 for local CanvasKit paths
and mishandled nested entry-test paths. The permanent browser entry test lives at
the test root. For local validation only, a temporary CDP helper fulfilled that
owned test browser's CanvasKit requests using read-only SDK cache files. The SDK,
shared configuration and application settings were not modified. Normal browser
test command on a working runner:
`flutter test --no-pub --platform chrome test/publication_coordination_web_test.dart`.

These browser cases are not a two-full-app-tabs/live-API end-to-end test. Signed
Android device runs, other browser families, real app-process termination, live R2,
production networks and production infrastructure were not tested here.

## Migration, compatibility and remaining conditions

The correction commits add no migration and change neither 0029 nor 0030.
Static graph verification confirms
`20261029_0028 -> 20261101_0029 -> 20261102_0030`.
The original isolated live upgrade/downgrade checks remain previous evidence;
production revision is unverified. The previously reported global Alembic drift
was not changed or claimed resolved.

Existing installed Android clients keep the optional-key server contract and its
legacy duplicate risk. New source callers must carry an explicit draft ID.
Native single-engine coordination and browser Web Locks/fresh reads are documented
in `PUBLICATION_RELIABILITY.md`. No complete saved-draft restoration/selection UI
was introduced; recovery after process death requires the retained ID and payload.
Browser storage clearing or losing that ID removes local recovery context.

R4 is documented in `PUBLICATION_ROLLOUT.md`, with two mock transport tests. Mixed
nodes can still duplicate an old-node commit because its ledger record is absent.
No capability-gate code or production-script change was implemented. Do not enable
updated clients until every serving backend supports idempotency; preserve the
ledger and a compatible handler throughout rollback. If operational gating cannot
be enforced, a protocol/routing capability boundary requires separate approval.
The startup command's automatic `alembic upgrade head` must not bypass approval
for any pending Batch 1 migration.

R5's unbounded manifests/client bindings and best-effort orphan cleanup remain
documented follow-ups. No automatic deletion or retention policy was introduced.
The original real-device/SGP1 root cause remains unproven.

## Files changed by the correction work

- `backend/app/api/v1/uploads.py`
- `backend/app/core/publication_diagnostics.py`
- `backend/app/infrastructure/storage/service.py`
- `backend/tests/test_publication_connection_lifecycle.py`
- `backend/tests/test_publication_log_privacy.py`
- `docs/PUBLICATION_R123_VALIDATION.md`
- `docs/PUBLICATION_RELIABILITY.md`
- `docs/PUBLICATION_ROLLOUT.md`
- `frontend/lib/core/media/selected_image_pipeline.dart`
- `frontend/lib/core/network/api_client.dart`
- `frontend/lib/core/network/mushukistan_api.dart`
- `frontend/lib/core/network/publication_lock_stub.dart`
- `frontend/lib/core/network/publication_lock_web.dart`
- `frontend/lib/core/network/publication_retry.dart`
- `frontend/lib/core/network/publication_session.dart`
- `frontend/lib/core/storage/token_store.dart`
- `frontend/lib/core/storage/token_store_factory_web.dart`
- `frontend/lib/core/storage/token_store_provider.dart`
- `frontend/lib/features/add_observation/application/add_observation_controller.dart`
- `frontend/lib/features/add_observation/presentation/screens/add_observation_details_screen.dart`
- `frontend/lib/features/adoption_posts/presentation/screens/adoption_post_create_screen.dart`
- `frontend/lib/features/auth/infrastructure/auth_repository_impl.dart`
- `frontend/lib/features/lost_pets/presentation/screens/lost_pet_create_screen.dart`
- `frontend/pubspec.lock`
- `frontend/pubspec.yaml`
- `frontend/test/core/network/api_client_multipart_test.dart`
- `frontend/test/core/network/post_mutation_test.dart`
- `frontend/test/core/network/publication_retry_test.dart`
- `frontend/test/core/network/publication_rollout_test.dart`
- `frontend/test/core/network/publication_session_test.dart`
- `frontend/test/features/add_observation/publication_outcome_screen_test.dart`
- `frontend/test/live_backend_smoke_test.dart`
- `frontend/test/publication_coordination_web_test.dart`
- `frontend/test/support/fakes.dart`
