# Final integration readiness (2026-10-18)

Branch `fix/release-readiness`. Nothing was installed on the phone, no email or push was sent, no production user was created, no cloud setting was changed, nothing was deployed or merged. Only read-only checks and one local release build were performed.

## Verdicts
| Integration | Result | Basis |
|---|---|---|
| Google Sign-In, configuration consistency | **PASS** | Backend `GOOGLE_OAUTH_CLIENT_ID`, the AAB's embedded `serverClientId` and the build-script format check are the same value; the backend verifies the token audience against it |
| Google Sign-In, Android OAuth client for `uz.mushukistan.app` + SHA-1 | **BLOCKED** | Lives in Google Cloud project `441892...`; no console access. Not verifiable from outside |
| Google Sign-In, real device | **BLOCKED** | Needs the real package; it cannot be installed over production and the `.rdtest` id has no OAuth client |
| FCM, server side | **PASS** | Service account project = `FIREBASE_PROJECT_ID` = `google-services.json` project (`mushukistan-9ab90`); a Firebase Admin `dry_run` send authenticated and was rejected only for the fake token. Nothing was delivered |
| FCM, client build | **PASS** | AAB manifest/resources contain project `mushukistan-9ab90`, sender `618068451530`, package `uz.mushukistan.app`, `POST_NOTIFICATIONS`, no background location; built with push enabled |
| FCM, real delivery | **BLOCKED** | Needs the production package on a device and one push to a test account token |
| Email, DNS/sender | **PASS (DNS) / UNVERIFIED (Resend status)** | `resend._domainkey` DKIM, `send.` SPF + MX (SES) and `_dmarc` `p=none` are all published. `RESEND_API_KEY` is send-only, so domain status cannot be read through the API |
| Email, real delivery | **BLOCKED** | Needs one test email to a mailbox you control |

## Configuration mismatches
1. `.env` defines `EMAIL_FROM`, but the backend reads `RESEND_FROM_EMAIL` (`backend/app/core/config.py:60`). Harmless today because the code default is the same `noreply@mushukistan.uz`, but the variable is ignored. Rename it in the server `.env`.
2. The Firebase project (`618068451530`) and the OAuth client project (`441892...`) differ. Documented as acceptable (the app passes `serverClientId` explicitly). Do not replace the OAuth client with the Firebase auto-generated web client.
3. `docs/DEPLOYMENT.md` "Canonical production AAB build" omits `-EnableAndroidPush`; without it the Play build has no push. This AAB was built with it. (Not edited: that file has your uncommitted changes.)
4. Apex `mushukistan.uz` has no SPF TXT and DMARC is `p=none`. Not a blocker (Resend aligns on `send.` and DKIM); tighten DMARC after a monitoring period.

## Android package, signing, version
| Item | Value |
|---|---|
| Package id | `uz.mushukistan.app` (AAB, installed app and `google-services.json` all agree) |
| Version | AAB `0.2.0` / versionCode **9**. Installed production app: `0.1.0` / **8** (sideloaded, not from Play). Commit `0bfdbfd` records the bump |
| Play versionCode history | **Not verifiable** (no Play Console access). 9 must never have been uploaded |
| Upload cert SHA-1 | `A0:FB:0D:BA:4F:4A:23:08:F1:6A:5D:75:08:57:12:48:CE:38:02:BB` |
| Upload cert SHA-256 | `D6:87:51:2C:BE:AC:E6:D2:E3:E4:38:01:BB:ED:6F:E7:D6:68:5C:80:94:47:3A:28:C6:D8:3F:3F:35:97:F5:0D` |
| Signing compatibility | **PASS**: the keystore, the new AAB and the installed production APK carry the identical certificate |
| AAB | `frontend/build/app/outputs/bundle/release/app-release.aab`, 67,271,141 bytes, SHA-256 `a87eeffcc951f3ed3fb5824dacf7af368698aad6c1e6dce3fa8ee006ba46bb5e` |
| AAB content | production API URL and OAuth client ID present in all three ABIs; not debuggable; no emulator addresses ("localhost" is a Dart framework string) |

## Play-signing consequence (important)
Play re-signs with the Play App Signing key, whose certificate differs from the upload key. Therefore:
- The sideloaded `0.1.0` cannot be updated in place by the Play build. Testers must uninstall it first (the session is lost; server data is not).
- Google Sign-In on the Play build needs the **Play App Signing SHA-1** (Play Console, Test and release, App integrity) added to the Android OAuth client, in addition to the upload SHA-1 above.
- FCM is unaffected.

## Can the signed release go to Play internal testing?
**Yes, the artifact is ready to upload**, with these conditions: (1) versionCode 9 has not been used on Play; (2) before judging Google Sign-In, register the Play App Signing SHA-1; (3) the new client calls the contact-reveal endpoints, so internal testers need the new backend (migration `0027`) running, or reveal will fail. Do not release beyond internal testing before the backend is deployed.

## Remaining release blockers
1. Owner confirmation of the Android OAuth client and both SHA-1 values (needs Viewer on Cloud project `441892...`, or a Credentials screenshot).
2. Play Console: versionCode history and the Play App Signing SHA-1.
3. One real-device pass on the Play-installed build: Google sign-in, one push, reveal.
4. One verification email to a controlled mailbox (also confirms the Resend domain is Verified).
5. Production backend deploy with migration `0027` (not done, not authorized).
6. Production read-only SSH preflight (blocked earlier; not re-run).
7. Legal/consent wording review by the owner (open from the blocker status).

## Minimum additional permissions for the remaining tests
| Test | Minimum needed |
|---|---|
| OAuth client check | Viewer role on the Cloud project, or a screenshot of the Android client |
| Play data | Play Console read access or screenshots (versionCode history, App integrity SHA-1) |
| Google sign-in, push | Upload to internal testing, a tester account, then install from Play (no sideload over production) |
| Push | A test account's device token and approval for exactly one push to it |
| Email | Approval for one registration/verification email to a mailbox you own, or a Resend full-access (read) key |
