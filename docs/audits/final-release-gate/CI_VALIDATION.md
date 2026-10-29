# CI validation

**GitHub-hosted CI: NOT VERIFIED. The workflow has never run on GitHub. Nothing was pushed.**

## Static review of `.github/workflows/ci.yml` (final)
| Check | Result |
|---|---|
| Syntax | `actionlint` 1.7.12: no findings (also YAML parses) |
| Runners | `ubuntu-latest` for all jobs; no Windows-only paths |
| Python | 3.13 with pip cache keyed on `backend/pyproject.toml`. I ran ruff, black and the full suite on Python 3.13.15 in a container (`python:3.13-slim`) |
| Services | `postgis/postgis:15-3.4` with health check, mapped to `localhost:5432`; throwaway credentials |
| Database safety | `TEST_DATABASE_URL` points at `mushukistan_test`; `backend/tests/db_safety.py` refuses non-local hosts and names without `test` (covered by `test_test_isolation.py`). The migration step creates and uses a separate `mushukistan_migrations_test` database |
| Environment | `APP_ENV=test`, no PostHog/Firebase/Resend/R2 variables, `RUN_DB_INTEGRATION_TESTS=1`, JWT secret is a throwaway constant |
| Secrets | none referenced; `permissions: contents: read` |
| Install | `pip install -e .[dev,research]` (research extra provides `bs4`, otherwise parser tests silently skip) |
| Flutter | `flutter-action@v2.18.0`, Flutter pinned `3.44.8`, `flutter analyze` then `flutter test`. Java is not needed (no Gradle in CI) |
| Failure reporting | no `--maxfail`, no `|| true`; `-ra` lists skips; concurrency cancels superseded runs |
| Migrations | upgrade, downgrade to base, upgrade on an empty database |

## Problems found (earlier phase, fixed)
Test collection needed the repository root on `sys.path` (`pythonpath = [".", ".."]`), and the `research` extra was missing.

## Findings this phase
1. **A plain `git push` of `fix/release-readiness` will not start CI.** The workflow triggers only on `push` to `main`/`develop` and `pull_request` into `main`/`develop`. The branch must be opened as a pull request into `main` (or `develop`) to be tested before merge.
2. The branch is 25 commits ahead of `main`, containing the earlier phases, so the pull request is large; reviewing it phase by phase (commits are grouped) is practical.
3. `gh` is not installed here and I did not attempt authentication. `origin` is `ssh://git@ssh.github.com:443/SardorEssketi/Mushukent.git`. No upstream is configured for the branch.
4. Actions are pinned by tag, not SHA; no `pip-audit` or Android job.

## What I prepared (without pushing)
`PR_DESCRIPTION.md` in this folder. To run CI, with your approval:
```
git push -u origin fix/release-readiness
# open a pull request into main (web UI), paste PR_DESCRIPTION.md, watch the three jobs
```
CI is marked verified only when all three jobs are green on GitHub. Likeliest first-run failures: Flutter version resolution, a slow job exceeding its timeout, and tests that read files outside `backend/` (the repo root is available in the checkout, so these should pass).
