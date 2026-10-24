# Phase 4 - Release readiness report

Branch `fix/release-readiness` (from `fix/reliability-ci`). Not pushed, merged or deployed. Nothing touched production.

## Verdict
**Not declared release-ready.** The backend and the shared Flutter logic are in good shape on the evidence below, but two gates are open: (1) Android was **not** run on any device or emulator, and (2) GitHub Actions has **never run** on this workflow. Product decisions on phone-number exposure are also open. See `RELEASE_BLOCKERS.md`.

## Confirmed (evidence in this folder)
- Backend: 498 passed, 1 skipped (live R2), 0 failed on a disposable PostGIS container; ruff and black clean; migrations up/down/up pass.
- Flutter: `flutter analyze` no issues; `flutter test` 432 passed, 4 skipped, 0 failed.
- Real-browser run (mobile viewport, isolated backend and DB): outage/recovery 24 of 25 checks. Language persistence check 4/4: a cold start during an outage shows the retry screen in the saved language (Uzbek).
- Live API on the isolated backend: anonymous detail and list have no phone number and show `contact_available`; a signed-in user gets the number on detail only; non-owner cat PATCH returns 403.
- Contact privacy and cat-edit authorization are implemented and tested (`docs/CONTACT_PRIVACY.md`, `docs/CAT_EDITING.md`).
- CI review found and fixed two real CI defects (test collection path, silently skipped parser tests). actionlint is clean.
- Release APK builds and is signed with the local upload key (signature verified; not installed or run).

## Corrections and open questions
- The audit's cat-cover finding was partly inaccurate: PATCH never stored the URL, but POST did. Both are now validated.
- One browser check still fails: after switching accounts without a reload, the UI did not switch to the second account's language (Russian). The language follows the account's `preferred_language` after login; I did not investigate this further. **Unresolved**, probably low severity.
- Skipped Flutter tests: 3 live-backend smoke tests (opt-in; I ran them against the isolated backend and they passed 3/3) and 1 web-only HEIF test. The HEIF test could not be run because the C: drive filled up during `--platform chrome`, so it is **untested**.

## Untested
Android runtime (all items), GitHub Actions, Google sign-in, FCM delivery, R2 storage, production configuration and `.env`, load behaviour, web HEIF conversion test, browser re-run of blocking and rate-limit scenarios this phase.

## Files
`RELEASE_BLOCKERS.md`, `SECURITY_PRIVACY_FINDINGS.md`, `ANDROID_TEST_RESULTS.md`, `CI_VALIDATION.md`, `TESTS_AND_REGRESSIONS.md`, `COMMITS_AND_FILES.md`, `DEPLOYMENT_SEQUENCE.md`, plus raw outputs (`p4_*.txt`, `docker_ci2.txt`), scripts and `screenshots/`.
