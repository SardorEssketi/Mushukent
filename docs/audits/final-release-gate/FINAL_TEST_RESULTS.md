# Final test results

All runs on branch `fix/release-readiness` at commit `8f818b6` plus the uncommitted work of the project owner. Disposable PostGIS container (`postgis/postgis:15-3.4`, local port 55436, database names contain `test`, removed afterwards), `APP_ENV=test`, no PostHog/Firebase/R2 variables.

| Check | Result |
|---|---|
| Backend pytest (Python 3.14 venv) | **498 passed, 1 skipped, 0 failed** (836 s). Raw output: `final_full.txt` |
| Ruff | all checks passed |
| Black (CI command, `test_feed_map.py` excluded as in CI) | 262 files unchanged |
| `flutter analyze` | no issues |
| `flutter test` | **433 passed, 4 skipped, 0 failed** |
| Browser smoke (headless Chrome, 390x844, release web build against an isolated backend and DB): outage, retry screen, bounded retries, recovery, logout, account switch | **25/25**. Raw output: `final_mobile.txt` |
| Live API: anonymous detail has no phone and `contact_available: true`; signed-in detail has the number; anonymous lost-pet/adoption/feed lists contain no phone | pass |
| Security regressions (blocking, rate limit, APP_ENV, analytics, contact privacy, cat editing) | included in the 498 backend tests |
| GitHub Actions | **not run** |
| Android runtime | **not run** (no device) |

## The "24/25" browser result
It was **invalid test data, not a product defect.** The seed script registered every test user with `preferred_language=en`, but the check expected Bob's UI to switch to Russian. After setting Bob's language to `ru` in the seed data the same script passes 25/25. A new Flutter regression test (`switching accounts without a restart switches the UI language`, commit `8f818b6`) also proves the language follows the account on logout/login with no restart. No application code needed fixing.

## Skipped tests and what they mean
| Test | Why skipped | Risk |
|---|---|---|
| `backend/tests/test_storage.py:494` live R2 smoke | needs real Cloudflare R2 credentials | Real upload/permissions against R2 are unverified here; run it in staging with a test bucket before release |
| `frontend/test/live_backend_smoke_test.dart` (3 tests) | opt-in via `RUN_LIVE_BACKEND_TESTS=1` | They need a running backend. Run against the isolated backend last phase: 3/3 passed. Not run again in this phase |
| `frontend/test/core/media/heif_normalizer_web_test.dart` | `skip: !kIsWeb`; only runs with `--platform chrome` | Web HEIF conversion is **unverified**: the Chrome run failed in Phase 4 because C: was full ("not enough space"), and was not retried while C: has about 1 GB free. This is photo upload for iPhone users on the web: re-run when disk space is freed |
| (CI only) `tests/test_places_v2_source_parsers.py` | skipped when `bs4` is missing | fixed in CI by installing the `research` extra; ran locally with it |

## Not covered
Android runtime, GitHub-hosted CI, Google sign-in, push notification delivery, real R2, production configuration, load testing, web HEIF conversion.
