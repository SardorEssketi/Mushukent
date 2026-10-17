# User Blocking

Status: implemented on branch `fix/user-blocking` (resolves audit finding F-01).

## Decision

Before this change a block was stored in `user_blocks` and nothing else read it, so blocking looked like protection but changed nothing. Blocking is now enforced **on the server, in the query layer**, with one shared rule. The Flutter client does not filter anything itself; it only reloads data after a block change.

### Rule

A block between two users is **symmetric in effect**. If a row exists in `user_blocks` in either direction, then for those two users:

1. **Content is invisible both ways.** Neither user sees the other's observations, lost-pet posts, adoption posts or comments in the feed, map, lists, cat pages, comment threads, user activity lists or notifications.
2. **Interaction is rejected as "not found".** Commenting, replying, liking and "Contact owner" against the other user's content return the same 404 as a missing item (`POST_NOT_FOUND`, `LOST_PET_NOT_FOUND`, `ADOPTION_POST_NOT_FOUND`, `COMMENT_NOT_FOUND`, `LOST_PET_NOT_ACTIVE`, `ADOPTION_POST_NOT_ACTIVE`). A blocked user is not told that they are blocked.
3. **No notifications.** A comment/reply notification, its push job and nearby-lost-pet alerts are not created between blocked users. Notifications that already exist are hidden (and not counted as unread) while the block exists. A push that was queued before the block is cancelled by the worker at delivery time.

Directionality: *who* blocked is stored (`blocker_id` -> `blocked_id`) so only the blocker can remove the block and sees it in their blocked list. Visibility and interaction rules do not depend on the direction. If both users block each other, both rows must be removed before content is visible again.

### What is deliberately not affected

- **Anonymous visitors and third parties** see everyone's content. Blocking one person never changes what other users see.
- **Public profiles** stay reachable (`GET /users/{id}`), because the blocker needs a place to unblock, and the profile now says whether the viewer has blocked that user (`is_blocked_by_viewer`). Their post and comment *lists* are empty for the blocked pair.
- **Own content**: editing and deleting your own posts is unchanged. Retracting a like (`DELETE /posts/{id}/likes`) stays allowed so old likes can be removed.
- **Moderation** is unaffected: moderator routes do not apply block filters.
- **Reports** against a user's content use their own read path and are not filtered.
- **Existing data is kept.** Blocking never deletes likes, comments or notifications, so unblocking restores everything. Counters (`like_count`, `comment_count`) are global and still include a blocked user's contributions.
- **Aggregates not tied to a viewer** (leaderboards, `GET /places`, cat records in non-map list views) are not filtered. Map pins and cat observation histories are filtered because they expose individual observations.
- **Replies to a hidden comment** from third parties stay visible (they are the third party's content); the client already renders a reply with a missing parent as a top-level comment.
- Account deletion still removes block rows in both directions (unchanged).

### Where the rule lives

`backend/app/infrastructure/repositories/blocking.py` provides `blocked_between`, `exclude_blocked` (SQL predicate, used in WHERE clauses so pagination stays correct) and `users_are_blocked` (single check used before writes). Read paths call `exclude_blocked` with the viewer id; write paths either use the same filter when loading the target (posts, likes) or call `users_are_blocked` (lost-pet/adoption comments and contact, replies, notification creation, worker delivery).

Because enforcement is on every read, a race between a block and an in-flight interaction is harmless: anything written just before the block commits is hidden by the read-time filter, and the worker re-checks blocks before sending a push. Duplicate or concurrent block requests collapse into one row (`INSERT ... ON CONFLICT DO NOTHING` on the unique `(blocker_id, blocked_id)`).

Public read endpoints that now apply the filter accept an optional access token (`/feed`, `/posts/{id}`, comment lists, `/lost-pets`, `/lost-pets/map`, `/lost-pets/{id}`, `/adoption-posts`, `/adoption-posts/{id}`, `/cats`, `/cats/{id}`, `/cats/{id}/posts`, `/users/{id}`, `/users/{id}/posts`, `/users/{id}/comments`). Without a token they behave exactly as before. As with `/feed` before, an invalid token on these routes now returns 401 so the client refreshes it.

### Query cost (measured)

On a disposable PostGIS database with 200,000 posts, 600,000 comments and a viewer with 100 block relations, through the real repository code: recent feed 8.9 ms -> 10.4 ms, popular feed 143.6 ms -> 143.4 ms (its existing sequential scan dominates), mixed feed key query 68 ms -> 80 ms. The two directions are two separate `NOT EXISTS` conditions because that planned as index-friendly anti joins (about 35 ms in a raw-SQL test), while `NOT (a OR b)` and an `OR` inside one subquery planned as per-row subplans (150-240 ms).

## API

| Method | Path | Behaviour |
|---|---|---|
| POST | `/users/{id}/block` | Idempotent (204 on repeat). 404 for unknown/inactive user, 422 for self |
| DELETE | `/users/{id}/block` | Idempotent (204 even when no block exists). Only removes the caller's own block |
| GET | `/users/me/blocks` | Caller's blocks, newest first: `id`, `name`, `avatar_url`, `blocked_at` |
| GET | `/users/{id}` | Adds `is_blocked_by_viewer` (false for anonymous viewers) |

## Client

- Profile overflow menu offers Block or Unblock depending on `is_blocked_by_viewer`; both show a snackbar and failures show "Could not update the block".
- Settings > Blocked users lists blocked accounts with an Unblock button.
- After any change the client bumps `postMutationRevisionProvider` (feed, map, post, profile and activity providers reload) and refreshes the unread-notification badge.
- Public reads that the server filters are sent with the viewer's token (previously several were explicitly anonymous).

## Known limits

- Counters include hidden interactions (see above).
- Android behaviour was not exercised; the code is shared with Flutter Web.
- A comment or like written in the instant before a block commits is stored but hidden; it is not deleted.
