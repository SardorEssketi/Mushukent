# Android real-device validation

Branch `fix/release-readiness` (PR #1 head `b8b48f9` plus the local commit described under "Fixes"). Nothing was pushed, merged or deployed. No production access.

## Device and build
| Item | Value |
|---|---|
| Device | TECNO KJ7 (`115333744V005830`), Android 14 (API 34), arm64-v8a, 1080x2436 |
| ADB | `adb devices -l` showed the device as `device` (authorized) |
| Production app on the phone | `uz.mushukistan.app` v0.1.0 (code 8), installed through the Android package installer, **not touched** (still v0.1.0 at the end) |
| Test app | `uz.mushukistan.app.rdtest`, debug APK `0.2.0+9` (197 MB), signed with the standard Android debug key (cert SHA-256 `2a222fbc...9277`), which differs from your release key |
| Why a different package id | A debug build with the production id could not be installed over the release-signed app (signature mismatch) and a release-signed update would have replaced your production app. A new opt-in Gradle property (`-Ptest-application-id-suffix=.rdtest`, via `--android-project-arg=test-application-id-suffix=.rdtest`) adds an `applicationIdSuffix` to the debug build only; default builds are unchanged. A first build used a malformed property and still had the production id; I caught it with `aapt2` **before** installing and rebuilt |
| Consequences of the suffix | Push is unavailable (the production `google-services.json` matches only `uz.mushukistan.app`, so the plugin is skipped); Google sign-in cannot work for this package id |
| Install | with your explicit approval: `adb install -r` of the debug APK, `adb reverse tcp:18440 tcp:18440`, three generated test JPEGs pushed to `/sdcard/Pictures/rdtest/` |
| Cleanup done | test images and UI dump removed from the phone, `adb reverse` removed, test app force-stopped. **The test app `uz.mushukistan.app.rdtest` is still installed**; uninstall it from the phone or tell me and I will (needs your approval) |

## Backend environment
Disposable PostGIS container (`postgis/postgis:15-3.4`, local port 55436, removed afterwards), migrations to head `20261015_0027`, backend from this branch on `0.0.0.0:18440` with `APP_ENV=development`, rate limiting off, **`CONTACT_REVEAL_MAX_PER_DAY=2` and `..._PER_WEEK=5`** (lowered so the quota can be reached by hand), local media storage. Test accounts only (`bf-alice`, `dev-dave`, `dev-legal`, `dev-ru`, ...); one account (`dev-legal`) had its accepted legal versions set to `2026-08-01` directly in the test database. Reached from the phone through `adb reverse` (cleartext HTTP is allowed in debug builds only).

## Results
Legend: PASS = executed on the phone. FAIL = confirmed problem. BLOCKED = needs a credential/service I do not have. NOT TESTED = not executed.

### Authentication
| Scenario | Result | Notes |
|---|---|---|
| Registration | NOT TESTED | accounts were created through the API |
| Password login | PASS | `login`, `users/me`, feed calls seen in the backend log. See the first-login observation below |
| Session restoration after restart | PASS | force-stop and relaunch: signed in, notification badge present |
| Session after OS process kill | PASS | `am kill` then relaunch: signed in, Russian kept |
| Google Sign-In | BLOCKED | button is shown but no OAuth client exists for the test package id |
| Updated Terms/Privacy acceptance | PASS | `dev-legal` was routed to "We updated our Terms and Privacy Policy"; DB `2026-08-01` before, `2026-10-15` only after tapping **Accept and continue**; then continued to the feed |
| Logout | PASS | confirmation dialog, then signed out (backend `POST /auth/logout 204`) |
| Account switching | PASS | Alice, then `dev-legal`: nothing of the first account shown |

### Core
| Scenario | Result | Notes |
|---|---|---|
| Feed | PASS | cards, tabs, images load from the backend |
| Map | PASS (tiles) / NOT TESTED (markers) | OpenStreetMap tiles render; I did not locate the test markers |
| Cat observation, lost-pet creation | NOT TESTED | |
| Create adoption post with photo (system photo picker, real upload) | PASS | picked a test JPEG, post created (201), photo shown in the feed, DB stored `contact_consent_version=1` |
| Comments and likes | NOT TESTED | |
| Lost-pet detail | PASS | |
| Public profile | PASS | |
| Settings (theme, language, privacy toggle visible, notifications, blocked users) | PASS | language change needs **Save changes** and then applies |

### Privacy and security
| Scenario | Result | Notes |
|---|---|---|
| Block / unblock | PASS | profile menu, confirmation, `POST .../block 204`; the blocked user disappears from the feed (checked by API for the same account) and returns after "Blokdan chiqarish" |
| Contact Owner reveal | PASS | detail shows no number; one tap produced `contact-reveal 200` then `contact 204`; number appeared on the button; Android showed its dialer chooser (I closed it, nothing dialled) |
| Reveal quota | PASS | with the test limit of 2: two reveals worked, the third returned 429 and the app showed "You have viewed the maximum number of owner contacts for now. Try again later." with no number |
| No contact for guests | NOT TESTED on the phone | covered by backend and Flutter tests and the earlier browser/API checks |
| Consent checkbox (adoption) | PASS | unchecked by default; Russian wording shown in full; publishing without it showed "Confirm that signed-in users may see your contact details" in Russian and sent no request; checked, it published |

### Reliability and localization
| Scenario | Result | Notes |
|---|---|---|
| Outage while signed in | PASS (backend outage) | I stopped the **backend** (exact PID) instead of changing your phone's Wi-Fi/mobile settings; the app stayed signed in, a cold start showed "Can't reach the server. You are still signed in..." with Retry and Continue browsing |
| Recovery | PASS | backend restarted; the app returned to the profile by itself, no input |
| Restart | PASS | see above |
| Russian | PASS | onboarding, nav, add menu, forms, consent, block dialog, settings |
| Uzbek | PASS | nav, profile, settings, notification settings, blocked users |

### Notifications
| Scenario | Result | Notes |
|---|---|---|
| Notification permission state | PASS | Settings shows "Android notification permission: Not granted" and offers "Open Android settings"; I did not grant it |
| Notification center | PASS | opens; empty state shown (an earlier test comment produced a badge of 1) |
| Push delivery (foreground/background), opening a notification | BLOCKED | no isolated Firebase project; the app itself says push is unavailable without permission and a configured push service. Not simulated |
| Location prompt | PASS | "Nearby alert privacy" consent dialog appears; I chose "Do not use my location" |

### Android-specific
| Check | Result | Notes |
|---|---|---|
| Crashes / runtime exceptions | PASS | logcat (whole session) had no `FATAL EXCEPTION`, `ANR in`, `RenderFlex overflowed` or Flutter errors |
| Lifecycle (HOME, resume, process death) | PASS | |
| Back button | PASS | closes the dialer chooser, leaves detail and settings screens |
| Photo picker / upload | PASS | |
| Keyboard | PASS | the keyboard covers lower fields as normal; the form scrolled |
| Network config | PASS | cleartext only in the debug manifest; the release manifest does not enable it |
| Layout | FAIL (cosmetic, not fixed) | the English bottom-bar label "Leaderboard" wraps to "Leaderboar / d" at this width; Russian/Uzbek labels fit. The legal-update app-bar title is also truncated ("We updated our Terms and Priva...") |

## Defects
| # | Finding | Status |
|---|---|---|
| 1 | **Contact Owner button text unreadable**: the label and the revealed number used the default dark text colour on the orange primary fill (the number was almost invisible). Root cause: explicit `TextStyle`s in `PublicationContactButton` override the button foreground. Fix: use `onPrimary` (primary button) or `primary` (secondary). Regression test `publication_contact_button_test.dart` (3 tests, fail without the fix, pass with it). **Re-verified on the phone**: light text on orange. | FIXED (local commit, not pushed) |
| 2 | After the very first login of `bf-alice`, the Login screen with the typed credentials stayed visible after the onboarding dialogs, although the backend showed login and profile calls; a restart opened the signed-in feed. I could not reproduce it with `dev-legal` (the legal screen took over). | **NOT RESOLVED**: observed once, not reproduced, no root cause. A fresh-account first login on a device should be repeated |
| 3 | The onboarding dialogs (location, language, welcome) appear over the legal-acceptance screen for a new device session. | open UX observation |
| 4 | "Leaderboard" wrapping and the truncated legal title (above). | open, cosmetic |

## Things that went wrong during testing (disclosed)
- One adb tap landed on the keyboard's voice-input key and opened Gboard's voice-typing settings; I went back without changing anything.
- A path mangling in Git Bash briefly tried to create `C:/Program Files/Git/sdcard` on the phone; it failed (read-only file system), no effect.
- Your real Telegram notification banner appeared in one screenshot; I deleted that file immediately and did not record its content. Other unviewed screenshots were also deleted. Screenshots kept here were viewed and contain only the test app (and test account data).
- My first APK had the production package id; caught before installation.

## Not verified as production integrations
Google sign-in, FCM push, real R2 storage, the production backend and configuration, the signed release build on a device, and anything involving your real account data.

## Remaining release blockers
1. Repeat the first-login flow on a device (finding 2) and the unexercised scenarios above (registration, cat observation, lost-pet creation, comments/likes, guest contact view, map markers).
2. Push/FCM and Google sign-in on a device need an isolated Firebase/OAuth setup for a test package id, or a controlled test with the production configuration.
3. Production preflight and real R2 upload test (`docs/audits/release-blockers/BLOCKER_STATUS.md`).
4. Native-speaker and legal review of the Russian/Uzbek and legal wording.
