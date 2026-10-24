# Android validation

**Runtime testing: BLOCKED. No Android behaviour was observed in this phase.**

## Device check
`adb devices` (SDK at `D:\Android\Sdk`) lists no devices. No physical device is connected. Per the instructions I did not retry the emulator: in Phase 4 it failed three times for lack of memory (`Needed 4096 MB / Remaining ~3.9 GB`, then a qemu `failed to allocate` crash), and the machine is still memory- and disk-constrained (a background disk scan was killed by the system this session for low memory).

## Test plan, ready for a device (requires your approval before any install)
Preconditions: a **test device or a spare phone**, USB debugging on, an isolated backend reachable from it (`adb reverse tcp:18440 tcp:18440` and `MUSHUKISTAN_API_BASE_URL=http://127.0.0.1:18440/api/v1`, or the host LAN address), seeded test accounts (the scripts in `docs/audits/phase4-release-readiness/` seed three users). Use a debug build of `uz.mushukistan.app`; if the device already has the production app installed, an install of the same package with a different signature would fail or replace it, so use a device without the app or ask first. Never use real user accounts.

| # | Area | Steps | Expected |
|---|---|---|---|
| 1 | Startup | cold start, airplane-mode cold start | feed loads; offline start shows retry/notice, not a crash |
| 2 | Authentication | register/verify (dev token), login, kill app, relaunch | session restored without login |
| 3 | Feed and map | open feed, map, location permission deny/allow | markers load; denial handled |
| 4 | Posts and photos | create observation with camera and gallery photo | upload succeeds, post visible |
| 5 | Blocking | Alice blocks Bob, check feed/comments, unblock | content hidden both ways, restored |
| 6 | Settings | edit profile, change language, change privacy toggle | persisted |
| 7 | Language persistence | choose Russian, kill app, enable airplane mode, relaunch | outage screen shown in Russian |
| 8 | Outage and recovery | stop backend while signed in, navigate, restart backend | retry screen, no logout, automatic recovery |
| 9 | Notifications | grant/deny `POST_NOTIFICATIONS`, tap a notification | opens the right screen (needs Firebase config; may be BLOCKED without it) |
| 10 | Lifecycle | background 5 min, rotate, foreground | state kept, session valid |
| 11 | Contact flow | guest taps Contact Owner on a lost-pet post | sign-in prompt; after login number appears |

## Release build configuration (verified separately from runtime)
| Item | Result |
|---|---|
| Release APK (`flutter build apk --release`, Gradle `-Xmx2g`) | built, 65.9 MB, `apksigner verify` OK (v2) |
| Release AAB (`flutter build appbundle --release`, same flags, dummy dart-defines) | **built**, 64.0 MB (`app-release.aab`) |
| AAB signature | `jarsigner -verify` reports signature verified (signed with the local upload key in the git-ignored `android/key.properties`) |
| Application id / version | `uz.mushukistan.app`, `0.2.0+9` (uncommitted change in `pubspec.yaml`: the committed value is `0.1.0+8`; the version code must be higher than what is on Play) |
| SDK levels | `compileSdk 36`; `minSdk` and `targetSdk` inherit the Flutter 3.44.8 defaults (not checked against the current Play target-API requirement; check in Play Console pre-launch report) |
| Signing | release config is applied only if `key.properties` exists; **without it the release build is silently unsigned**. CI has no Android job, so this is only caught locally |
| Gradle heap | `android/gradle.properties` requests `-Xmx8G`, which killed the Gradle daemon on this machine; builds pass with `--android-project-arg=org.gradle.jvmargs=-Xmx2g` |
| Minify/shrink | not configured (defaults) |
| Reproducibility | not tested (builds run once) |
| Firebase | `google-services` handling and the real `google-services.json` were not inspected (secret/production file) |

## Verdict for this section
Build configuration: **PASS** for signed APK and AAB production on this machine (with the heap override). Runtime: **BLOCKED** (no device). Nothing about Android runtime is claimed.
