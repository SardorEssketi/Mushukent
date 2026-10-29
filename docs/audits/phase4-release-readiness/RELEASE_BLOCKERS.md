# Remaining release blockers

## Blocking
1. **Android untested** (no device; emulator ran out of memory). Run the checklist in `ANDROID_TEST_RESULTS.md`.
2. **CI never executed on GitHub.** Push the branch (needs your approval) and confirm all three jobs pass.
3. **Coordinated release of backend and client** for the contact-privacy change (guests on old clients lose Contact Owner).

## Decisions needed (product, not technical)
- Signed-in-only phone numbers vs the public-visibility consent wording; an adoption consent step; reveal rate limits; the rule for JSON `photo_url`.

## Should fix soon
- Replace python-jose, revisit the cryptography pin, add pip-audit and an Android build job to CI, pin actions by SHA.
- Free disk space on the dev machine (C: is full; it broke a test run).
- Lower `-Xmx8G` in `android/gradle.properties` or document the override.
- Investigate the account-switch language check.
- Pre-existing uncommitted work of yours remains in the tree (version bump 0.2.0+9, website, nginx, docs). I did not stage it; review it before release.
