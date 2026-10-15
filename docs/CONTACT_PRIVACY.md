# Owner contact privacy (lost-pet and adoption posts)

Status: implemented on branch `fix/release-readiness`. Policy values were approved by the project owner on 2026-10-15 (legacy-compatibility mode, 15 reveals per day and 40 per week, explicit consent for both post kinds, proposed wording). Wording in Russian and Uzbek still needs a native-speaker review. Legal texts (`legal_document_screen.dart`) still say the lost-pet phone is "public" and need a legal review.

## Rules
1. **Anonymous users, lists, feeds, maps, search, notifications and the owner's `mine` lists never contain `owner_phone_number` or `owner_telegram_username`.** They carry `contact_available` (boolean).
2. A signed-in user who is not the owner gets the contact only by calling `POST /lost-pets/{id}/contact-reveal` or `POST /adoption-posts/{id}/contact-reveal`.
3. Each user may reveal a limited number of **unique** posts in a rolling window. Revealing a post again is free. Over the limit: `429 CONTACT_REVEAL_LIMIT` with `Retry-After`.
4. The owner always sees their own contact on the detail response (needed by the edit form).
5. Blocked users, resolved or deleted posts, and posts without a usable phone cannot be revealed (404); owners cannot reveal their own post (403).
6. Reveals are recorded in `contact_reveals` (user, post kind and id, owner, mode, time). **No contact value is stored in that table or written to logs.**
7. Responses that can contain contact details are sent with `Cache-Control: private, no-store` and `Vary: Authorization`. nginx does not cache `/api` (`infrastructure/nginx/default.conf` has no `proxy_cache`).

## Configuration
| Variable | Default | Meaning |
|---|---|---|
| `CONTACT_REVEAL_MAX_PER_DAY` | 15 | unique posts per user in a rolling 24 hours |
| `CONTACT_REVEAL_MAX_PER_WEEK` | 40 | unique posts per user in a rolling 7 days |
| `CONTACT_REVEAL_MIN_ACCOUNT_AGE_HOURS` | 0 | accounts younger than this cannot reveal (0 = off) |
| `CONTACT_LEGACY_DETAIL_ENABLED` | true | compatibility mode for old app versions (below) |

Concurrent requests from one user are serialised with a per-user transaction lock, so parallel requests cannot exceed the quota (covered by a test).

## Compatibility with old app versions
Old clients send no `X-Contact-Mode` header and read the number from the detail response. For them, while `CONTACT_LEGACY_DETAIL_ENABLED=true`:
- a signed-in **non-owner** opening a detail page receives the contact **only if the same quota allows it**; that read is recorded as a reveal with `mode=legacy_detail`;
- over the quota the old client shows the post without the contact (no crash);
- anonymous users never receive it. No private number is exposed just for compatibility.

The new web/Android client sends `X-Contact-Mode: reveal` on every request, so detail responses never carry contacts for it, and it calls the reveal endpoint when the user taps Contact Owner. Guests are asked to sign in first (as before).

Cost of legacy mode: merely opening a detail page in an old app uses quota. Sunset: when the share of old versions is small, set `CONTACT_LEGACY_DETAIL_ENABLED=false` (old apps then lose Contact Owner, a deliberate end of support), optionally after showing a minimum-version prompt.

## Consent
Both create forms have an unchecked checkbox. Wording (English; Russian and Uzbek in `app_strings.dart`):
> Show my phone number (and Telegram, if I add it) to signed-in Mushukistan users who tap Contact Owner on this post.
> Each user can view only a limited number of contacts per day. It is never shown to visitors who are not signed in, or in lists or on the map.

- New clients (reveal mode) must send consent: lost pets via the existing `owner_phone_publication_consent` (required), adoption via the new `owner_contact_consent`. A missing or false value is rejected (`CONTACT_CONSENT_REQUIRED` for adoption).
- The server stores `contact_consent_version = 1` and `contact_consent_at` for posts created with the new wording; `NULL` means the original wording.
- Older clients that send no adoption consent keep working (as before, implicitly); an explicit `false` is always refused.
- Existing posts are not re-consented: the new policy is narrower than the "public" wording they accepted.

## Tests
`backend/tests/test_contact_privacy.py`, `test_contact_reveal.py` (reveal, idempotence, daily and weekly windows, parallel requests, account age, blocked/owner/resolved, legacy mode and its switch, leak scan over every parameterless GET route, no contact in logs or rows) and `test_contact_consent.py`; Flutter `contact_privacy_test.dart` and `adoption_lifecycle_screen_test.dart`.

## Still open
- Native-speaker review of Russian/Uzbek consent text; legal review of the privacy policy and terms wording.
- Tuning of the limits after real usage data.
- A per-account alert for repeated limit hits (log events `contact_reveal_limit_reached` exist).
