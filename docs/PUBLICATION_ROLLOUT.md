# Publication protocol rollout and rollback

This is a reviewable handoff plan, not deployment authorization. Claude owns
Batch 1, revision 0029 and release preparation. No infrastructure scripts or
configuration were changed for the publication corrections.

## Preconditions and backend-first order

1. Obtain the actual production Alembic revision through the authorized release
   owner. Do not infer it from local main, image tags or older deployment reports.
2. Confirm Batch 1 approval and the reviewed chain:
   `20261029_0028 -> 20261101_0029 -> 20261102_0030`. Recheck for additional heads
   after Claude finishes; never silently renumber or reparent migrations.
3. Resolve or explicitly disposition the pre-existing global Alembic drift.
   Validate the reviewed upgrade from the actual starting revision in an isolated
   copy, including 0029's dependencies and relevant retained data.
4. Arrange a consistent backup that includes both publications and operation
   records. Plan normal DDL locking and an approved migration window/timeout.
5. Apply approved migrations through 0030 before serving keyed requests. The new
   table is additive; do not backfill invented keys for older posts.
6. Deploy the reviewed idempotent backend to every serving instance and drain all
   old instances before enabling the updated Flutter client. Keep the client
   release gated until the complete serving fleet is verified.

Important: `backend/Dockerfile` runs `alembic upgrade head` before Uvicorn. Starting
the image can apply **all** missing revisions, including Batch 1's 0029. Do not
start it as an indirect way to apply unapproved production migrations.

## Verify every serving instance

- Enumerate the actual load-balancer/proxy upstreams, replicas, alternate API
  routes and any cached/fallback backends. One successful request through the
  public hostname does not establish fleet consistency.
- Verify each instance's immutable image digest/reviewed revision and startup
  configuration. Confirm its publication handlers and status route come from
  the approved build, not merely that the route exists somewhere.
- Confirm the shared database is at approved 0030 and its operation PK, FK and
  checks match the reviewed migration. Test-account operation status for a fresh
  random UUID must return authenticated 404 `PUBLICATION_OPERATION_NOT_FOUND`
  from each serving instance. Do not print credentials or owner content.
- In an approved isolated/staging environment, publish all four types with the
  same-key replay and lost-response scenarios across different serving instances.
  Verify one publication, unchanged committed media, and completed status.
- Verify Web CORS permits the request headers, supported browsers supply Web
  Locks, and unsupported browsers block before upload. Validate request IDs and
  synthetic-marker log privacy at the real server entry point.
- Release the updated client only after the fleet gate is signed off. No
  production test publications are authorized by this document.

## Mixed-version hazard and scope boundary

An old node can ignore `Idempotency-Key`, commit a publication and lose its
response. A new node then returns operation-not-found because the old node did
not write a ledger row. Resending the original key creates a second publication.
The same problem occurs when unsupported rollback is followed by restoration of
the new backend. The client cannot infer that an absent ledger means an old node
did not commit a post.

`publication_rollout_test.dart` models this contract and deliberately demonstrates
the two accepted POSTs. A second test verifies that a backend lacking the status
route blocks an outstanding retry until supported service returns. These are mock
transport tests, not proof of a production load-balancer topology.

No rollout capability endpoint or production gate was implemented under R1-R3.
If fleet uniformity cannot be verified operationally, the proposed separate code
correction is an enforced protocol-capability gate/routing boundary for **all**
keyed creation and recovery traffic, including rollback. A client-only capability
probe is insufficient if a subsequent request can reach an old node. This needs
separate scope/architecture approval; abort rollout until an enforceable gate exists.

## Application rollback and outstanding operations

- Keep 0030 and its operation ledger. Never run its downgrade as part of an
  application rollback: dropping the table destroys retry mappings while posts
  remain, allowing duplicate creation after re-upgrade.
- Keep a reviewed compatible publication handler available for updated clients.
  If the rest of the application is rolled back, their POST/status/detail traffic
  must still reach an idempotent implementation against the same database.
- If no compatible handler is available, stop publication writes using an approved
  maintenance mechanism until compatible service is restored. Do not send new
  keyed operations to a legacy implementation or advertise rollback as safe.
- Completed operations continue to resolve to existing posts. Pending operations
  remain pending; after lease expiry only a supported handler may take over with
  fencing. Failed operations reuse their original key. Never clear records to
  unblock a client, invent new IDs for uncertain attempts, or delete their media.
- A missing status route produces an uncertain client outcome and no blind retry.
  That fail-closed behavior does not make new publications on old nodes safe.
- Restore publication rows and their ledger consistently after database recovery.
  Keep API namespace/base URI stable for retained client bindings, or coordinate
  an explicit recovery plan before changing them.

## Verification and abort checklist

Before enabling clients, require all of the following:

- [ ] Actual production revision and every pending migration approved.
- [ ] Batch 1 complete; one compatible migration chain.
- [ ] Consistent backup and approved migration/rollback plan.
- [ ] Every serving backend has verified idempotency support; legacy nodes drained.
- [ ] Cross-instance replay, uncertain commit, media and session-transition tests pass.
- [ ] Web lock/storage tests and unsupported-browser blocking pass.
- [ ] Server/application logs contain no synthetic private markers.
- [ ] A compatible handler is available throughout rollback and recovery.
- [ ] Operators have an agreed baseline and abort thresholds for API failures,
      response duration, pool waits, database load and storage failures.

Abort or keep clients gated if any item is unresolved, topology/version evidence
is incomplete, a node ignores keys, the ledger is unavailable, private markers
appear, or publication/status recovery fails. Do not fall back to keyless POSTs,
drop the ledger, change DNS/proxy settings, or prune uncertain media to recover.

## R5: retention and orphan reconciliation

R5 remains a MEDIUM follow-up, not implemented here. Server operation manifests
grow with retries, and client bindings are retained after success. Monitor their
size and age; define a bounded, audited retention/reconciliation policy. Compact
only verified retired attempt metadata while preserving operation-to-publication
deduplication mappings. Before deleting any object, establish that its attempt has
stopped and check all live references. Expiry alone is insufficient. No automatic
sweeper or production cleanup is part of this branch.
