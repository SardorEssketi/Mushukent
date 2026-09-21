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
- Comment deletion cascades to replies through the database foreign key.
