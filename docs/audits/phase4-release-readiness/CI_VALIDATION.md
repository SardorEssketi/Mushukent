# CI validation (Phase 4)

**GitHub Actions has not run.** Nothing was pushed. Everything below is local validation. The first real run happens when the branch is pushed (instructions at the end).

## Static checks
| Check | Result |
|---|---|
| YAML parse | OK |
| `actionlint` 1.7.12 (installed into a scratch directory with `pip install --target`, nothing added to the repo) | exit 0, no findings |
| Job graph | three independent jobs (`backend-quality`, `backend-tests`, `frontend-quality`); no `needs`, so they run in parallel and all must pass |
| Permissions / secrets | `contents: read` only. No `secrets.*` are used; the only credentials are throwaway values for the service container |
| Action pinning | exact tags (`checkout v4.2.2`, `setup-python v5.6.0`, `flutter-action v2.18.0`), not commit SHAs (SHAs could not be resolved offline). Recommended hardening: pin SHAs before a public release |
| Caching | `setup-python cache: pip` keyed on `backend/pyproject.toml`; `flutter-action cache: true` |
| Flutter SDK | pinned `3.44.8` (local version; Dart satisfies `sdk: >=3.5.0 <4.0.0`) |
| Java | not needed: CI runs `flutter analyze/test` only, no Gradle/Android build. An Android build job is **not** in CI (recommended follow-up) |

## What I ran locally that mirrors CI
| Step | Environment | Result |
|---|---|---|
| ruff + black (CI commands) | Python 3.13.15 in `python:3.13-slim` | pass (262 files unchanged) |
| `pip install -e .[dev]` | Python 3.13.15 container | OK |
| Full pytest, **Python 3.13** (CI's version), PostGIS container, `APP_ENV=test`, no PostHog variables, throwaway credentials | Docker | 495 passed, 2 failed, 2 skipped. **The 2 failures are artifacts of my partial copy** (the child-safety tests read `website/` and `infrastructure/nginx/` which I did not copy into the container); they pass in the full local runs. The 2 skips: `bs4` not installed (fixed in the workflow, see below) and the live R2 test |
| Full pytest, Python 3.14 (my venv), PostGIS container | local | 498 passed, 1 skipped (R2 live), 0 failed |
| Migrations up / down to base / up | local PostGIS | pass |
| `flutter analyze`, `flutter test` | local, Flutter 3.44.8 | see TESTS_AND_REGRESSIONS.md |

## Defects found by this review (fixed on this branch)
1. **CI would have failed on test collection.** `tests/test_places_v2_release_unit.py` imports `backend.scripts...`, which needs the repository root on `sys.path`. It worked locally by accident. Fixed with `pythonpath = [".", ".."]` in `backend/pyproject.toml`. This was only found because I ran the suite on Python 3.13 in a container laid out like the repo (`/repo/backend`).
2. **Places-import parser tests were silently skipped in CI** (`bs4` is in the optional `research` extra). The workflow now installs `.[dev,research]`.

## Remaining CI risks (unverified until it runs on GitHub)
- Runner differences (Ubuntu, `localhost` IPv4/IPv6): locally `localhost` made DB tests extremely slow on Windows (IPv6 fallback); on Linux runners it is fine, and `TEST_DATABASE_URL` uses `localhost` as the service container is mapped to the runner.
- Test duration is unmeasured on GitHub; locally the backend suite took 9-14 minutes (docker-on-Windows). Timeout is 25 minutes per job.
- `subosito/flutter-action` resolving `3.44.8` is assumed; if it fails, change `flutter-version`.
- No dependency-vulnerability job (`pip-audit`) and no Android build job.
- `tests/test_feed_map.py` is excluded from `black` (pre-existing formatting debt).

## Safe-test guarantees (verified by tests, not just configuration)
`backend/tests/db_safety.py` is exercised by `tests/test_test_isolation.py`: the dev compose database name, production-style names, remote hosts and names that merely contain "test" as a substring are refused; credentials never appear in the refusal message.

## How to run it on GitHub (needs your approval to push)
```
git push -u origin fix/release-readiness        # or open a PR from the branch into develop
```
Then open Actions, run `CI`, and compare against this document. If a job fails, the first suspects are the Flutter version pin, test time-outs and any test reading files outside `backend/`.
