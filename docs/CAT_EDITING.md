# Cat record editing

Status: implemented on branch `fix/release-readiness` (audit finding F-14).

## Intended model

`docs/PRD.md`: cat records are internal grouping entities for observation links, map markers, status and counters; there are no cat profile pages and the Flutter client never edits a cat (it has no call to `PATCH /cats/{id}`). Observation creation makes the cat record automatically. `docs/API.md` said normal users "can suggest" and that non-sensitive fields were open in the MVP, which is not a collaborative editing feature that the product uses. Nothing in the documentation describes community co-editing of names, locations or cover photos.

## Policy implemented

- `PATCH /cats/{id}`: only the user who created the record (`created_by`) or a moderator. Anyone else gets 403 `FORBIDDEN`. A cat whose creator account was deleted (`created_by` is null) is editable by moderators only.
- `status` and `merged_into` stay moderator-only, as before, including for the creator.
- `cover_photo_url` (on create and on update, for everyone including moderators) must point at the platform's own media storage (`MediaStorageService.owns_url`: same host as the configured storage and a known media path). Anything else returns 422 `VALIDATION_ERROR` with `details.cover_photo_url = ["must_be_platform_media_url"]`. Clients that want a cover photo upload the file instead.

## Correction to the audit

The audit reported that a non-owner setting an external `cover_photo_url` on `PATCH` succeeded. The request returned 200, but the update path never applied the URL (only an uploaded file changes the cover), so no external URL could be stored through `PATCH`. The URL **could** be stored through `POST /cats` (create), which is why validation is applied there as well.

## Not changed (flag)

`POST /posts` in JSON mode accepts an arbitrary external `photo_url` (`PostCreateJSONRequest`). The mobile and web clients use multipart uploads, so this is an API-only path, but it has the same hotlinking concern as the cat cover URL. Left untouched because many existing tests and any scripted API clients may use it; **Decision needed**: apply the same platform-URL rule there.

## Tests

`backend/tests/test_cat_editing_policy.py`: non-owner, anonymous, creator, moderator, orphaned cat, status/merge, external and look-alike cover URLs, platform URLs.
