# Architecture Decision Records

## ADR-0016: Automatic cat records and nested comment replies

- Status: Accepted
- Date: 2026-09-14

### Context

The observation concept no longer includes manual nearby-cat matching or an
existing-cat/new-cat choice. Comments also need to support direct replies and
deeper conversation threads.

### Decision

- A new observation without a legacy `cat_id` or `new_cat` reference creates an
  unnamed `unknown` cat in the same transaction as the post.
- The mobile observation flow does not expose cat matching or nearby-cat
  suggestions. Optional naming of the automatically created cat is specified
  by ADR-0019.
- Comments store an optional self-referencing `parent_comment_id`. The API
  returns a flat page with that relationship, and clients render unlimited
  nesting recursively.

### Consequences

- Existing legacy API clients may continue to provide `cat_id` or `new_cat`.
  Mobile clients omit `cat_id` and may provide `new_cat.name` only to name the
  automatically created cat; they do not select or match existing cats.
- Cat records remain available for grouping, map visibility, and future
  separately approved identification work.
- Physical comment cleanup cascades to replies through the database foreign key;
  user-facing deletion uses the later soft-delete decision below.

## ADR-0017: Author comment edit window and auditable soft deletion

- Status: Accepted
- Date: 2026-09-20

### Context

Comments are threaded, so removing rows would break reply relationships. The
product requires authors to edit only shortly after publication while allowing
authors to delete at any time and moderators to remove any comment.

### Decision

- Keep the existing comment soft-delete strategy. Active comment queries also
  exclude comments whose parent post or other target has been soft-deleted.
- Add `edited_at` and `deleted_by_id` to comments through migration
  `20260920_0018_comment_edit_delete`.
- Enforce a centrally configured `COMMENT_EDIT_WINDOW_MINUTES` (default 30)
  using the database clock. The exact boundary is exclusive: age `< 30`
  minutes is editable; age `>= 30` minutes is rejected.
- Only the comment author may edit. Moderators receive deletion authority from
  the existing trusted RBAC flag but never an edit override.

### Consequences

- Deleted comments retain their rows and reply relationships but are omitted
  from normal active comment responses. The deletion actor is retained until
  that account is removed, at which point the foreign key is nulled.
- Clients receive `edit_until` for menu visibility and `edited_at` for the
  indicator, but the backend remains authoritative for authorization.

## ADR-0018: Deterministic pagination for the mixed feed

- Status: Accepted
- Date: 2026-09-20

### Context

The feed merges observations, lost-pet posts, and adoption/rehoming posts. A
cursor from only one source cannot represent the position in that global stream
and can therefore duplicate or skip records across pages.

### Decision

- Build one database-level key stream across all item types before pagination.
- For `recent`, order by `(created_at desc, item-type rank desc, id desc)`.
- For `nearby`, order geolocated observations and lost-pet posts by
  `(distance asc, created_at desc, item-type rank desc, id desc)`; adoption
  posts are excluded because they have no location.
- Return an opaque versioned cursor containing the complete last sort key,
  filter, and (for nearby) the normalized search scope.
- Apply a strict tuple boundary and batch-hydrate the selected source records
  while reconstructing the global order.

### Consequences

- Equal timestamps and equal distances paginate deterministically.
- A cursor cannot be reused under a different filter or nearby scope.
- Cursor internals are an API implementation detail and may evolve by version;
  clients only persist and return the opaque value.

## ADR-0019: Optional cat names on observations

- Status: Accepted
- Date: 2026-09-26

### Context

Users sometimes know the name of the cat in an observation. The existing flow
automatically creates one cat record per observation and intentionally has no
cat matching or existing-cat selection.

### Decision

- Add an optional cat-name field to the shared observation details form,
  including Needs help posts.
- Send a nonblank name for the newly created cat record. A blank field omits
  the name and keeps the existing `Unknown` display behavior.
- Keep one automatically created cat record per observation. Do not add
  nearby-cat search, matching, or existing-cat selection.
- Limit the name to 100 characters, matching the existing API schema.

### Consequences

- No database migration is needed; cat names are already nullable and the
  observation API already accepts `new_cat.name`.
- Existing observations and blank-name submissions remain unnamed.

## ADR-0020: Bind missed passwordless Gmail records on verified sign-in

- Status: Superseded by ADR-0021
- Date: 2026-09-26

### Context

The Google-subject migration marks existing active, verified consumer Gmail
records as eligible for binding. A passwordless legacy Gmail record that was
not marked by that migration can otherwise be rejected even when Google has
verified the same email address.

### Decision

- On Google sign-in, allow a passwordless, unlinked record to bind to the
  verified Google subject when its address is `gmail.com` or `googlemail.com`,
  even when the migration marker is absent.
- Keep the existing authenticated-linking requirement for ordinary
  email/password accounts and for passwordless external-domain accounts.
- Continue to reject a Google subject that is already linked to another user.

### Consequences

- The fix requires no database migration and handles eligible Gmail records
  missed by the migration.
- External-domain legacy records still require an existing authenticated
  session or support-assisted verification.

## ADR-0021: Keep Google and password methods on one user with bounded auto-linking

- Status: Accepted
- Date: 2026-09-26

### Context

The `users` table already supports a nullable password hash and a unique nullable
Google subject on one row. The old login policy nevertheless rejected a Google
sign-in when a password account had the same verified email, while a separate
legacy Gmail exception allowed email matching. This split the account behavior
without requiring a different data model.

### Decision

- Keep one Mushukistan user row as the account; password hash and Google subject
  are independent sign-in methods. Use Google `sub` as the stable Google key.
- Automatically attach a new Google subject by email only when there is exactly
  one active matching row, Mushukistan already marks that email verified, and
  the verified Google address is consumer Gmail. Preserve the password hash and
  all user-owned data on that row.
- Require an authenticated Account Security link for Workspace and other
  external-domain email matches, and for unverified password accounts. Never
  merge two user rows by email.
- Treat a Google email as Mushukistan-verified only for an authoritative Gmail
  or verified hosted-domain claim. A non-hosted external email may still sign
  in through its `sub`, but it must pass Mushukistan email verification before
  password login.
- Preserve stable refresh-token sliding renewal per the existing MVP session
  policy. Do not add an unlink operation until an account-safe recovery flow is
  designed; currently Google cannot be disconnected.

### Consequences

- No identity-table rewrite is needed. An additive functional unique index
  prevents case/whitespace email duplicates; the migration refuses to proceed
  when legacy collisions exist and does not alter or merge records.
- Existing verified password accounts can use both password and Google sign-in
  when the conservative Gmail match rule applies. Workspace/external users keep
  their existing account and can link after authenticating to it.
- Adding a password to a Google account requires a fresh server-verified
  Google ID token matching the current account.
