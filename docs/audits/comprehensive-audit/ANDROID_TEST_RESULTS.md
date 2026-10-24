# Android Test Results

**Runtime testing on Android was not possible in this environment. Nothing below claims an Android behaviour was observed.**

## What was verified
| Check | Result |
|---|---|
| Debug APK build | **Succeeded**: `flutter build apk --debug --dart-define=MUSHUKISTAN_API_BASE_URL=http://10.0.2.2:18400/api/v1 --dart-define=MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID=...` produced a 169 MB debug APK, but only after overriding the Gradle heap: `--android-project-arg=org.gradle.jvmargs=-Xmx2g` |
| Default Gradle build | **Failed twice**: "Gradle build daemon disappeared unexpectedly". `frontend/android/gradle.properties` asks for `-Xmx8G -XX:MaxMetaspaceSize=4G`, which this machine could not commit |
| Toolchain | Android SDK at `D:\Android\Sdk`, AVD `Medium_Phone` (x86_64, Google APIs + Play Store), WHPX acceleration usable (`emulator-check accel`). `flutter doctor` flags unaccepted Android licenses |
| Dart/Flutter tests and analysis | 385 tests pass and `flutter analyze` is clean (these cover notification lifecycle, settings navigation and nearby-alert logic in unit/widget form) |
| Release build | **Not built.** No release keystore is available to me, and `build.gradle.kts` silently skips release signing when the keystore properties file is missing |

## Precise blocker for runtime testing
The emulator refused to start on every attempt (four) with: `Needed: 4096 MB` of free commit charge versus `Remaining` between 404 MB and 3,701 MB (commit limit 34,539 MB; about 31 GB already committed by WSL2 `vmmemWSL` ~5 GB, Java/IDE processes, browsers and others). Lowering `-memory` did not change the requirement. I did not close the user's other applications to make room.

To finish Android testing: free about 5 GB of commit charge (or raise the Windows page file), then run `emulator -avd Medium_Phone`, `adb install -r frontend/build/app/outputs/flutter-apk/app-debug.apk`, start the backend on `127.0.0.1:18400` and pass `--dart-define` as above.

## Static review of Android configuration
- `AndroidManifest.xml`: permissions INTERNET, ACCESS_COARSE_LOCATION, ACCESS_FINE_LOCATION, POST_NOTIFICATIONS; Firebase auto-init and analytics collection disabled; no cleartext or network-security overrides.
- **No deep-link / app-link intent filters** (only the launcher filter and a `text/plain` process-text query). Web URLs shared as `https://mushukistan.uz/posts/{id}` will not open the app. Treat as a product gap, not a bug, unless links are a launch requirement.
- No `android:allowBackup` attribute, so the platform default (enabled) applies.
- Release signing is conditional on `key.properties`; no minify/shrink configured (`build.gradle.kts`, F-10).
- `google-services.json` exists locally but is not tracked by git (`git ls-files` returned nothing).

## Not tested (all runtime items requested)
Startup, authentication persistence, navigation, image upload, lifecycle, notification permission, deep links, background/foreground, release build configuration at runtime.
