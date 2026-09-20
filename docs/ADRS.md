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
- The mobile observation flow does not expose cat matching, cat naming, or
  nearby-cat suggestions.
- Comments store an optional self-referencing `parent_comment_id`. The API
  returns a flat page with that relationship, and clients render unlimited
  nesting recursively.

### Consequences

- Existing legacy API clients may continue to provide `cat_id` or `new_cat`,
  but new clients should omit both for observations.
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
