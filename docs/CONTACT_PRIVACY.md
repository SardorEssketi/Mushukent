# Owner contact privacy (lost-pet and adoption posts)

Status: implemented on branch `fix/release-readiness` (audit finding F-13). Items marked **Decision needed** are product choices for the owner of the project.

## What was exposed

Before this change every lost-pet and adoption endpoint returned `owner_phone_number` and `owner_telegram_username` to anyone, signed in or not:

- `GET /lost-pets`, `GET /adoption-posts`, `GET /feed` (list items),
- `GET /lost-pets/{id}`, `GET /adoption-posts/{id}`,
- `GET /lost-pets/mine`, `GET /adoption-posts/mine` (owner's own lists).

Lists are paginated up to 100 items and the old rate limiter could be bypassed with random Bearer tokens (fixed in `fix/security-hardening`), so harvesting every phone number needed only a few anonymous requests.

## What the product requires (docs/PRD.md, docs/UI_UX.md)

- Contact Owner is a **sign-in-gated action**: "Guests are asked to sign in before the contact event is recorded or the phone action proceeds" (UI_UX.md). The contact event is recorded server-side before the phone/Telegram action.
- Lost pets require explicit consent to show the profile phone number publicly. Adoption posts have no consent checkbox; a usable profile phone is required (PRD.md).
- Phone numbers are not shown on public profiles (UI_UX.md).

So the number only needs to be reachable by someone who is about to contact the owner, who must already be signed in.

## Policy implemented

| Viewer / endpoint | Phone and Telegram | `contact_available` |
|---|---|---|
| Anonymous, any endpoint | never | yes |
| Signed in, list / feed / map / `mine` | never | yes |
| Signed in, detail endpoint | yes (unless the post is resolved, as before) | yes |
| Owner, detail endpoint (needed by the edit form) | yes | yes |

`contact_available` is true when the post is not resolved and the owner has a usable phone number. The Flutter client shows the **Contact Owner** action when it is true; guests who tap it are sent to sign in (existing behaviour), after which the detail reloads and the number appears on the button. No essential functionality was removed.

Residual risk: any verified, signed-in account can still read the numbers one post at a time. That is bounded by the per-user rate limit (60 requests/minute) and email-verified registration, but it is not eliminated.

## Decisions needed

1. **Is a signed-in-only number acceptable for lost pets** whose owners consented to *public* visibility? The consent text promises public display; this policy is stricter than that promise. Recommended: yes (nothing breaks, privacy improves), and update the consent wording to "shown to signed-in users".
2. **Adoption posts have no consent step.** Add the same explicit consent as lost pets? (Not implemented: changes the create form and API contract.)
3. **Stronger anti-harvesting** (per-user daily cap on distinct contact reveals, or reveal only through the recorded `POST .../contact` call so every reveal is an event). Not implemented because it changes the contact flow; the contact event is already recorded, so it is a small follow-up.
4. **Existing cached clients**: older app versions keep working (the fields are optional on the client) but guests on them lose the Contact Owner button because it used to depend on the number being present. Releasing the updated client with the server change avoids this.

## Tests

`backend/tests/test_contact_privacy.py` (anonymous and signed-in views of every endpoint, scraping simulation, owner edit flow, contact workflow, resolved posts) and `frontend/test/features/lost_pets/contact_privacy_test.dart`.
