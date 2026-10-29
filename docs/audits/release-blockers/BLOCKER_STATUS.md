# Release blocker status

Branch `fix/release-readiness`. Not pushed, merged or deployed. No production access. Pre-existing uncommitted work of the project owner is untouched.

## Verdict: NOT READY

Android runtime and the production preflight are unverified (GitHub CI has since passed). The contact policy is implemented and tested; it is approved by you in principle, but its Russian and Uzbek wording and the legal texts are not reviewed.

| # | Blocker | Status | Detail |
|---|---|---|---|
| 1 | Contact reveal system | **PASS (implemented and tested); DECISION REQUIRED for wording review** | Implemented per the approved choices (legacy mode with quota, 15/day and 40/week, explicit consent for both post kinds). Details below. Open: native-speaker review of Russian/Uzbek consent text, legal review of terms/privacy text that still says "public" |
| 2 | Android runtime | **BLOCKED** | `adb devices` lists no device. Nothing was installed, modified or validated on Android. Plan: `docs/audits/final-release-gate/ANDROID_VALIDATION.md` |
| 3 | GitHub CI | **PASS** | Branch pushed and PR #1 opened (https://github.com/SardorEssketi/Mushukent/pull/1). GitHub-hosted run 38777007138 on commit `49629f7`: Backend lint and format, Backend tests (PostGIS) and Flutter analyze and tests all succeeded on the first run. Left open for review, not merged |
| 4a | Production config preflight | **BLOCKED** (tool ready) | `backend/scripts/prod_preflight.py --env-file <file>`: read-only, prints only PASS/FAIL/WARN names. Self-tested with a deliberately bad fake file. Not run against production configuration |
| 4b | R2 upload test | **BLOCKED** (tool ready) | `backend/scripts/r2_disposable_smoke.py`: dry run by default; `--execute` uploads one PNG to `release-smoke/<random>/smoke.png`, checks it, and deletes it in a `finally` block. Needs your approval and credentials; staging bucket first |
| 4c | Backup, rollout, rollback, smoke tests, stop conditions | **PASS (documented)** | below |

## What was built for the contact policy (blocker 1)
- `POST /lost-pets/{id}/contact-reveal` and `POST /adoption-posts/{id}/contact-reveal`: signed-in, non-owner, not blocked, active post; returns phone/Telegram; `Cache-Control: private, no-store`; `429 CONTACT_REVEAL_LIMIT` with `Retry-After`.
- Quota: unique posts per user, rolling 24 h and 7 days, `CONTACT_REVEAL_MAX_PER_DAY=15`, `CONTACT_REVEAL_MAX_PER_WEEK=40`, optional `CONTACT_REVEAL_MIN_ACCOUNT_AGE_HOURS` (0), per-user transaction lock against parallel bypass. Repeat reveal of the same post is free.
- Legacy compatibility (`CONTACT_LEGACY_DETAIL_ENABLED=true`): old apps (no `X-Contact-Mode` header) still get contact on detail pages, only when signed in, non-owner and within the same quota; recorded as `legacy_detail`. Anonymous never. New clients send `X-Contact-Mode: reveal` and never receive contacts with post details.
- Log: table `contact_reveals` (user, kind, post, owner, mode, time) and structured log events, never the contact value (tested).
- Consent: checkbox on both create forms, unchecked by default, new wording (en/ru/uz); stored as `contact_consent_version=1` and `contact_consent_at`; existing posts keep working (new policy is narrower than the "public" wording they accepted).
- Migration `20261015_0027`: additive (new table, two nullable columns on each post table). Upgrade, downgrade and re-upgrade tested; old code ignores the additions, so a code rollback needs no schema rollback.
- Docs: `docs/CONTACT_PRIVACY.md`, `docs/API.md`; design record `CONTACT_REVEAL_PROPOSAL.md`.

## Tests (all on disposable PostGIS, isolated backend, no production)
| Check | Result |
|---|---|
| Backend full suite | 514 passed, 1 skipped (live R2), **1 failed**: `test_db_metadata` table list lacked the new table. Fixed in `49629f7`; that file then passed (4 passed). A full re-run after the fix was **not** repeated |
| New backend tests | `test_contact_reveal.py` (12) and `test_contact_consent.py` (5), both passing |
| Ruff, Black | clean |
| Flutter | analyze clean; 436 passed, 4 skipped, 0 failed |
| Live API (isolated backend) | anonymous detail and reveal-mode detail show no phone; anonymous reveal 401; signed-in reveal 200 with `no-store`; old-style detail returns the number within the quota |
| Browser, reveal flow (headless Chrome, mobile viewport) | signed-in Contact Owner visible, no number before the tap, loading the detail revealed nothing, tap produced one `OPTIONS` + `POST contact-reveal` (200) + `POST contact` (204), number shown afterwards: 4 of 5 checks passed; the failing check was my script counting log lines that included an earlier manual API call, not a product defect (evidence in `reveal_browser.txt` and the backend log). The guest-page check was dropped from the script after a hang, so guests were not checked in the browser (covered by backend and widget tests) |
| Browser regression (outage/recovery/logout/account switch) | 25/25 on the new client and backend |

Environment problems met (not product defects): Windows reserves TCP ports 9657-9756, which made Chrome debugging hang until I used port 9641; C: has about 1 GB free; a test contact event created a "Did you find your pet?" prompt for the seeded owner and failed 8 later checks until I answered it, which is data pollution from my own test.

## Coordinated rollout
1. **Before anything:** database backup, restore rehearsed into a scratch database; record the current backend image, web build and Android version code; run `prod_preflight.py` and the R2 test.
2. **Backend first** with migration `20261015_0027` and legacy mode on. Smoke tests.
3. **Web client** (instantly rollbackable).
4. **Android** after device validation, as a staged rollout (for example 5% to 20% to 100%).
5. **Later:** set `CONTACT_LEGACY_DETAIL_ENABLED=false` once old versions are below an agreed share.

## Smoke tests after each step
Health; register and verify email; login and session restore; anonymous `GET /lost-pets` and `/adoption-posts` have no phone or Telegram; signed-in reveal works and the 16th unique post in a day returns 429; legacy (no header) detail respects the quota; blocked users hidden; cat `PATCH` by a non-owner is 403; photo upload works; contact event recorded.

## Rollback
| Component | Rollback | Check afterwards |
|---|---|---|
| Backend | redeploy the previous image; the migration is additive so the schema can stay. Do not downgrade the production database unless a restore is chosen | health, login, anonymous list has no phones. If the previous image predates the Phase 4 contact change it re-exposes numbers to anonymous users: treat that as a security rollback and prefer a forward fix |
| Web | redeploy the previous build; the old web client still works against the new backend through legacy mode | main flows |
| Android | halt the staged rollout; the previous release stays installable | crash-free rate, login success |
| Database | restore only for corruption; rehearse first | row counts, `alembic current` |

## Release-stop conditions
Backup or restore rehearsal fails; any preflight FAIL; any smoke test fails, especially a phone number visible to an anonymous request; 5xx above 1% for 10 minutes or a sharp login-success drop; Android crash-free sessions below the agreed threshold; the R2 test fails; `alembic current` not at `20261015_0027` after deploy; CI red on the pull request.

## Needed to reach READY
1. Android: run `ANDROID_VALIDATION.md` on a real test device (your approval for the install) and pass every scenario, including contact reveal and quota messages.
2. CI: approve push and pull request into `main`; all three jobs green on GitHub.
3. Production: run the preflight on the real configuration; run the R2 test (staging first, production only with your approval); backup and restore rehearsal.
4. Review the Russian and Uzbek consent wording and the legal text; re-run the full backend suite once on the final commit.
