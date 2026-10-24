# Functional QA Results

Method: a custom Flutter Web release build (`MUSHUKISTAN_API_BASE_URL=http://127.0.0.1:18400/api/v1`) served from a local static server, an isolated backend on a migrated disposable database, and headless Chrome 155 driven over the DevTools protocol. Flutter's accessibility tree was enabled so controls could be located and clicked. Seed data (2 users, 6 observations, 1 needs-help post, 1 lost pet, 1 adoption post) was created through the real API with real JPEG uploads. The shipped `frontend/build/web` was **not** used because it points at the production API.

Legend: **Executed** = I ran it. **Not executed** = no claim made.

## Journey checklist (the 20 requested)
| # | Journey | Status | Result |
|---|---|---|---|
| 1 | Registration and login | Executed (API for registration, UI for login) | Registration returns the verification step; login with wrong password shows "Email or password is incorrect." (layout shifts 36 px when the error appears); correct login lands on `/feed` |
| 2 | Google Sign-In | **Not executed** | Needs real Google credentials; the button renders (in Uzbek on an English UI) |
| 3 | Logout and session recovery | Partly executed | Reload keeps the session; stale access token + valid refresh recovers silently; both invalid -> `/auth-required?redirect=/profile`. Explicit logout button click **not executed** |
| 4 | Account editing | Partly | Language/privacy changes via API and visual check of Settings in 3 languages; edit-profile form **not executed** |
| 5 | Create observation | Executed (UI) | `/add/details`: 2 photos via the real file chooser, current-location consent dialog, publish -> `POST /posts`, redirect to `/feed`; post stored with 2 photos and the coordinates. The free-text note I typed was **not** saved (description came back empty); I could not tell whether my automation or the app lost it, so it is unverified |
| 6 | Upload multiple images | Executed | 2 photos via UI; API matrix: 5 accepted, 6th/7th rejected with a clear 400 |
| 7 | Create lost pet | Executed (API) | `POST /lost-pets` 201; UI form **not executed** |
| 8 | Resolve lost pet | API only | Owner/other-user checks in AUTHORIZATION_MATRIX; the "Mark as found" button is visible to the owner (screenshot) but was not clicked |
| 9 | Create help request | Executed (API) | `POST /posts kind=needs_help` 201 |
| 10 | Create rehoming post | Executed (API) | `POST /adoption-posts` 201 |
| 11 | View and filter feed | Executed | Feed renders on desktop/tablet/mobile; filter chips present; filter switching **not clicked** |
| 12 | Map navigation and filtering | Executed | 3,000 seeded pins; clustering works; pan/zoom produce one debounced `/cats` + `/lost-pets/map` request pair per settle (12 requests for 3 pans + 4 zooms); max 100 pins per viewport with no UI hint (F-22). Layer filter menu **not clicked** |
| 13 | Place details | **Not executed** | No places seeded |
| 14 | Another user's profile | Executed | `/users/{id}` renders; profile actions menu shows Report / Block user |
| 15 | Likes and comments | Executed | Like from the feed -> `POST /posts/{id}/likes`; comment on a lost pet through the UI -> exactly one `POST` even after a double click |
| 16 | Reporting and blocking | Blocking executed (UI + API); reporting **not executed** | Block request succeeds but has no effect (F-01) |
| 17 | Notifications and preferences | Partly | `/notifications` and settings pages render in all viewports; the unread count call fires; preference toggles **not executed** |
| 18 | API failures | Executed | Backend stopped: feed shows "Could not load this section"/Retry **and the signed-out header**; `/profile` redirects to auth-required; lost-pet page shows Retry (F-16) |
| 19 | Mobile and desktop navigation | Executed | Desktop sidebar, tablet and mobile bottom bar; bottom bar disappears on the unknown-route page (F-17) |
| 20 | Refresh and direct URLs | Executed | 13 routes x 3 viewports loaded directly and after login without horizontal overflow or console errors; deep links to posts, lost pets, adoption posts, users, settings, notifications all resolved |

## Viewport and theme matrix (executed)
Routes: feed, map, leaderboards, post, lost pet, adoption post, profile, add, notifications, settings, user profile, missing post, unknown route. Viewports: 1366x768, 820x1180, 390x844. Dark theme everywhere; light theme on all routes at mobile and on feed/post/lost/profile at the other sizes. Total 60 page loads.
- Horizontal overflow (`scrollWidth - innerWidth`): **0 on every page**.
- Console errors: none, except the expected 404 for the missing post.
- Screenshots of defects: `screenshots/`.

## Localization (executed)
Same 9 routes in English, Uzbek and Russian (account preference changed via API). Labels that were identical to English: none apart from user-entered content ("Orange tabby, red collar"). Screenshots: `lang_uz_profile_settings.png`, `lang_ru_add.png`. The Google sign-in button's own language follows Google, not the app (seen in Uzbek on the English login page).

## Edge cases
| Case | Status | Result |
|---|---|---|
| Invalid input (login) | Executed | Inline error |
| Expired session | Executed | Silent refresh works; refresh token does not rotate (F-19) |
| Backend unavailable | Executed | F-16 |
| Missing content | Executed | F-17 |
| Duplicate submission | Executed | UI sends one comment request on double click; API accepts duplicates (F-23) |
| Rapid interactions | Partly | 20 parallel likes handled correctly |
| Slow connections | **Not executed** | |
| Missing images | **Not executed** (seeded image URLs resolved) | |
| Missing permissions (location) | Partly | Geolocation was granted via the browser; denial **not executed** |
| Large datasets | Executed | 3,000 map pins; 200,000 posts on the backend (API timings only, UI not pointed at that DB) |

## Observed UX issues (see UX_UI_REVIEW.md)
First-run onboarding stacks two modal dialogs on top of whatever URL was opened (language, then a "Welcome" dialog with the author's card number). Both dismiss normally with the mouse; an earlier apparent failure to dismiss was my test driver clicking a container instead of the button.
