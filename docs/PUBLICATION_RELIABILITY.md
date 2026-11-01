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

The client durably retains account-scoped operation keys and request fingerprints
in SharedPreferences before sending; no tokens, text or images are persisted there.
Concurrent identical calls in one client share one request. A retry first checks
status: completed operations load the existing publication, active ones wait, and
only absent, failed or expired operations may resend with the original key. A failed
status lookup never causes a blind POST. Token-refresh replay preserves the key.
Failure to clear an acknowledged journal entry cannot convert success into failure.

Creation screens distinguish uncertain outcomes and offer **Check publication
status**, retaining form contents and locking edits while uncertain. Draft text and
image bytes remain in memory on that screen; full draft restoration after process
death is not implemented. Reselecting identical content can recover using the
durable key. Different content is a new logical publication. Avatar/edit transports
are not automatically replayed by the creation protocol.

## Diagnostics and validation

Valid UUID `X-Request-ID` values are accepted, otherwise generated, and returned on
publication responses. FastAPI logs correlate request completion, upload queue
wait, bounded file byte counts, media timing, operation outcomes and commit errors.
Client transport diagnostics retain exception type/cause type without printing
tokens, URLs, filenames, content or account IDs. Nginx correlation is a separate
owner-coordinated infrastructure task; no Nginx configuration is changed here.

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
