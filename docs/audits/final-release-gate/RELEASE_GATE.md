# Release gate

Branch `fix/release-readiness` (HEAD `8f818b6`, 26 commits ahead of `main`). Nothing was pushed, merged or deployed. No production access. The project owner's uncommitted changes are untouched.

## Verdict: NOT READY

Technically the code is in good shape (see PASS items), but three requirements cannot be verified in this environment and one needs a product decision. "Ready" needs the items under **What is needed for READY**.

## Requirements

| # | Requirement | Status | Notes |
|---|---|---|---|
| 1 | Backend test suite on disposable PostGIS | **PASS** | 498 passed, 1 skipped, 0 failed |
| 2 | Ruff and Black | **PASS** | clean |
| 3 | Flutter analyze and tests | **PASS** | no issues; 433 passed, 4 skipped |
| 4 | Browser smoke (outage/recovery/logout/account switch) | **PASS** | 25/25 (earlier 24/25 was invalid seed data) |
| 5 | Language switches with the account | **PASS** | regression test added; no code change needed |
| 6 | Language persists during outage | **PASS** (web) | tested in browser last phase and by widget tests; Android secure storage not tested |
| 7 | Anonymous cannot read contact fields | **PASS** | tests and live API |
| 8 | Contact enumeration by signed-in users limited | **DECISION REQUIRED** | only the generic 60/min per-user limit (about 86k reads/day/account); recommended reveal-only-via-contact-event plus quotas (PRIVACY_AND_COMPATIBILITY.md) |
| 9 | Owners told accurately who sees their number | **DECISION REQUIRED** | texts say "public"; actual behaviour is signed-in only; adoption records consent without a checkbox |
| 10 | Old client compatibility | **PASS with accepted change** | signed-in contact works on old clients; guests on old clients lose the button; no private data exposed for compatibility |
| 11 | Release APK builds and is signed | **PASS** | verified with apksigner |
| 12 | Release AAB builds and is signed | **PASS** | 64.0 MB, jarsigner verified |
| 13 | Android runtime behaviour | **BLOCKED** | no device; emulator not retried (memory) |
| 14 | Notification permission and navigation on Android | **BLOCKED** | needs device and Firebase config |
| 15 | GitHub Actions workflow valid | **PASS (static)** | actionlint clean; Python 3.13 run matches CI |
| 16 | GitHub Actions actually succeeds | **BLOCKED** | needs your approval to push and open a PR into `main` (a plain branch push does not trigger CI) |
| 17 | Production config preflight | **BLOCKED** | checklist prepared; production was not accessed |
| 18 | Real R2 upload | **BLOCKED** | needs credentials; test skipped |
| 19 | Web HEIF conversion test | **BLOCKED** | needs Chrome test run, disk space |
| 20 | Dependency risk (python-jose CVE without fix; cryptography pinned below 50) | **DECISION REQUIRED** | judged not exploitable as configured; replace python-jose after release or accept |
| 21 | Version bump (`0.2.0+9`) and other pre-existing uncommitted changes | **DECISION REQUIRED** | uncommitted, not reviewed or tested by me beyond the builds; commit deliberately |

## Environment (drive C:)
C: is 150 GB with about 1 GB free. Read-only inspection (nothing deleted):

| Item | Size | Class | Note |
|---|---|---|---|
| `C:\pagefile.sys` | 17.4 GB | system | Biggest single item. Moving the page file to D: (41 GB free) frees most of it and removes the commit-limit pressure that killed the emulator and Gradle. Needs admin and a reboot: your call |
| `C:\hiberfil.sys` | 6.3 GB | system | `powercfg /h off` frees it if you don't use hibernate/fast startup |
| `%LOCALAPPDATA%\Programs\Python` | 5.7 GB | user software (Python39 with torch/CUDA) | not regenerable without reinstall; leave unless unused |
| `%LOCALAPPDATA%\Temp` | 3.2 GB | **regenerable** | includes `flutter_tools.*` (about 0.2 GB each), `DiagOutputDir` 0.5 GB, `mushukistan-cdp-review` 0.1 GB, installer leftovers |
| `AppData\Roaming` | 8.6 GB | user data/apps | Telegram Desktop 2.1 GB, JetBrains 1.5 GB: **user data, do not delete** |
| `npm-cache` | 1.7 GB | **regenerable** | `npm cache clean --force` |
| `pip` cache | 0.9 GB | **regenerable** | `pip cache purge` |
| Pub cache (`Local\Pub\Cache`) | 0.7 GB | regenerable (re-downloads) | |
| `.cache\huggingface` + `.deepface` | about 2 GB | user data (models) | |
| `Downloads`, OneDrive, WSL `ext4.vhdx` (1.5 GB) | | user data | leave |

Smallest safe plan, needing your approval: clear `Temp\flutter_tools.*`, `Temp\DiagOutputDir`, `npm-cache` and `pip` cache (about 5-6 GB). A Flutter/Android build already succeeded at about 1 GB free (build output goes to D:), but the web Chrome test failed once when free space hit 0. Moving the page file would remove the underlying problem.

## What is needed for READY
1. Android: run the plan in `ANDROID_VALIDATION.md` on a real test device, with your approval for the install (or free memory and approve one emulator attempt). All runtime items must pass.
2. CI: with your approval push the branch, open a pull request into `main`, and get all three jobs green.
3. Decide items 8, 9 and 20 (contact reveal policy and wording, dependency risk), or record them as accepted risks (then the verdict becomes READY WITH ACCEPTED RISKS once 1 and 2 pass).
4. Operator runs `PRODUCTION_PREFLIGHT.md` against the real environment and a real R2 upload test; then back up the database and deploy backend and client together as described in `docs/audits/phase4-release-readiness/DEPLOYMENT_SEQUENCE.md`.
5. Re-run the web HEIF test after freeing disk space.

## Files in this folder
`ANDROID_VALIDATION.md`, `CI_VALIDATION.md`, `PRIVACY_AND_COMPATIBILITY.md`, `PRODUCTION_PREFLIGHT.md`, `FINAL_TEST_RESULTS.md`, `PR_DESCRIPTION.md`, raw outputs `final_full.txt`, `final_mobile.txt`. This folder is uncommitted, like the earlier audit folders.
