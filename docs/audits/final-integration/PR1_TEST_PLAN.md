## Test plan
Legend: PROD = executed against production services. ISOLATED = local disposable database/backend or restored backup, no production.

- [x] GitHub Actions: Backend lint and format, Backend tests (PostGIS), Flutter analyze and tests, all green on `d757911` (CI)
- [x] Backend suite, disposable PostGIS (ISOLATED): 514 passed, 1 skipped (live R2); the one failing metadata test was fixed
- [x] Flutter (ISOLATED/local): analyze clean, 436 passed, 4 skipped
- [x] Browser regression against an isolated backend (ISOLATED): 25/25
- [x] Migration 0026 -> 0027 on a restored copy of the production backup (ISOLATED; production database untouched)
- [x] **Cloudflare R2 smoke test (PROD):** upload, exists, public HTTP 200 through `media.mushukistan.uz`, delete, absence confirmed. The earlier failure was a 403 (Cloudflare 1010) for urllib's default User-Agent, fixed in the smoke script (`docs/audits/r2-public-read-403.md`)
- [x] Android runtime on a real phone (ISOLATED): debug build `uz.mushukistan.app.rdtest` with a local backend; login, session restore, legal acceptance, feed, logout and account switching passed. Google Sign-In and push could not be tested on that package id
- [x] Signed AAB `0.2.0+9` built and inspected: package, versionCode, signing certificate identical to the installed production app, production API/OAuth values embedded
- [x] FCM server credentials (PROD, dry run only, nothing delivered) and email DNS records (PROD, read-only)
- [ ] Android OAuth client + SHA-1 registration for `uz.mushukistan.app` (BLOCKED: needs Cloud console access)
- [ ] Google Sign-In, push receipt and reveal on the Play-installed build (NOT RUN)
- [ ] Real verification email delivery (NOT RUN; needs approval)
- [ ] Production read-only SSH preflight (NOT RUN)
- [ ] Production deploy with migration 0027 (NOT DONE, out of scope)

See `docs/audits/final-integration/INTEGRATION_READINESS.md`.
