# Phase 3 validation record (reliability and CI)

Branch `fix/reliability-ci`.

| Check | Result |
|---|---|
| Backend pytest, CI-equivalent (APP_ENV=test, no PostHog variables, disposable PostGIS, throwaway credentials), 127.0.0.1 | 483 passed, 1 skipped, 0 failed, 9 min 09 s |
| `ruff check app tests scripts` | pass |
| `black --check app tests scripts --extend-exclude tests/test_feed_map.py` | pass (260 files) |
| Migrations upgrade / downgrade base / upgrade (clean DB) | pass |
| `flutter analyze` | no issues |
| `flutter test` | 426 passed, 4 skipped, 0 failed |
| Browser outage validation, desktop 1366x768 | 24/25 (the one miss was a wrong test fixture: the seeded user's language was English) |
| Browser outage validation, mobile 390x844 | 25/25 |

Not executed: GitHub-hosted workflow (no GitHub access from here), Android runtime.
The real-browser run found a defect the widget tests had missed (cold load of a protected URL during an outage
parked on /auth-required); it is fixed and covered by a new widget test.
