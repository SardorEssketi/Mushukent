# Test Report (updated after phase 2)

Environment: Windows 11, backend `.venv` (Python 3.14 interpreter), Flutter at `D:\flutter`, Docker Desktop, Chrome 155. Date 2026-10-14.

## Isolation
- A new container `mushukistan-audit-disposable-db` (`postgis/postgis:15-3.4`, host port 55432, its own credentials, no volume) hosted separate databases: `audit_test` (full suite), `audit_repro` (repro tests), `audit_app` (browser/API QA), `audit_perf` (synthetic load), `audit_mig` (migrations). The container is removed at the end of the audit.
- `DATABASE_URL` and `TEST_DATABASE_URL` were exported per command and checked (`current_database()` returned `audit_test`). The backend has no `.env` in its working directory, so no real secrets were loaded. The dev database (`mushukistan-db`) was only read once, before this phase, to count users.
- The destructive fixture (`tests/conftest.py:73`, TRUNCATE of every table) ran only against the disposable databases.

## Static and unit checks
| Command | Result |
|---|---|
| `ruff check app` | pass |
| `black --check app` | fail: `app/main.py` would be reformatted |
| `mypy app` | 54 errors in 20 files |
| `flutter analyze` | no issues |
| `flutter test` | 385 passed, 4 skipped, 0 failed |
| `pip-audit --path .venv/Lib/site-packages` | 20 advisories in 6 packages (see F-20) |

## Complete backend test results
| Run | Result |
|---|---|
| First run, no env (phase 1) | 176 passed, 3 failed, 10 errors, 181 skipped |
| **Isolated run**: `RUN_DB_INTEGRATION_TESTS=1`, disposable DB, dummy PostHog vars, `--basetemp` in a writable folder, `PYTHONPATH=.` | **369 passed, 1 skipped, 0 failed**, 12 min 17 s |

### Explanation of every earlier failure
| Item | Cause | Defect or environment |
|---|---|---|
| `test_rate_limit.py` x3 failures | App lifespan raises when `POSTHOG_PROJECT_TOKEN` is missing | **Application defect** F-05 (they pass once the variable exists) |
| `test_storage.py` x7 errors, `test_places_v2_release_unit.py` x2, `test_notifications_db.py` x1 | `PermissionError: [WinError 5]` on `%TEMP%\pytest-of-PRESTIGE` | **Environment** (Windows temp-directory permissions); pass with `--basetemp` elsewhere. `test_notifications_db` also needed the DB env |
| `ModuleNotFoundError: scripts` at collection | `PYTHONPATH` not set | Environment/invocation; CI would need it |
| 181 skipped | DB tests need `RUN_DB_INTEGRATION_TESTS=1` and a database | Environment; all run in the isolated run |
| 1 remaining skip | Not identified; I did not rerun with `-rs` (a full run takes 12 minutes) | Unknown, low risk |

The 12-minute duration is caused by the exporters retrying a dead PostHog host (`localhost:1`); with telemetry disabled it should be far shorter. I did not verify that.

## Repro and authorization tests I wrote (kept in `evidence/`, not added to the repo)
| Test | Result |
|---|---|
| `test_f01_block_effect` | **fails as expected**: a blocked user's comment is visible, post still in feed, notification created, like 200, comment 201 |
| `test_f02_rate_limit_bypass` | passes: proves 0/200 random-token requests were limited |
| `test_f03_memory_growth_and_per_process` | passes: store keeps 50,001 keys; two independent workers allowed 6 of 10 attempts for a limit of 3 |
| `test_unauthenticated_sweep` | passes: all 53 auth-required routes -> 401 |
| `test_invalid_and_inactive_tokens` | passes: inactive-account token 403, garbage and tampered tokens 401, garbage token on public `/feed` 401 |
| `test_ownership` | cross-user writes rejected; cats open by design; block gaps flagged |

## Migrations
`alembic upgrade head` -> `downgrade base` -> `upgrade head` on an empty database: no errors. `alembic check` reports only `spatial_ref_sys` and an index expression spelling.

## Other executed checks
- Concurrency (20 parallel likes/unlikes, 10 parallel registrations, 10 parallel comments) - results in TECHNICAL_FINDINGS.
- Upload matrix (valid, text-as-jpg, 36 MP, PNG-declared-JPEG, GIF, SVG, empty, 16 MP, 1x1, 7 photos, 5 photos).
- Synthetic load: 5,000 users, 100,000 cats, 200,000 posts, 600,000 comments, 200,000 likes; endpoint timings and one `EXPLAIN (ANALYZE, BUFFERS)` (see PERFORMANCE_REVIEW).
- Browser and Android runs: see FUNCTIONAL_QA_RESULTS.md and ANDROID_TEST_RESULTS.md.

## Not executed / limitations
- Google Sign-In (needs real Google credentials), Firebase push delivery, Cloudflare R2, Telegram/Resend integrations, account deletion through the UI, password change and reporting through the UI, the moderation screens in a browser.
- Production-parity build: I built a custom web bundle pointing at the isolated backend; I did not run the shipped `frontend/build/web` (it points at the production API, so I deliberately avoided it).
- Android runtime (blocked, see ANDROID_TEST_RESULTS.md).
- Website tests (`website/test_*.py`) and website build.
- Flutter dependency vulnerability scanning (no tool available for pub).
- Load testing beyond single-user sequential requests.
- The one unexplained skipped backend test.
