# Tests and regressions

| Suite | Environment | Result |
|---|---|---|
| Backend pytest | Python 3.14 venv, disposable PostGIS (`mushukistan-p4-disposable-db`, port 55436, db name contains `test`), `APP_ENV=test`, no PostHog | 498 passed, 1 skipped, 0 failed (836 s) |
| Backend pytest | Python 3.13 container (the version CI uses) | 495 passed, 2 failed, 2 skipped. The 2 failures come from my partial copy (the container lacked `website/` and the nginx files). The run also exposed a collection error, now fixed |
| ruff, black | local and 3.13 container | clean |
| `flutter analyze` | Flutter 3.44.8 | no issues |
| `flutter test` | local | 432 passed, 4 skipped, 0 failed |
| Live-backend Flutter smoke (3) | isolated backend on 18440 | 3/3 passed |
| Browser (headless Chrome, 390x844): outage, recovery, logout, account switch | isolated backend | 24/25 (see README). 5 bounded retries at 0.9/4/10/22/46 s; automatic recovery in 4.8 s and 13.4 s; credentials never cleared |
| Browser language persistence | isolated backend | 4/4 |
| API contact/cat checks | isolated backend | 4/4 |

Phase 4 tests added: `test_contact_privacy.py`, `test_cat_editing_policy.py`, `contact_privacy_test.dart`, and two language-persistence widget tests. One existing test (`test_feed_map`, owner resolve flow) was updated because it asserted the old anonymous phone exposure.

## Regression review across phases
- Blocking, rate limits, fail-closed env, optional analytics and outage handling are all covered by the full suites above; no regressions found.
- The contact policy change is an intentional API behaviour change. Older clients keep working, but guests on them lose the Contact Owner button, so backend and client should be released together (see CONTACT_PRIVACY.md).
- Blocking and rate-limit scenarios were not re-run in the browser this phase; they rest on backend tests and live API checks.
- Remaining skips: R2 live smoke (needs credentials), 3 opt-in live-backend tests (run manually, passed), web HEIF test (not run).
