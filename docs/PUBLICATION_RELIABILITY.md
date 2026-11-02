# Publication reliability

This protocol extends the synchronous MVP upload flow. It does not change DNS,
Nginx, Cloudflare, background processing or Batch 1 moderation behavior.

## Publication operations

Migration `20261102_0030` adds `publication_operations` after the unchanged
`20261101_0029`. Apply it before enabling the new client. Older clients can keep
omitting `Idempotency-Key`; their requests retain the existing creation contract,
but cannot receive retry deduplication guarantees.

All three creation endpoints accept an optional UUID `Idempotency-Key`. Keys are
scoped to the authenticated account. A fingerprint covers the normalized request,
post type, image order, MIME types and image bytes, excluding transport filenames.
The same key with different content returns 409 `PUBLICATION_KEY_CONFLICT`.

A short transaction reserves an operation and a fixed publication UUID. Image
processing and storage occur without holding its database connection. An active
reservation returns 409 `PUBLICATION_IN_PROGRESS`; failed operations can retry.
An abandoned reservation can be claimed after 15 minutes. Each attempt has a new
owner token, checked under row lock before publication writes. An older attempt
cannot commit after takeover. The publication and completed operation state commit
in the same transaction, including Lost Pet notification records.

Completed POST replays read the existing publication without additional R2 writes.
Deleted publications are not recreated by replay. There is no automatic key expiry
that could turn an old retry into another post. Account deletion cascades its
operation records. Operators must review retention before any future pruning.

`GET /api/v1/publication-operations/{key}` is authenticated and owner-scoped. It
returns `state` (`pending`, `failed`, `completed`), `target_kind`, `target_id`,
`can_retry`, and `retry_after_seconds`. It never exposes fingerprints or media
manifests. Other accounts and absent operations receive 404
`PUBLICATION_OPERATION_NOT_FOUND`. Status checks use the ordinary thread pool,
so they do not queue behind the two long-running upload-processing slots.

## Uncertain outcomes and media

A commit exception is conservatively unknown. Publication create/update preserves
media and returns 503 `PUBLICATION_OUTCOME_UNKNOWN`. For keyed creation, a fresh
read first attempts to reconcile a completed transaction and return its result.
If reconciliation is unavailable, retain the reservation and media; never infer
rollback from a disconnected connection. Session-close failures after commit are
logged without inviting a duplicate submission.

Intended object keys are journaled before PUT for keyed creation. A failed PUT
attempts deletion of its unique key, including when only its acknowledgement was
lost. Cleanup remains best effort. Failed deletes and crashes can leave objects;
the manifest retains attempted keys and owner tokens for an audited reconciliation.
There is no automatic orphan sweeper. Before manual deletion, establish publication
references and attempt termination; a lease expiring alone does not establish that
an earlier remote PUT has stopped. Do not remove committed objects or blindly delete
every key in a completed operation's manifest.

## Client recovery

The caller creates a UUID for each explicit new draft and passes it as
`publicationId` through the three creation APIs. It is the server operation key;
content fingerprints validate its binding and never allocate or select identities.
Two unrelated drafts with identical content have different UUIDs. Missing IDs are
rejected before transport. The journal binds each ID to a hashed account owner and
request fingerprint before sending; no tokens, text or images are persisted there.
Completed bindings remain saved so a delayed caller cannot allocate a replacement.
Completion observed during reconciliation is saved in the existing journal as an
optional `completed_target_id`, bound to the same account hash and fingerprint.
Old journal records without that field remain readable. Once saved, recovery can
only read that target; even a later missing operation/status response cannot
permit another creation POST. No draft text, photos, tokens or moderation details
are added to storage.

A completed operation whose detail is definitively rejected (including 403/404,
or authentication/validation rejection after refresh) produces the distinct terminal
`PublicationCompletedUnavailable` result (`PUBLICATION_COMPLETED_UNAVAILABLE`).
It is authoritative evidence of an earlier creation, not validation rejection or
an uncertain creation. The UI retains the operation ID, locks that draft, disables
submission and displays neutral "already published, cannot be opened here" copy.
Queued callbacks are guarded too. The message does not identify moderation actions.
An explicit new draft through the Create flow is required for another publication;
no terminal recovery action silently allocates a replacement ID. Account transitions
clear prior-account terminal state. Temporary detail/storage failures retain the
original identity and fail closed; unavailable status still never authorizes POST.

A retry first checks
status: completed operations load the existing publication, active ones wait, and
only absent, failed or expired operations may resend with the original key. A failed
status lookup never causes a blind POST. Token-refresh replay preserves the key.
Client recreation can recover by supplying the same ID, account and exact payload.
Automatic fingerprint matching after process death has been removed: it could
conflate unrelated drafts. Full draft restoration and a saved-draft selection UI
are not implemented; a new draft is a new intent, not recovery of an unidentified
old operation. Do not reconstruct a retry with a new ID.

Android's single-engine application serializes journal work across all client and
journal instances using a shared process-isolate coordinator. The UUID remains the
operation key across engine/process boundaries; server uniqueness remains the last
line of defense. Multiple independent native engines do not share the in-process
lock and must carry the original ID rather than allocate a replacement.

Web uses exclusive same-origin Web Locks across tabs and fresh SharedPreferences
reloads while holding that lock. It never substitutes a localStorage lease or
instance-local mutex. Browsers without Web Locks fail closed before any journal
binding or network request. Storage failures also block transport. Browser storage
clearing, reinstalling the app, or losing a draft ID removes local recovery context;
the server ledger remains authoritative for retained IDs.

Each call binds to the authenticated account and a session epoch. Dispatch pins a
freshly validated token and prevents the ordinary interceptor from replacing it.
Login/logout changes the epoch and cancels outstanding requests; same-account token
refresh preserves it. Status reads, detail reads and refresh replay use the same
binding. Web account-change storage events invalidate other tabs' sessions. Creation
screens clear prior-account drafts and ignore late picker, location and API results.
Cancellation cannot undo a request already received or committed by the server;
retain its ID for recovery under its original account.

Local credential/journal failures and unexpected client exceptions remain uncertain;
they must not cause a new operation key to be generated. Only a definite creation
rejection allows the UI to start a replacement attempt when the user corrects its
content.
Completed-but-unavailable recovery explicitly forbids replacement.

Creation screens distinguish uncertain outcomes and offer **Check publication
status**, retaining form contents and locking edits while uncertain. Draft text and
image bytes remain in memory on that screen; full draft restoration after process
death is not implemented. Reselecting identical content can recover using the
original retained ID. Different content requires an explicit new draft/attempt.
Avatar/edit transports
are not automatically replayed by the creation protocol.

## Diagnostics and validation

Valid UUID `X-Request-ID` values are accepted, otherwise generated, and returned on
publication responses. FastAPI logs correlate request completion, upload queue
wait, bounded file byte counts, media timing, operation outcomes and commit errors.
Client transport diagnostics retain exception type/cause type without printing
tokens, URLs, filenames, content or account IDs. Nginx correlation is a separate
owner-coordinated infrastructure task; no Nginx configuration is changed here.

The publication ASGI boundary catches unexpected create/update/status exceptions
before Starlette can rethrow their private messages to Uvicorn. It returns a
sanitized error envelope with request ID. If response bytes have already started,
it raises only a sanitized replacement exception, suppressing the private chain.
Unrelated endpoints retain their original exception diagnostics. Unexpected media
errors and client-provided MIME values are also sanitized before application logging.

Use only dedicated disposable databases: integration fixtures truncate all tables.
Use mock storage, strip service credentials, and disable external network access.
Cover concurrent replay, lost HTTP responses and commit acknowledgements, payload
conflicts, account boundaries, stale-attempt fencing, ambiguous PUT and deletion
failures, pool saturation, and Batch 1 moderation/comment behavior. Test the new
migration after 0029 and rollback only inside an explicitly disposable database.

The original real-device failure remains unproven. Direct/proxy HTTPS comparisons
and SGP1 diagnostics require a separate controlled investigation; ICMP loss is not
proof of application-level loss. No route or production changes are authorized by
this document.

## Local implementation validation — 2026-11-02

Baseline: `8c273a877cebdf02ee8dbf7b130f91cd3a8dfce3`; branch
`fix/publication-reliability`; worktree
`D:/Data science/mushukent-publication-reliability`. The shared main worktree
remained clean at the baseline during implementation. No Batch 1 changes were
integrated, and migration 0029, comment counting, feed behavior and moderator
deletion implementations were not modified.

Validation used owned containers with a private internal Docker network, no
published ports, a disposable tmpfs PostgreSQL/PostGIS database, read-only source
mounts and mock object storage. No shared development or production database,
R2 bucket or service was used. Container ownership was checked before cleanup.

- Full backend suite: **604 passed, 2 skipped**. This includes existing comment,
  moderation, authentication and feed regressions.
- Final publication idempotency suite: **21 passed**, including eight additional
  cases added after the full run: deleted-publication replay and lost update
  commit acknowledgements for all four post types.
- Full Flutter suite: **579 passed, 4 skipped**; `flutter analyze --no-pub`:
  no issues. New tests cover client recreation, unavailable status, pending
  operations, key reuse, account separation, single-flight submission, journal
  failures, token-refresh key preservation and retained in-screen drafts.
- Ruff checks pass for application code and changed publication tests.
- All migrations upgraded successfully through 0030 in a second disposable
  database. Downgrade to 0029 and re-upgrade succeeded; 0029's special-post
  deletion columns remained present. Comparing only the new table with its ORM
  model found no differences.
- Global `alembic check` did **not** pass: it reports existing drift involving
  PostGIS `spatial_ref_sys`, cat observation timestamp types and the normalized
  email expression index. Those definitions were not changed here. This remains
  an integration/release review item, separate from the new table's validation.

The timeout regressions run an actual local Uvicorn HTTP listener, delay mock
storage, force the client to time out, then query status and replay the same key.
For regular, Needs Help, Lost Pet and Adoption, one publication and one pair of
media objects remain. A separate 15-request gated-storage test confirms that
authentication connections have returned to the pool while uploads wait.

No physical-device, mobile-data, Wi-Fi, live R2 or production network tests were
performed during this implementation. The fixes address demonstrated application
defects; they do not establish the root cause of the original device failure.
Text-only publication remains subject to the existing photo requirements.

## Integration and remaining work

Integration requires separate authorization. Review and apply 0030 in the
approved deployment process, release the server and status endpoint before the
new Flutter client, and repeat real-device recovery checks. Legacy requests
without a key remain susceptible to duplicate creation. Updates preserve media
on an uncertain commit but do not gain creation-style idempotency or a separate
update operation-status endpoint.

See `PUBLICATION_ROLLOUT.md` for the mandatory fleet capability gate, migration
prerequisites, outstanding-operation handling, rollback and abort checklist.

Full draft restoration after process death, automatic orphan reconciliation and
Nginx correlation are deliberately separate work. Reconciliation must establish
that an old attempt has stopped and check all live references before deleting
manifest objects; operation expiry alone is insufficient.

For network investigation, use an approved disposable HTTPS upload sink on both
routes, with equivalent application handling, bounded payload sizes and unique
request IDs. Alternate direct/proxy samples from the same device on Wi-Fi and
mobile data, recording DNS/connect/TLS/send/first-byte/total duration, HTTP status
and transport failure type. Correlate client IDs with Nginx arrival/upstream
timings, FastAPI stages, host load, DB pool waits and provider diagnostics at the
same timestamps. A browser GET or ICMP loss measurement is insufficient to
attribute multipart upload failures to SGP1. No DNS, proxy or server changes are
part of this branch.

## Completed-but-unavailable correction validation (2026-11-02)

Starting publication commit: `c111c92a7f592c8abf0b88256920ef6db926f46a`.
The integration candidate and shared main were not modified. No server runtime,
migration, deployment script or shared configuration changed for this correction.

The original eight four-type 403/404 cases failed before the correction and passed
after it. Permanent coverage now includes 26 network recovery cases, eight screen
cases and four additional real-socket/backend moderator-removal cases. Tests cover
lost responses, authoritative completion, inaccessible detail, 401/422 after
completion, client/journal recreation, repeated and queued interactions, retained
identity, no second POST, status/detail/storage outages, neutral messages, account
isolation, session transitions, and genuine validation correction. Backend socket
cases also assert one publication, retained media and one removal notification.

Executed validation for this correction:

- Focused Flutter recovery/retry/session/screen regressions: **61 passed**.
- Full Flutter VM suite after the final recovery guard: **635 passed, 4 skipped**.
- Chrome coordination/session checks: **3 passed** using the previously documented
  Windows runner workaround with read-only cached SDK assets. This was an owned
  browser against this publication worktree, not the integration candidate.
- Isolated backend publication, commit-outcome, pool, diagnostics/privacy,
  authentication and moderator-deletion regressions: **147 passed**.
- Flutter analysis: no issues. Ruff on the changed backend test and whitespace
  checks passed. A test-fixture brace lint and Windows encoding of the new
  localized copy were corrected; original localization content was verified
  unchanged, and screen regressions were checked again.

Backend tests used uniquely owned, CPU/memory-limited containers, an internal
network, no published ports or persistent volumes, tmpfs PostgreSQL/PostGIS,
read-only sources and mock media. The backend image's automatic migration/startup
command was overridden. Ownership was verified before removing these resources.
The full backend suite was not rerun: backend runtime and migration files are
unchanged; the targeted run includes previous publication/privacy guarantees.

No physical-device, live-R2 or two-full-app-tab end-to-end tests were performed.
Existing rollout gates, retention/orphan limitations, incomplete draft restoration
and unproven network causes remain as documented above. This correction closes the
completed-but-unavailable blocker; integration still requires a fresh separately
authorized preflight. No production or integration action is authorized here.
