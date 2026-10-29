# Contact reveal: proposal (awaiting approval, nothing implemented)

## Why a change is needed
Today a signed-in user receives `owner_phone_number` and `owner_telegram_username` from the detail endpoint of every lost-pet and adoption post (`GET /lost-pets/{id}`, `GET /adoption-posts/{id}`). The only brake is the general 60 requests/minute per user, which allows about 86,000 numbers per account per day. The existing `POST .../contact` records an event and returns `204` with no body; it does not gate anything, and calling it repeatedly creates new events and owner follow-ups each time.

## Facts that constrain the design
- **Old clients** (including every Android build already installed) read the number from the detail response and, when they see one, show Contact Owner and then call `POST .../contact` (no body needed). They know nothing about a reveal endpoint. If the detail response stops carrying numbers for everyone, every old client silently loses the button for everyone. That is the break the task forbids.
- Old clients cannot be told apart from new ones except by something they send. The new client can send a header such as `X-Contact-Mode: reveal`.
- Owners need their own contact details in the edit form (detail/mine responses to the owner).
- Android updates take weeks; Play can't force an update.

## Proposed design

### 1. Endpoints
| Endpoint | Behaviour |
|---|---|
| `POST /lost-pets/{id}/contact-reveal`, `POST /adoption-posts/{id}/contact-reveal` | Auth required. Not the owner, not blocked, post active, owner has a contact. Records a reveal (see 3), enforces the limit, returns `{phone_number, telegram_username}` with `Cache-Control: no-store`. Idempotent per user and post: a second reveal of the same post returns the same data and does not use quota again. Errors: 401, 403 owner/blocked, 404 not active/no contact, 429 `CONTACT_REVEAL_LIMIT` with `Retry-After`. |
| existing `POST .../contact` | Unchanged (records the "I contacted the owner" event and owner follow-up). The new client calls reveal first, then contact when the user actually taps Call/Telegram. |
| Detail endpoints | **New clients** (header `X-Contact-Mode: reveal`): never contain contact fields, only `contact_available`. **Legacy clients** (no header): see "Compatibility". Owner always sees their own. |
| List, feed, map, mine (non-owner), search, notifications, anonymous | Never contain contact fields (already true; enforced by a new leak test over every GET route). |

### 2. Limits (configurable, defaults proposed)
| Setting | Default | Meaning |
|---|---|---|
| `CONTACT_REVEAL_MAX_PER_DAY` | 15 | unique posts a user may reveal in a rolling 24 hours |
| `CONTACT_REVEAL_MAX_PER_WEEK` | 40 | unique posts in a rolling 7 days |
| `CONTACT_REVEAL_MIN_ACCOUNT_AGE_HOURS` | 0 (off) | optional "new accounts can't reveal yet" |
| `CONTACT_LEGACY_DETAIL_ENABLED` | true | legacy compatibility mode (below); set false after old clients are gone |

Why 15 per day: a person looking for a lost pet or an adopter realistically contacts a few owners; harvesting needs hundreds. 15/40 caps a scraper at roughly 40 numbers a week per account instead of 86,000 a day, and creating verified accounts is the next cost. These numbers are a **product choice** (see decisions).

### 3. What is recorded (never the number)
New table `contact_reveals`: `id`, `user_id`, `post_kind` (`lost_pet`/`adoption`), `post_id`, `owner_id`, `mode` (`explicit`/`legacy_detail`), `created_at`; unique `(user_id, post_kind, post_id)`; indexed by `(user_id, created_at)`. Additive migration; old code ignores it, so rolling back the app needs no schema rollback. Logs contain ids, kind, mode and outcome only. A test asserts that no log record and no event row contains the seeded phone or Telegram value.

### 4. Compatibility strategy (no private numbers exposed just to keep old apps working)
- **Legacy mode** (header absent, `CONTACT_LEGACY_DETAIL_ENABLED=true`): a signed-in non-owner opening a detail page gets the contact **only if the same reveal quota allows it**; that detail read is recorded as a reveal with `mode=legacy_detail`. Anonymous never gets it. Over the limit, the old client simply shows no Contact Owner button for that post (its existing behaviour for posts without a number); it does not crash.
- Cost: in legacy mode, merely *opening* details counts against the quota, so a heavy browser on an old app could hit 15 posts a day. Mitigation options: a higher legacy limit (for example 30/day), or counting only after the old client's `POST .../contact` call. The second is stricter but cannot work, because the old client already has the number before it calls `contact`.
- **New clients** (this release) send the header, never receive numbers in detail, and use `contact-reveal` when the user taps Contact Owner. Guests tapping it are sent to sign in, as today.
- **Sunset**: after the new Android build is adopted (check analytics for versions) and a minimum-supported-version prompt has been shown for a few weeks, set `CONTACT_LEGACY_DETAIL_ENABLED=false`. Old clients then lose Contact Owner (they can still browse); that is a documented, deliberate end of support, not a silent break.
- **Rollout order**: (1) backend with migration, legacy mode on; (2) web client; (3) Android client; (4) later, sunset flag. Rollback at any step is safe: the table is additive and legacy mode keeps working.
- **Caching**: reveal and contact-bearing detail responses get `Cache-Control: no-store` and `Vary: Authorization`; nginx must not cache `/api/` (to be verified in `infrastructure/nginx/default.conf`; the preflight lists it).

### 5. Consent (needs approval of the exact wording)
Add an **explicit, unchecked-by-default checkbox** to both the lost-pet and the adoption create/edit forms, and store the consent version and time. Draft wording (must match the behaviour in section 4, not "public"):

- **English:** "Show my phone number (and Telegram, if I add it) to signed-in Mushukistan users who tap Contact Owner on this post. Each user can view only a limited number of contacts per day. It is never shown to visitors who are not signed in, or in lists or on the map."
- **Russian:** "Показывать мой номер телефона (и Telegram, если я его добавлю) вошедшим в аккаунт пользователям Mushukistan, которые нажмут «Связаться с владельцем» в этом объявлении. Каждый пользователь может открыть ограниченное число контактов в день. Посетителям без входа, в списках и на карте контакт не показывается."
- **Uzbek:** "Telefon raqamimni (va qo‘shsam, Telegramni) ushbu e’londa «Egasiga bog‘lanish» tugmasini bosgan, tizimga kirgan Mushukistan foydalanuvchilariga ko‘rsatish. Har bir foydalanuvchi kuniga cheklangan miqdordagi kontaktni ko‘ra oladi. Tizimga kirmagan tashrifchilarga, ro‘yxatlarda va xaritada ko‘rsatilmaydi."

(Uzbek and Russian are drafts and need a native-speaker check.)
Existing posts: the new policy is **narrower** than what those owners agreed to ("public"), so no re-consent is required. Adoption posts created before have an implicit consent, kept. Editing an old post asks for the new consent. New posts and edits without consent cannot publish a contact (`contact_available=false`), and the API rejects a post with a phone but without consent.

## Decisions I need from you
1. Limits: 15/day and 40/week, or other numbers; a separate legacy limit?
2. Compatibility: legacy mode as described (quota applies to detail reads), or a hard cut (new clients only; old Android loses Contact Owner immediately)?
3. Consent wording (English text above) and whether adoption gets the same explicit checkbox (recommended: yes).
4. Minimum account age before reveals (off by default).
5. Whether to ship backend and clients in this release or hold the Android release until the new client is on the device-tested list.

## Implementation plan once approved (separate commits)
1. Migration and `contact_reveals` model; settings. 2. Reveal service and endpoints plus quota. 3. Detail response modes (header, legacy flag, `no-store`). 4. Consent field in schemas, validation, forms and strings (en/ru/uz). 5. Flutter client: reveal call, sign-in prompt, rate-limit message. 6. Tests: quota boundaries, idempotency, concurrent reveals, legacy mode, owner/blocked, leak scan over all GET routes, no-number-in-logs, caching headers, old-client simulation (no header). 7. Docs update.
