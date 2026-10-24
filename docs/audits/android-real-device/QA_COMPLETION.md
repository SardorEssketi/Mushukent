# Android QA completion (second device session)

Device: TECNO KJ7, Android 14. Test package `uz.mushukistan.app.rdtest` only; production `uz.mushukistan.app` stayed v0.1.0 and untouched. With your approval I ran `pm clear` on **the test package only**. Isolated backend and a fresh disposable PostGIS database (removed afterwards). No Android system settings were changed. The first session's report is `README.md`.

## 1. Git check of `2484e79`
Contains exactly three files: the contrast fix (`publication_detail_parts.dart`), its regression test (`publication_contact_button_test.dart`) and the opt-in debug package-id option in `build.gradle.kts` (the release build and default debug build are unchanged; with the option unset nothing differs). Not pushed. `main` untouched.

## 2. First-login investigation
**Reproduced and fixed.** Not an unexplained backend problem.

| Item | Finding |
|---|---|
| Symptom | Backend `login` succeeded but the Login screen stayed on top until restart |
| Root cause | The Feed's Login button opens `/login` with `context.push`. After sign-in the router listener (`app_router.dart`) decided whether to leave the auth screen by reading `router.routeInformationProvider.value.uri`. For a **pushed** page that value still says `/feed` (verified with a probe: provider `/feed`, delegate last match `/login`), so the listener never called `router.go(...)` and the pushed Login page stayed visible. The auth state itself was correct (authenticated); only navigation was stale. Auth state transitions, legal acceptance and the onboarding overlays were not the cause |
| Why it was intermittent | It only happens when Login was opened with `push` from the feed or another page; opening Login by redirect (protected route) goes through `go` and works |
| Fix | `_visibleUri(router)` returns the last match of the delegate configuration, so a pushed Login/Register is recognised and left after authentication. Redirect behaviour for legal acceptance, outages and onboarding is unchanged |
| Regression tests | `login opened from the feed Login button`: login from the pushed screen reaches the feed; same after logout and login. Both **failed before** the fix (`Found 1 widget with type "LoginScreen"`) and pass after |
| On the phone | Fresh state (`pm clear` of the test package): first launch signed out, feed Login button, credentials, **first login went straight to the feed behind the onboarding dialogs; no Login screen left behind** |
| Also exercised | cold start with a restored session (signed in, no login screen), logout then login, account switch to a second account (its language applied), registration then login |
| Remaining uncertainty | The original observation was on the first build; I cannot prove it was this exact path, but the same symptom is now reproduced in a widget test, fixed, and the identical device flow passes |

## 3. Scenarios completed on the phone (this session)
| Scenario | Result |
|---|---|
| Registration (form, consent checkbox) | PASS (DB row with current terms version `2026-10-15`) |
| Email verification | PASS via the development-only "Verify now" path (the backend returns a dev token in development). Real email delivery: **BLOCKED**, not tested |
| First login, cold start, restored session, logout/login, account switch | PASS |
| Cat observation (photo from the system picker, location chosen on the map, name) | PASS; row in `cats`/`posts`, shown in the feed with the photo |
| Map markers and details | PASS: lost-pet marker via "View on map", bottom sheet with title and "Open post" opened the post |
| Comment (typed in the app) | PASS; comment row, "Comment posted" |
| Like | PASS; count 1, like row, heart filled |
| Lost-pet report with photo, map point, consent checkbox | PASS; consent version 1 stored |
| Owner view of own lost pet (no Contact Owner, Edit/Delete/Mark as found) | PASS |
| Mark as found (resolve) | PASS; "Reunited", contact hidden message |
| Delete own test post | PASS (`deleted_at` set; gone from the feed) |
| Guest view: Contact Owner for a guest | PASS: shows "Account required", **no reveal request** reached the backend |
| Contact reveal and quota | PASS in the first session (limit of 2: third reveal returned 429 with message); not repeated |
| Adoption post create/consent | PASS in the first session; the adoption **view** by another user was not repeated |
| Back button, keyboard | PASS: Back closes pickers/dialogs/menus and leaves screens; the keyboard moves the form; note: Back with the keyboard already closed leaves the form (normal) |
| Language layouts | PASS for Russian and Uzbek bottom bar; English bottom bar fixed (below) |

## 4. Cosmetic issues
| Issue | Result |
|---|---|
| "Leaderboard" bottom-tab label wrapped to two lines | **Fixed.** `NavigationBarTheme` label style 11 sp with zero letter-spacing/padding. Test `bottom_nav_labels_test.dart` loads the real Manrope font and checks all 15 labels (en/ru/uz) stay on one line; it failed for Leaderboard, Добавить and Qo‘shish before the change and passes after. On the phone: "Leaderboard" now on one line |
| Legal-update title truncated in the app bar | **Fixed.** The app bar title was removed (the heading in the page already carries it). Widget test checks the full title once in English, Russian and Uzbek and that no `AppBar` is shown. Not visually re-checked on the phone (it only appears for a user with outdated acceptance; the earlier session screenshot showed the truncated version) |

## 5. Validation
| Check | Result |
|---|---|
| `flutter analyze` | no issues |
| `flutter test` | 452 passed, 4 skipped, 0 failed |
| Backend tests | not re-run: no backend change in this session |
| Logcat (whole session, test app) | 0 `FATAL EXCEPTION`, 0 `ANR in`, 0 `RenderFlex overflowed`, 0 Flutter errors, 0 crash lines for the test package |
| Device smoke tests | as in section 3 |

## 6. Privacy hygiene during testing
Several screenshots unintentionally captured your personal notification banners (Telegram). Each such file was **deleted immediately and its content not recorded**; one was also a phone home screen. Screenshots kept are of the test app only. I did not change notification settings; to avoid this you could enable Do Not Disturb before the next run.

## 7. Not verified
Google Sign-In (no OAuth client for the test package id), push/FCM delivery and notification opening (no isolated Firebase project), real email, real R2 storage, the signed release build on a device, production data. Not repeated this session: adoption view by another user, deleting an adoption post, contact-limit message in Russian/Uzbek.

## 8. Remaining Android blockers
1. Push and Google sign-in need an isolated Firebase/OAuth test setup (or a controlled test with production configuration).
2. Install and smoke-test the **signed release** build (not the debug test package) before release.
3. Uninstall `uz.mushukistan.app.rdtest` from the phone when you no longer need it (needs your approval; I did not).

## 9. Commits ready for PR #1 (local, **not pushed**)
`2484e79` contrast fix and opt-in test package id; `8c94fa8` leave the pushed Login screen after sign-in; `a48f85a` regression tests (login from feed, legal title, isolated language mock); `b25c599` bottom-nav labels and legal-update title; `44b644e` correct the test-package build command. Pushing needs your explicit authorization.
