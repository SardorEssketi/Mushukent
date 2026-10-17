## Test plan
Legend: PROD = executed against a production service (read-only or disposable object). ISOLATED = disposable local database/backend or restored backup copy, no production. BLOCKED = needs access or approval not available to the agent. NOT RUN = not yet executed.

### Completed
- [x] GitHub Actions on `d757911`: Backend lint and format, Backend tests (PostGIS), Flutter analyze and tests, all green. Commits after it (`0bfdbfd` version bump, `5b2e312` docs) change only `pubspec.yaml` and docs and have **not run on GitHub yet** (not pushed)
- [x] Backend suite, disposable PostGIS (ISOLATED): 536 passed, 1 skipped (live R2), ruff and black clean (latest recorded run, `release-handoff/ROLLOUT_CHECKLIST.md`)
- [x] Flutter (ISOLATED): analyze clean, 452 passed, 4 skipped
- [x] Browser regression against an isolated backend (ISOLATED): 25/25
- [x] Production backup restored locally and **migration `0026 -> 0027` applied to the restored copy** (ISOLATED; production database untouched). Production Alembic revision confirmed as `20261013_0026`
- [x] **Cloudflare R2 smoke test (PROD):** upload, exists, public HTTP 200 through `media.mushukistan.uz`, delete, absence confirmed. The earlier 403 was Cloudflare 1010 for urllib's default User-Agent, fixed in the smoke script (`docs/audits/r2-public-read-403.md`)
- [x] Physical Android QA, TECNO Android 14 (ISOLATED backend, debug package `uz.mushukistan.app.rdtest`): login, first login, session restore, outage recovery, posts with photos, map, comments, likes, block/unblock, contact reveal and quota, consent, resolve/delete, languages, legal acceptance, account switching
- [x] Signed AAB `0.2.0+9` built and inspected: package `uz.mushukistan.app`, versionCode 9 (installed production app is 8), signing certificate identical to the installed production app, production API and OAuth client values embedded, no emulator addresses
- [x] FCM server credentials (PROD, `dry_run` only, nothing delivered); email DNS records DKIM/SPF/MX/DMARC (PROD, read-only)
- [x] Google Sign-In configuration consistency: backend client ID = AAB `serverClientId`

### Blocked real-device / console checks (not integration-tested)
- [ ] Android OAuth client and SHA-1 (upload and Play App Signing) for `uz.mushukistan.app` (BLOCKED: Cloud console access)
- [ ] Google Sign-In on the Play-installed build (BLOCKED: needs OAuth client and an internal-testing install; the `.rdtest` package has no OAuth client)
- [ ] FCM push receipt on a real device (BLOCKED: needs production package on a device and approval for one push to a test token)
- [ ] Real verification email delivery and Resend domain status (NOT RUN: needs a mailbox you control and approval)
- [ ] Play Console: versionCode 9 never uploaded (BLOCKED: no console access)

### Deployment gate (NOT DONE; separate approval)
- [ ] Push of `0bfdbfd`, `5b2e312` and CI green on the new head
- [ ] Read-only production preflight (`release-handoff/prod_readonly_inspect.sh`): disk, overlay set, backend start command, image tags
- [ ] Fresh production backup + integrity check immediately before deploy
- [ ] Backend and notification-worker deploy with migration `0027`; post-deploy smoke (`BACKEND_DEPLOYMENT_PLAN.md`)

See `docs/audits/final-integration/INTEGRATION_READINESS.md` and `BACKEND_DEPLOYMENT_PLAN.md`.
