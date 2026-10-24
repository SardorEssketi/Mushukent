# Android test results (Phase 4)

**Android runtime verification was not possible. No Android behaviour below was observed.**

## What was done
| Item | Result |
|---|---|
| Physical device | None connected (`adb devices` empty). Nothing was installed on any personal device. |
| Emulator `Medium_Phone` (x86_64, API 36 image, WHPX available) | Tried three times. Attempt 1/2: refused to start, Windows commit charge short (`Remaining 3,932 MB, Needed 4,096 MB`). Attempt 3: it started and `adb` saw `emulator-5554` but stayed `offline`; the qemu process then crashed with `failed to allocate 59392 bytes` (out of memory) and was killed by PID. |
| Environment cause | `C:` is 100% full (3 MB free at its worst, about 0.6 GB after I deleted my own scratch files) and the machine runs close to its commit limit (about 31 of 33 GB committed: WSL2 ~5 GB, IDE JVMs, browsers). The same pressure killed the Gradle daemon (see below) and made `flutter test --platform chrome` fail with "not enough space on the disk". |
| Debug APK build | Succeeds only with `--android-project-arg=org.gradle.jvmargs=-Xmx2g`, and only when the emulator is not running. The default `-Xmx8G` in `frontend/android/gradle.properties` makes the Gradle daemon disappear on this machine. |
| Release APK build | `flutter build apk --release` (same heap override, dummy dart-defines) **succeeded**: 65.9 MB. |
| Release signing | `frontend/android/key.properties` exists locally (git-ignored) and the build used it. `apksigner verify` reports **Verifies: true**, APK Signature Scheme v2 only (v3/v3.1 not present), signer `CN=Mushukistan Upload, OU=Android, O=Mushukistan, L=Tashkent, ST=Tashkent, C=UZ`, certificate SHA-256 `d687512c...f50d`. Note: the key is an *upload* key; Play App Signing is assumed. |
| Reproducibility | Not verified (the release build was run once). |
| Config review | `build.gradle.kts`: release signing is applied only when `key.properties` exists; without it the release build is **unsigned** (not debug-signed), which is the safe outcome but is silent. No explicit minify/shrink settings (Flutter/AGP defaults apply). `AndroidManifest.xml`: INTERNET, coarse/fine location, POST_NOTIFICATIONS; Firebase auto-init and analytics collection disabled; no deep-link intent filters; `allowBackup` not set (platform default). |

## Not verified (all requested runtime items)
Login and session recovery, blocking/unblocking, notification permission and delivery, network-outage recovery, post creation and photo upload, navigation, startup/lifecycle (background/foreground), deep links.

## What substitutes, and what it does not
The same Dart code runs on Web and Android and was tested on Web in a real browser (see TESTS_AND_REGRESSIONS.md) and by 400+ Flutter unit/widget tests. That covers shared logic only. It does **not** cover Android-specific behaviour: secure token storage, FCM and runtime permissions, `AppLifecycleState.resumed` behaviour after the OS suspends the app, the photo picker and camera, Android network stack error types (the outage classification in `ApiFailureKind` maps Dio error types, which differ slightly from Web).

## How to finish Android validation
1. Free about 6 GB on `C:` and 6 GB of commit charge (close WSL2/Docker Desktop or raise the Windows page file), or connect a physical device with USB debugging.
2. Start the isolated backend on `0.0.0.0:18440` (`docs/audits/phase4-release-readiness/` scripts), seed with `p4_run.py`'s seed helper.
3. `flutter build apk --debug --android-project-arg=org.gradle.jvmargs=-Xmx2g --dart-define=MUSHUKISTAN_API_BASE_URL=http://10.0.2.2:18440/api/v1 --dart-define=MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID=x`, `adb install -r`, then run the checklist above. **Ask before installing on a personal device.**
