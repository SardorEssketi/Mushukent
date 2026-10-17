# Mushukistan 0.2.0: contact privacy, blocking, resilience, legal acceptance, release hardening

Draft for PR #1 (`fix/release-readiness` into `main`). Replaces the earlier draft in `docs/audits/final-release-gate/PR_DESCRIPTION.md`, which predates the migrations. Not yet applied on GitHub.

## Summary
- Contact privacy: owner phone/Telegram never reach guests or list/feed/map responses; signed-in users obtain them through `POST /lost-pets/{id}/contact-reveal` and `POST /adoption-posts/{id}/contact-reveal` under a per-user quota (15/day, 40/week by default). Old clients keep working in legacy mode (`CONTACT_LEGACY_DETAIL_ENABLED=true`). Adoption create requires explicit contact consent from the new client
- Symmetric user blocking; cat edits restricted to creator or moderator
- Rate limiter keyed by verified identity/IP with bounded memory; fail-closed `APP_ENV`
- PostHog is optional and failure-proof; no email/name/free text, exception autocapture off, GeoIP off
- Session survives backend outages (retry screen, bounded back-off); language persisted locally
- Legal acceptance screen after sign-in (never blocks sign-in), explicit accept endpoint
- Feedback endpoint; Google sign-in without consent flags now succeeds for existing accounts
- Android `0.2.0+9`; R2 smoke script User-Agent fix; CI: backend tests on PostGIS, Flutter analyze/tests, ruff and black

## Release notes for operators
- **Database migrations: `20261013_0026` (feedback table) and `20261015_0027` (`contact_reveals` table, nullable consent columns on `lost_pets` and `adoption_posts`).** Both additive. Production is on `0026`, so this release applies exactly `0027`
- **The backend image migrates at container start** (`alembic upgrade head` in the Dockerfile `CMD`). Follow `docs/audits/final-integration/BACKEND_DEPLOYMENT_PLAN.md`: backup, explicit migration step, then replace backend and notification worker together
- Deploy the backend **before** the Android build leaves internal testing: the new client calls the reveal endpoints
- Rolling the backend back is a privacy regression (old code returns contacts to signed-in users without quota, and possibly to guests); prefer a forward fix
- Rename `EMAIL_FROM` to `RESEND_FROM_EMAIL` in the server `.env` (the old name is ignored; same default address, no behavior change)

## Test plan
See `docs/audits/final-integration/PR1_TEST_PLAN.md`. Completed: CI (on `d757911`), backend 536 / Flutter 452, browser 25/25, production backup restore + `0026 -> 0027` on the copy, R2 production smoke, physical Android QA, signed AAB inspection, FCM dry run, email DNS. Blocked: Google Sign-In OAuth client/SHA-1, real push, real email, Play data.

## Not in this PR
Static website default-language change (`/` Russian, `/en/`), Nginx route changes and their docs: separate web release.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
