# Privacy and compatibility review

## Verified
| Requirement | Result | Evidence |
|---|---|---|
| Anonymous users cannot retrieve contact fields | **PASS** | `test_contact_privacy.py` (every list, feed, map, detail, mine endpoint); live API check on the isolated backend: anonymous detail has no phone and `contact_available: true`, anonymous list contains no `+998` |
| Signed-in non-owners get the number on the detail endpoint only | **PASS** (by design) | same tests |
| Lost-pet and adoption behave identically | **PASS** | both use the same `contact_is_available` / `include_contact` helpers; tests cover both |
| Authenticated enumeration is bounded | **PARTIAL / DECISION REQUIRED** | see below |
| Owners understand who sees their number | **FAIL (wording out of date)** | see below |
| Old clients keep essential contact function | **PASS for signed-in users, regression for guests** | see below |

## Enumeration by signed-in users
Detail IDs are UUIDs, but list endpoints return them, so any verified account can walk the lists and fetch details. The only limit is the general per-user limit (`RATE_LIMIT_USER_PER_MINUTE`, default 60/min, single worker so it is exact): up to about 86,000 detail reads per account per day, and accounts only need a verified email. Bulk harvesting is slowed, not prevented. The contact event (`POST .../contact`) is already recorded but is not required to see the number.

## What owners are told today (code)
- Lost pet create form: checkbox "Show my profile phone number publicly on this lost-pet post" (explicit consent, stored).
- Adoption post form: a help text, "Your profile phone number is public on this post. Signed-in users can use Contact Owner to call you." No checkbox; the backend stores consent as `true` automatically (`adoption_posts/application/service.py`).
- Both texts say **public**, but since this change the number is visible to **signed-in users on the detail page only**. The wording is more alarming than the behaviour, and the adoption flow records consent without asking. Changing text is a product decision and was not done.

## Recommended contact-reveal and consent policy (not implemented)
1. Wording: "Shown to signed-in Mushukistan users who open your post. Never shown to visitors who are not signed in or in lists." Same sentence for lost pets and adoption; add the same explicit checkbox to adoption, and record the consent text version.
2. Reveal: keep the number off detail responses and return it only from `POST /lost-pets/{id}/contact` (and adoption equivalent), which already records the event. Then every reveal is auditable and countable.
3. Quota: cap distinct reveals per account (for example 20 per hour, 100 per day) with 429 and a clear message; log and alert on accounts above the cap. Consider requiring a minimum account age.
4. Owner transparency: show the owner a "N people contacted you" count (the event data exists).
5. Optional later: relay (masked) numbers or in-app messaging; Telegram username only on request.
Items 2-3 change the API and the client flow and need product approval and a client release; I did not build them.

## Old app versions (weeks or months in the field)
Reading the previous client code (`47ebff4`):
- Models treat `owner_phone_number` as nullable, so a missing value does not crash parsing.
- Detail screens show Contact Owner only when the number is non-null. **Signed-in users** still receive the number on the detail endpoint, so their contact flow, the owner's edit form, and the contact event keep working.
- **Guests** on old clients no longer see Contact Owner (they previously saw the button, then were sent to sign in). This is the only functional loss. Signing in restores it.
- Nothing else uses the phone from list responses.

Rollout recommendation, which avoids exposing numbers to stay compatible:
1. Ship the Android/Web client with `contact_available` first, or at the same time. The new client works against both the old and the new backend (it falls back to `owner_phone_number != null` when the flag is absent).
2. Deploy the backend change after the new Web build is live; for Android accept that guests on old versions lose the button until they sign in or update. Do **not** add a compatibility mode that returns numbers to guests.
3. Raise a minimum-supported-version prompt later if the loss matters (not built).
4. If Play review delays the Android client, the backend can still ship: the loss affects guests only.
