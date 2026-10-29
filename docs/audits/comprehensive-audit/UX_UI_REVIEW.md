# UX/UI Review (updated after phase 2)

Basis: 60 page loads across desktop (1366x768), tablet (820x1180) and mobile (390x844), dark and light themes, English/Uzbek/Russian, plus scripted journeys in headless Chrome. Screenshots are in `screenshots/`. Items marked *code/doc* were not seen on screen.

## What works well (observed)
- Responsive layout switches cleanly: sidebar on desktop, bottom bar on tablet/mobile; **no horizontal overflow on any page**; no console errors.
- Light and dark themes both render with legible contrast on the pages I looked at (`home_desktop.png`, `home_mobile.png`).
- Uzbek and Russian are complete on the 9 routes compared; no leftover English strings (`lang_uz_profile_settings.png`, `lang_ru_add.png`).
- Controls expose accessibility labels ("Like 0", "Next photo", "Remove photo", "Post comment"), tabs and menu items have roles; keyboard focus and Enter work on dialogs.
- The create flow is one screen with clear sections (photos, name, location, note), a clear location-privacy dialog before reading location, and visible per-photo remove buttons.
- Direct URLs and reload keep the user in place.

## Confirmed issues
| ID | Sev | Issue | Evidence |
|----|-----|-------|----------|
| U-1 | P1* | Blocking appears to work (button, confirmation, "blocked" state) but the person's content still appears everywhere; users will believe they are protected | F-01; `evidence/` repro |
| U-2 | P2 | During an outage a signed-in user sees the signed-out home (Login / Create account) and `/profile` sends them to "auth required", although the session is intact | `down_feed.png`, F-16 |
| U-3 | P3 | A deleted or missing post shows "Could not load this section" with a Retry that can never succeed | `m_mobile_dark_missing_post.png`, F-17 |
| U-4 | P3 | Unknown URL: only "This page is not available." in the middle of a blank screen, no button, no navigation bar | `m_mobile_dark_garbage.png` |
| U-5 | P3 | Map silently shows at most 100 pins per viewport; nothing says more exist | `map_3000.png`, F-22 |
| U-6 | P3 | First-run onboarding stacks two modal dialogs (language, then a welcome/donation card) on top of whatever page was opened, including deep links to a post; the language is asked again even though the account already has a saved preference | `add_choose.png` |
| U-7 | P3 | Login error text pushes the form down by 36 px, so the button moves under the cursor | `login_bad.png` |
| U-8 | P3 | The Google button text is rendered by Google in its own language (Uzbek on an English page) | `login_bad.png`, home screenshots |
| U-9 | P3 | Phone numbers are exposed in plain text and in the accessibility label of "Contact Owner" to anonymous visitors | F-13 |

\* Rated P1 together with F-01, not separately.

## Unverified from this phase
- A free-text note typed in the create form did not appear on the stored post; I could not separate a test-driver problem from an app problem, so it is not reported as a defect. Worth a manual 30-second check.
- Accessibility beyond labels (contrast ratios, text scaling, screen-reader order), form validation messages in other forms, onboarding clarity for first-time users, empty states for new accounts, notification preferences and the moderation screens.
- Android-specific UX (see ANDROID_TEST_RESULTS.md).

## Recommendations (small, targeted)
1. Make blocking real (F-01) before adding more social features.
2. Keep the signed-in shell during network failures; show a banner such as "Can't reach the server" (F-16).
3. Distinguish 404 ("This post was removed", with a button to the feed) from transient failures (Retry) (F-17).
4. Give the unknown-route page the normal app shell with a "Go to feed" button.
5. Say "Zoom in to see more" when a viewport hits the 100-pin cap.
6. Show onboarding once per account on a neutral screen, and skip the language question when the account already has a language.
7. Reserve space for the login error text so the layout does not jump.
