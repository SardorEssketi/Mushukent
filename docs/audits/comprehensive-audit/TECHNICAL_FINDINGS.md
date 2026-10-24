# Technical Findings (updated after phase 2)

Audit date: 2026-10-14. Branch `feature/publication-detail-redesign`. Everything ran against local, disposable resources (a throwaway PostGIS container, an isolated backend on port 18400 and a custom web build). No production access, no dev-database writes.

Evidence levels: **Confirmed** = reproduced by a test, command or browser run described in this folder. **Code-confirmed** = proven by reading code, not executed. **Needs verification** = plausible, not proven.

Correction to the first report: it said `users/application/service.py:268-269` was the profile view. It is the account-deletion cleanup of block rows. Block enforcement is simply absent elsewhere (F-01).

Reproduction artifacts: `evidence/repro_f01_f02_f03.py`, `evidence/authz_matrix_tests.py`, `evidence/authz_run_output.txt`, `screenshots/`.

## Summary

| ID | Sev | Area | Title | Confidence |
|----|-----|------|-------|-----------|
| F-01 | P1 | Backend/Security | Blocking a user is stored but enforced nowhere | Confirmed (API + browser) |
| F-02 | P2 | Backend/Security | Rate-limit bypass with arbitrary Bearer tokens | Confirmed |
| F-03 | P2 | Backend | Rate-limit store never evicts keys; per-process counters | Confirmed |
| F-04 | P2 | Infrastructure | CI runs no tests; `black --check` fails | Confirmed |
| F-05 | P2 | Backend | App will not start without PostHog token outside production | Confirmed |
| F-06 | P2 | Backend | 54 mypy errors, duplicated `ApiSuccess` classes | Confirmed |
| F-12 | P2 | Security/Config | Fail-open `APP_ENV` default exposes email-verification tokens | Confirmed |
| F-13 | P2 | Privacy | Phone numbers readable by anonymous clients; scrapable given F-02 | Confirmed |
| F-14 | P2 | Backend/Data | Any signed-in user can edit any cat and set an arbitrary external cover URL | Confirmed |
| F-16 | P2 | Frontend/UX | Backend outage looks like being logged out | Confirmed (browser) |
| F-25 | P3 | Backend | Zero-photo lost-pet/adoption row makes reads and the list endpoint return 500 | Confirmed with seeded row; reachability via API unverified |
| F-07 | P3 | Backend | Account-deletion media cleanup is best-effort | Code-confirmed |
| F-08 | P3 | Frontend/Security | Web tokens in localStorage | Confirmed |
| F-09 | P3 | Infrastructure | No nginx `limit_req` | Confirmed (config) |
| F-10 | P3 | Android | Release signing optional, no shrinking, no deep links, backup default | Code-confirmed |
| F-11 | P3 | Tests | Default test run skips 181 tests; no tests for F-01/F-02/F-14 | Confirmed |
| F-17 | P3 | Frontend/UX | Missing post shows "Retry"; unknown route is a dead end | Confirmed (browser) |
| F-18 | P3 | Infrastructure | `/health` never checks the database | Code-confirmed |
| F-19 | P3 | Security | Refresh tokens never rotate; replay works; no absolute lifetime | Confirmed (documented choice) |
| F-20 | P3 | Dependencies | `python-jose` 3.5.0 (CVE-2026-85394, unmaintained), `cryptography` 49.0.0 blocked by `<50` pin | Confirmed (scan); not exploitable as configured |
| F-21 | P3 | Database | Popular feed does a full sequential scan | Confirmed (measured) |
| F-22 | P3 | Frontend/UX | Map silently shows at most 100 pins per viewport | Confirmed |
| F-23 | P3 | Backend | Identical comments accepted (no idempotency); UI guards double clicks | Confirmed |
| F-24 | P3 | Frontend | `GET /users/me` fired 3 times at app start | Confirmed (measured) |
| F-26 | P3 | Observability | No Flutter crash reporting found; backups are a manual pre-migration step | Code/doc-confirmed |

Totals: P0 0, P1 1, P2 9, P3 15 (25 findings). The earlier F-02 was rated P1; see F-02 for why it is now P2.

---

## F-01 Blocking is stored but not enforced (P1, Backend/Security/Frontend, effort Medium, impact High)
- **Files:** `backend/app/features/users/application/service.py:489-510` (create/remove block); no use in `features/{comments,feed,posts,notifications,lost_pets,adoption_posts,likes}`; client only keeps a local flag in `frontend/lib/features/profile/presentation/screens/public_profile_screen.dart:72,255-268`.
- **Reproduction (executed):** `evidence/repro_f01_f02_f03.py::test_f01_block_effect`. Alice blocks Bob (204). Then:
  - Bob comments on Alice's post -> **201**, and Alice's comment list shows it.
  - Bob's post appears in Alice's feed.
  - Alice receives a notification about Bob's comment.
  - Bob likes Alice's post -> 200; Bob contacts Alice's lost-pet post -> **204**.
  - Browser run: blocking Bob from his profile sent `POST /users/{id}/block`; afterwards the API still returned 3 of Bob's items in Alice's feed.
- **Root cause:** the `user_blocks` table is written but no query or write path consults it.
- **Impact:** a harassed user cannot get away from the harasser. App-store UGC policies expect blocked content to be hidden.
- **Fix:** decide behaviour (hide vs. reject), then exclude blocked pairs in both directions in feed, comment list/create, likes, notification creation and owner contact; add tests (the repro file is a starting point).
- **Release blocker:** yes for a public launch that includes UGC.

## F-02 Rate-limit bypass with arbitrary Bearer tokens (P2, Security, Small)
- **File:** `backend/app/core/rate_limit.py:160-173, 201-209`.
- **Reproduction (executed):** with the anonymous limit at 3/min: no token -> 429 from the 4th request; the same garbage token 10 times -> 200,200,200,429...; **200 requests each with a different random token -> 0 of 200 limited** (`test_f02_rate_limit_bypass`).
- **Root cause:** the bucket key is `sha256(token)` and the token is never validated in the middleware.
- **Real-world reach (why P2, not P1):** endpoints that validate the token (all authenticated ones, and `get_optional_current_user` routes such as `/feed`) answer 401 to a fake token, so this does not let an attacker spam writes. It does remove throttling on routes that never look at the token: `/places`, `/cats`, `/lost-pets`, `/lost-pets/map`, `/leaderboards/*`, `/health`. A real account can also mint new tokens through `/auth/login`/`/auth/refresh`, but those are throttled per IP. Combined with F-13 it enables scraping.
- **Fix:** key by client IP unless the token verifies, and keep a per-IP ceiling in addition.

## F-03 Rate-limit store never evicts keys; counters are per process (P2, Backend, Small)
- **File:** `backend/app/core/rate_limit.py:36-71, 117-126`.
- **Measured:** after 50,000 distinct keys the store held 50,000; after the window expired and a new request arrived it still held 50,001 (`test_f03_memory_growth_and_per_process`). Two independent limiters each allowed 3 of 5 requests (6 total for a limit of 3), which is the per-worker multiplication. The `redis` backend raises `RuntimeError`.
- **Impact:** unbounded memory growth (worse with F-02) and limits that scale with worker count.
- **Fix:** evict idle keys; shared store before running more than one worker.

## F-04 CI does not test and is red on formatting (P2, Infrastructure, Small)
- `.github/workflows/ci.yml` runs `ruff`, `black --check`, `flutter analyze` only. `black --check app` fails on `app/main.py` (the `missing_setting` expression). With correct setup the suites pass (369 backend, 385 Flutter) but nothing runs them on a pull request.

## F-05 Startup crashes without PostHog configuration (P2, Backend, Small)
- **File:** `backend/app/main.py:86-93`. Non-production with no token raises `RuntimeError` in the lifespan.
- **Evidence:** the 3 `test_rate_limit.py` failures in the first run. With `POSTHOG_PROJECT_TOKEN`/`POSTHOG_HOST` set to dummies they pass (see TEST_REPORT).
- **Side effect observed:** with an unreachable PostHog host the backend suite took 12m17s instead of seconds because the OTLP/PostHog exporters retry on every test; the test environment should disable telemetry.

## F-06 Type-check debt (P2, Backend, Medium)
- `mypy app`: 54 errors in 20 files, including two parallel `ApiSuccess` classes (`routes/users.py:92,104`), an incompatible `register` override (`auth/application/service.py:75`), and CORS kwargs typing (`main.py:134`). Not part of CI.

## F-12 Fail-open `APP_ENV` default (P2, Security/Config, Small)
- **Files:** `backend/app/core/config.py:15,111`; `backend/app/features/auth/application/service.py:122,193,620-621`.
- **Evidence (executed):** with `APP_ENV=development` (the default), `POST /auth/register` returns `dev_verification_token` in the response; I used it to verify an email with no mailbox access.
- **Impact:** if production is ever started without `APP_ENV=production` (typo such as `prod`, missing variable), anyone can verify any email address, secret-strength validation (`validate_production_settings`) is skipped, API docs are enabled and CORS becomes the localhost regex. `docker-compose.prod.yml` sets the value, which is why this is P2.
- **Fix:** default to production-like, or fail startup unless the value is one of an explicit allow-list.

## F-13 Anonymous access to owner phone numbers (P2, Privacy, Medium)
- **Evidence (executed):** unauthenticated `GET /lost-pets` and `GET /adoption-posts/{id}` return `owner_phone_number`; the browser accessibility label of the Contact Owner button also contains the number.
- **Context:** this is documented (`docs/API.md:620-640`, consent required for lost pets). The adoption form has no consent checkbox (`docs/API.md:760`). The risk is mass harvesting: the list endpoints are public and, due to F-02, throttle-free.
- **Fix options (product decision):** require login to reveal the number, or reveal on a tap-through "Contact owner" call that is rate-limited per user.

## F-14 Any user can edit any cat (P2, Backend/Data, Small)
- **File:** `backend/app/features/cats/application/service.py:99-197`.
- **Evidence (executed):** non-owner B renamed A's cat -> 200; B set `cover_photo_url` to an arbitrary external URL (`http://169.254.169.254/x.jpg`) -> 200. Status and merges correctly need a moderator (403).
- **Context:** `docs/API.md:431` states normal users may update non-sensitive fields in the MVP.
- **Impact:** vandalism with no edit history for cats, and hotlinked third-party images (tracking pixels, inappropriate content) can be injected into every viewer's map/feed. The URL is only used by the client as an image, so it is not an SSRF path.
- **Fix:** restrict to the creator or moderator, or allow only URLs under the media base URL.

## F-16 Backend outage looks like a logout (P2, Frontend/UX, Medium)
- **Reproduction (executed, `screenshots/down_feed.png`):** signed in, then stop the API. `/feed` renders the signed-out hero (Login / Create account) with "Could not load this section"; `/profile` redirects to `/auth-required?redirect=/profile`. Tokens remained in storage (checked), so the session was fine.
- **Impact:** during any incident users believe they were signed out and may re-register or abandon.
- **Fix:** keep the last known authenticated state when `/users/me` fails with a network error or 5xx; only drop it on 401.

## F-25 Zero-photo lost-pet/adoption rows break reads (P3, Backend, Small)
- **File:** `backend/app/features/lost_pets/infrastructure/repositories.py:441` (`photo_records[0]`); the adoption equivalent behaves the same.
- **Evidence (executed):** a row without photos gave 500 (`IndexError`) on `GET /lost-pets/{id}`, PATCH, DELETE and the **public list**, so one bad row takes the whole list down.
- **Reachability:** the API requires 1-5 photos on create and replacement, and the schema has no constraint enforcing it. I did not find an API path that produces zero photos, so this is hardening.
- **Fix:** tolerate empty photo lists in `_model_to_record`; consider a DB-level check.

## F-07 Orphaned media on account deletion (P3, Backend, Small)
- `users/application/service.py:~345-410`: after commit, media deletion failures are only logged.

## F-08 Tokens in web localStorage (P3, Frontend/Security)
- Confirmed in the browser: `mushukistan_access_token` and `mushukistan_refresh_token` are in `localStorage`. The CSP in `infrastructure/nginx/default.conf:65` limits XSS risk.

## F-09 No edge rate limiting (P3, Infrastructure)
- No `limit_req`/`limit_conn` in `infrastructure/nginx/default.conf`; body cap 55 MB.

## F-10 Android release hardening (P3, Android)
- `frontend/android/app/build.gradle.kts`: release signing only if the keystore file exists, no shrinking. `AndroidManifest.xml` has no app-link/deep-link intent filters (only launcher and a text/plain query) and no `allowBackup` setting. `gradle.properties` requests an 8 GB heap, which crashed the Gradle daemon on this memory-constrained machine (built fine with `-Xmx2g`).

## F-11 Test coverage gaps (P3)
- Default `pytest` skips 181 tests; with a disposable DB all 369 pass. There is no test for blocking, the rate-limit token key, cat edit authorization, or zero-photo rows. There is no `test_lost_pets` module at all.

## F-17 Error states for missing content (P3, Frontend/UX, Small)
- `screenshots/m_mobile_dark_missing_post.png`: a deleted/missing post (404) shows "Could not load this section" and a Retry button that cannot succeed. `screenshots/m_mobile_dark_garbage.png`: an unknown URL shows only "This page is not available." with no navigation or way home (the bottom bar is also absent).

## F-18 Health check is shallow (P3, Infrastructure)
- `backend/app/api/v1/routes/health.py:11-22` returns OK without touching the database, so the Docker healthcheck (`docker-compose.yml:38-46`) stays healthy during a database outage. Each call also emits a PostHog log event.

## F-19 Refresh token behaviour (P3, Security)
- Executed: after refreshing, the stored refresh token was unchanged and replaying the old value returned 200. Documented as an MVP choice (`docs/AUTH.md:116,295`). Combined with F-08 a leaked token stays valid as long as it is used at least every 30 days.

## F-20 Dependency findings (P3, Dependencies)
`pip-audit` against the backend virtualenv: 20 advisories in 6 packages.
- **python-jose 3.5.0 (CVE-2026-85394, no fix)** - HMAC key confusion with asymmetric keys. Not exploitable here: `tokens.py:57-68` pins `algorithms=[settings.jwt_algorithm]` and uses a symmetric secret. The library is unmaintained; plan a move to PyJWT.
- **cryptography 49.0.0 (PYSEC-2026-3552, fixed in 50.0.0)** - affects PKCS7 decryption, which the code does not use. `pyproject.toml` pins `<50.0.0`, so the fix cannot be installed without a pin change.
- **ecdsa 0.19.2 (CVE-2024-23342, no fix)** - signing-side timing attack; the app does not sign with ECDSA.
- black, pytest, pip: development tooling only.
- Flutter: 92 packages have newer versions blocked by constraints; no advisory scanner was run for pub packages.

## F-21 Popular feed scans the whole table (P3, Database)
- `posts/infrastructure/repositories.py:470-495` orders by `(like_count, created_at, id)`; there is no matching index (`pg_indexes` listing for `posts`). With 200,000 posts the plan is a Parallel Seq Scan + top-N sort (30 ms core; 164 ms median at the API). It grows linearly with posts. A partial index on `(like_count DESC, created_at DESC, id DESC) WHERE deleted_at IS NULL AND is_public` is the candidate; not benchmarked.

## F-22 Map truncates silently (P3, Frontend/UX)
- Measured requests: `GET /cats?...&limit=100`. With 3,000 seeded cats the viewport showed about 100 pins and nothing in the UI says more exist (`screenshots/map_3000.png`).

## F-23 Duplicate-submit protection (P3)
- 10 concurrent identical comments -> 10 stored. The web UI sent a single request on a double click, so users are protected in practice; API clients are not.

## F-24 Duplicate startup requests (P3, Frontend)
- Cold load of `/profile` with a stale access token issued `GET /users/me` three times plus a refresh (browser run). Not harmful; avoidable.

## F-26 Observability (P3)
- No crash reporting in the Flutter app (no Sentry/Crashlytics/`runZonedGuarded` match), PostHog on the backend only. Backups: `docs/DEPLOYMENT.md:130-143` documents a manual pre-migration `pg_dump`; no scheduled backup or restore drill is documented.

## Verified OK (positive findings)
- All 53 authenticated routes return 401 without a token; cross-user edit/delete/resolve on posts, comments, lost pets and adoption posts return 403; moderation routes 403 for normal users; other users' notifications 404; activity-private profiles 403; public profile hides email/phone/telegram/moderator flag; deleted account tokens get 403.
- Concurrency: 20 simultaneous likes -> exactly one stored (19 x 409, count 1); 10 simultaneous registrations of one email -> one user; unlike is idempotent.
- Uploads: text, GIF, SVG, empty, wrong-format and 36 MP files rejected (422); 6th photo rejected (400); a 16 MP JPEG and a JPEG with trailing HTML were accepted (200). The code re-encodes through Pillow (`images.py`), but I did not keep the polyglot's stored object to prove the trailing bytes were dropped.
- Migrations: 26 revisions upgrade from empty, downgrade to base, and upgrade again without error. `alembic check` only reports benign drift (`spatial_ref_sys`, an index expression spelling).
- JWT validation, security headers and prod compose hardening as in the first report.
