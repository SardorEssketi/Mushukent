# Owner contact privacy (lost-pet and adoption posts)

Status: implemented on branch `fix/release-readiness`. Policy values were approved by the project owner on 2026-10-15 (legacy-compatibility mode, 15 reveals per day and 40 per week, explicit consent for both post kinds, proposed wording). The consent text and the legal documents (privacy policy, terms, in-app legal screen, web privacy page) were aligned with this behaviour on 2026-10-15. Russian and Uzbek wording still needs a native-speaker review and the legal text a legal review.

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
Old clients send no `X-Contact-Mode` header and read the number from the detail response, so **an old app may show the contact as soon as a post is opened**. While `CONTACT_LEGACY_DETAIL_ENABLED=true` (default):
- a signed-in **non-owner** who opens a detail page receives the contact **only if the same quota allows it**; that read is recorded as a reveal with `mode=legacy_detail` and counts as one unique post;
- over the quota the old client shows the post without the contact (no crash, no Contact Owner button for that post);
- anonymous users never receive it, and neither do lists, feeds, maps or notifications. No private number is exposed just for compatibility.

The new web/Android client sends `X-Contact-Mode: reveal` on every request, so detail responses never carry contacts for it, and it calls the reveal endpoint **after the user taps Contact Owner**. Guests are asked to sign in first.

Consequences of legacy mode: opening a detail page in an old app uses quota even if the user never calls; users therefore reach the daily limit sooner on old versions. Sunset: when the share of old versions is small, set `CONTACT_LEGACY_DETAIL_ENABLED=false` (old apps then lose Contact Owner, a deliberate end of support), optionally after showing a minimum-version prompt.

## Consent
Decision by the project owner on 2026-11-24: **the phone number in the profile is the consent.** The
create forms have no checkbox and no long explanation. Instead one line above Publish names what
will be shared (Russian, English and Uzbek in `app_strings.dart`, `contactNoticePhone` and
`contactNoticePhoneAndTelegram`):
> Only signed-in users will see your number +998 90 123 45 67.

(with "your number and Telegram" when the profile has a Telegram username).

- **A phone in the profile is still required** for both post kinds (`403 PHONE_NUMBER_REQUIRED`); the
  app asks the user to add one before opening the form. An empty profile phone is never consent.
- **The phone and Telegram are copied into the post when it is published.** Changing or removing
  them in the profile later does **not** change existing posts, in either direction: a post keeps
  the number it was published with until the owner edits the post (lost pets), resolves it or
  deletes it.
- What the server records in `contact_consent_version` / `contact_consent_at`:

  | Client sends | Result | Version |
  |---|---|---|
  | no consent field (current app, `X-Contact-Mode: reveal`) | created | `2` and the time |
  | `true` (older app with the checkbox, reveal mode) | created | `1` and the time |
  | `true` or nothing without the reveal header (oldest apps) | created | `NULL`, as before |
  | explicit `false` (an unticked checkbox in an older app) | `422` (`PHONE_PUBLICATION_CONSENT_REQUIRED` / `CONTACT_CONSENT_REQUIRED`) | - |

  Version 1 is the checkbox wording of 2026-10-15; `NULL` is the original wording.
- The consent field is optional on both endpoints, so an absent field must reach the service as
  `None`. That depends on the pinned FastAPI/Starlette (see the `DEPLOYMENT.md` note on dependency
  drift); `test_contact_consent.py` posts forms with the field truly missing.
- Existing posts are not re-consented.
- Release order: the backend must be live before a client without the checkbox, because an older
  server requires the lost-pet consent field.
- The legal documents describe this behaviour; their versions were not bumped (owner decision,
  2026-11-24), so nobody is asked to accept them again.

## Legal documents and acceptance versions
The Terms are version `2026-10-15` and the Privacy Policy is version `2026-10-30` (bumped for the post-view guest identifier, ADR-0024; documents, in-app screen, `/privacy` page) and the backend constants `CURRENT_TERMS_VERSION` / `CURRENT_PRIVACY_VERSION` (`backend/app/features/auth/application/schemas.py`) now equal them; `tests/test_legal_consistency.py` fails if they drift.

Behaviour (decided on 2026-10-15 because the contact policy, analytics and push disclosures changed):
- **Registration and Google account creation** record the current versions and time, as before, only with explicit consent.
- **Password and Google sign-in never fail because acceptance is outdated.** The user object (`login`, `google`, `refresh`, `users/me`) carries `legal_acceptance_required`, `current_terms_version`, `current_privacy_version`. Sign-in itself is not acceptance and records nothing. A Google sign-in that carries both consent flags records them.
- **New clients** route a signed-in user with `legal_acceptance_required` to `/legal-update`: an explanation, links to both documents, an **Accept and continue** button and **Logout**. Only the button calls `POST /auth/legal/accept` with `accept_terms`, `accept_privacy` and the two versions the client was told. The documents, the screen and logout stay reachable; everything else waits. The state is derived from the signed-in account, so switching accounts re-evaluates it.
- **The server** refuses acceptance unless both flags are true (422 `LEGAL_ACCEPTANCE_REQUIRED`) and the versions are the current ones (409 `LEGAL_VERSION_MISMATCH` with the current versions, so a stale screen cannot record text the user did not see). Repeating it keeps the original time. Sessions and refresh tokens are not touched.
- **Existing sessions** keep working; the flag appears on the next `users/me` or sign-in, which is when the app restores a session.
- **Old app versions** know nothing of the flag and are not interrupted; the server does not block write endpoints for unaccepted users because that would lock out every installed old app. Server-side enforcement on write endpoints is a possible later step once old versions are gone (**decision**).
- Accounts that were created before acceptance was recorded (null versions) are asked as well.

Implication: after this deploy, every existing user with a new app will see the acceptance screen once.

## Tests
`backend/tests/test_contact_privacy.py`, `test_contact_reveal.py` (reveal, idempotence, daily and weekly windows, parallel requests, account age, blocked/owner/resolved, legacy mode and its switch, leak scan over every parameterless GET route, no contact in logs or rows) and `test_contact_consent.py`; Flutter `contact_privacy_test.dart` and `adoption_lifecycle_screen_test.dart`.

## Still open
- Native-speaker review of the Russian/Uzbek notice line; legal review of the privacy policy and terms wording.
- Tuning of the limits after real usage data.
- A per-account alert for repeated limit hits (log events `contact_reveal_limit_reached` exist).
