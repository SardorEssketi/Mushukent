UI_UX.md

Mushukistan MVP UI/UX Specification

Version: 1.0 (MVP)
Primary platform: Android (Flutter)

1. Purpose
----------
This document describes every MVP screen in detail, including navigation flows, layout structure, interactions, and edge cases. It is the canonical UI/UX reference before implementation.

2. Design Principles
--------------------
- Feed-first navigation and discovery, with map as a location view.
- Minimal interactions to complete key tasks.
- Clear distinction: cats are core entities, posts are observations.
- Fast perceived performance on mid-range Android devices.
- Accessibility and readability over visual complexity.

3. Global App Structure
-----------------------
3.1 Primary Navigation
Bottom navigation with 5 tabs:
1. Feed
2. Map
3. Add
4. Leaderboard
5. Profile

3.2 Shared UI Elements
- App bar on screens that need title/actions.
- Bottom navigation always visible on main tabs.
- Floating action button optional on map for quick "Add Observation".
- Consistent cards for cat/post summary.

3.3 Global States
- Loading (skeletons/spinners)
- Empty
- Error with retry
- Offline/no network notification

4. Navigation Flows
-------------------
4.1 First Launch Flow
- App opens -> Auth Gate
- If no valid token -> Auth screen
- If valid token -> Feed tab

4.2 Authenticated Main Flow
- Default landing tab: Feed
- User can switch tabs anytime.
- Deep links to posts open details screens and preserve back stack.

4.3 Add Observation Flow
- User taps Add tab or map quick action
- Cat Observation -> choose camera or gallery photos -> choose location behavior:
  - Use current location -> match/select cat -> submit -> success.
  - Mark on map -> user sees current location, can recenter on user, taps map to place observation marker -> match/select cat -> submit -> success.
  - Continue without location -> feed-only observation details -> submit -> success.
- Lost Pet -> require profile phone number -> choose one to five photos -> enter pet name -> point last-seen location on map or use current location -> submit -> feed.

4.4 Moderation Flow (for moderators)
- Profile -> Moderator tools -> Reports list -> report detail -> action (resolve/dismiss/remove content)

5. Screen Specifications
------------------------
5.1 Auth Gate Screen
- Purpose: decide whether to route to authenticated app or auth screens.
- Layout:
  - centered app logo/name,
  - loading indicator while token check runs.
- Interaction:
  - none except automatic route decision.
- Edge cases:
  - expired token -> clear token and route to Login.
  - corrupted local auth state -> fallback to Login.

5.2 Login Screen
- Purpose: authenticate existing users.
- Layout:
  - title: "Welcome back"
  - email input
  - password input (toggle visibility)
  - login button
  - "Continue with Google" button
  - link to Register screen
- Interactions:
  - submit via button or keyboard action.
  - disable button while request pending.
- Validation:
  - email format check,
  - password required.
- Error states:
  - invalid credentials,
  - email not verified,
  - network timeout,
  - server unavailable.
- Edge cases:
  - repeated failed attempts -> show cooldown messaging from rate-limit response.
  - unverified password account -> route to Verify Email screen with resend action.

5.3 Register Screen
- Purpose: create account.
- Layout:
  - name
  - email
  - password
  - Terms of Service acceptance
  - Privacy Policy acceptance
  - register button
  - link to Login
- Interactions:
  - tapping Register after valid fields submits registration using the current app language.
  - Google account creation starts from the Login screen's Google flow, which collects any required legal consent separately from the email registration form.
- Validation:
  - email valid,
  - password min 8,
  - name required, max 100.
- Success:
  - show Verify Email screen; password users cannot log in until confirmation is complete.
- Edge cases:
  - duplicate email,
  - weak password,
  - network failure.

5.4 Verify Email Screen
- Purpose: complete email confirmation before allowing password login.
- Layout:
  - confirmation title
  - explanatory copy using the pending email address
  - resend verification action
  - in development only, a quick verify action when a development token is available
  - link back to Login
- Interactions:
  - resend verification email
  - resend action starts a 60-second cooldown before it can be pressed again.
  - submit local development verification token
- Edge cases:
  - expired token -> show failure and allow resend
  - already verified account -> route to Login with success message

5.4.1 Authenticated Welcome Onboarding
- Purpose: greet newly authenticated users after email verification and sign-in.
- Trigger:
  - first authenticated app session for a user after they enter the main platform.
- Layout:
  - language selection dialog with English, Uzbek, and Russian options
  - welcome/support dialog from the developer
- Interactions:
  - selecting a language updates the app locale and persists the preferred language to the authenticated user profile.
  - dismissing the welcome/support dialog completes onboarding for that user on the device.

5.5 Map Screen (Primary MVP Screen)
- Purpose: discover recently observed cats geographically.
- Layout:
  - full-screen map canvas,
  - compact filter button opening marker filters for Cats, Vets, Shops and Shelters,
  - optional recenter location button,
  - marker clusters or markers,
  - bottom sheet preview on marker tap.
- Visibility:
  - cats appear on the map only when their latest public observation is within the last 10 days.
- older cats remain available through Feed posts.
- Filters:
  - Nearby Cats
  - Recently Seen
  - Needs Help
  - Recently Added
  - Pet Shops
  - Veterinary Clinics
  - Animal Shelters
- Interactions:
  - pan/zoom map,
  - tap marker -> no detail page in MVP,
  - tap vet/shop/shelter marker -> place preview with phone, website and opening hours when available,
  - tap filter button -> choose visible marker types -> apply filters,
  - filter selection updates marker set.
- Edge cases:
  - location permission denied -> show explanatory prompt and fallback to city-level default view.
  - no cats in visible area -> empty map helper message.
  - map tiles load failure -> retry banner.

5.6 Cat Profiles
- Cat profile pages are not part of the MVP.
- Cat records are still used internally to group observations, display cat names in posts, and support map markers.

5.7 Add Observation Entry Screen
- Purpose: start observation creation process.
- Layout:
- Cat observation: user chooses camera or gallery photos, then explicitly chooses whether to attach current location, manually mark a location on the map, or continue without location.
- Lost Pet: creates a lost pet post shown in the feed.
- Interactions:
- permission prompts for camera/gallery.
- map location picker shows user's current location, a recenter-on-user button, and a tappable observation marker.
- tapping Lost Pet checks whether the current user has a phone number; if not, show a prompt to edit profile first.
- Edge cases:
- permission denied -> show system settings guidance.
- user cancels image picker -> return to previous screen.

5.7.1 Lost Pet Create Screen
- Purpose: publish a lost pet post from the Add flow.
- Layout:
  - one to five selected cat photos
  - pet name field
  - last-seen location selected by pointing on a map
  - additional information text field
  - owner phone preview from profile
  - submit button
- Interactions:
  - add/remove photos
  - tap the map or use the current-location shortcut to set last-seen location
  - submit -> lost pet appears in Feed with Lost Pet tag
- Validation:
  - profile phone number required before opening create flow
  - phone number must use Uzbekistan format shown with placeholder digits: +998 xx xxx xx xx
  - pet name required, max 100 chars
  - at least one photo required
  - maximum five photos
  - last-seen map point required
  - additional information max 2000 chars

5.8 Add Observation Details Screen
- Purpose: complete metadata before submission.
- Layout:
- one to five image previews
- description input
- status selector for located observations only (Healthy/Needs Help/Unknown)
- located observations include an explicitly confirmed current location or manually selected map point.
- cat matching section:
    - nearby suggestions list,
    - action buttons: "This is existing cat" / "This is new cat"
  - submit button
- Interaction:
  - selecting existing cat links observation to chosen cat.
  - selecting new cat reveals optional cat name and approximate age fields.
- Validation:
  - image required,
  - location required,
  - status enum valid.
- Edge cases:
- GPS unavailable for current-location flow -> show error and retry or allow manual map placement / skip location.
- no nearby suggestions -> emphasize "new cat" path.
- observations without explicit location do not create map markers.
- observations without explicit location do not show a status selector.
- upload failure -> keep entered data in memory and allow retry.

5.9 Observation Publish Success Screen/State
- Purpose: confirm successful post creation.
- Layout:
  - success message,
  - preview thumbnail,
  - buttons: View feed, Add another.
- Edge cases:
  - follow-up fetch failure when opening details -> show retry.

5.10 Feed Screen
- Purpose: browse observations in list format.
- Layout:
  - top filter chips: Recent, Popular, Needs help, Lost pets
  - when Popular is selected, show period selector: Today, Month, All time
  - vertically scrolling post cards
  - on wide web screens, keep the feed column constrained and use shorter media previews so cards remain compact.
- Post card contents:
  - thumbnail image,
  - Lost Pet tag for lost pet posts,
  - author,
  - cat summary,
  - timestamp,
  - distance (if nearby),
  - like count next to the like icon, comment count next to the comment icon and publish date as `Published: <date>`,
  - all visible tags appear next to the cat/pet name; `Unknown` is not displayed as a tag,
  - quick like action.
- Interactions:
  - tap card -> Post Detail
  - tap Lost Pet card -> Lost Pet Detail
  - tap Contact Owner on Lost Pet card -> initiate phone call
  - tap author name/avatar -> User Profile
  - pull to refresh,
  - infinite scroll pagination.
  - filter selection is visible in the feed header, not hidden in an overflow menu.
  - Today means the last 24 hours.
- Edge cases:
  - empty feed -> helper CTA to add first observation.
  - duplicate pagination response -> deduplicate by post id.

5.11 Post Detail Screen
- Purpose: full observation detail and discussion.
- Layout:
  - large image/gallery
  - author info
  - cat name
  - description
  - location mini-map
  - likes/comments section
  - comment input field (if logged in)
- Interactions:
  - tap author -> User Profile
  - like/unlike,
  - report content,
  - owner options menu: delete post.
- Edge cases:
  - post removed by moderator -> show unavailable message and navigate back.

5.12 Comments Section
- Purpose: display and add comments inside the post detail screen.
- Layout:
  - comment list
  - input box + send button
- Interactions:
  - tap comment author -> User Profile
  - submit comment,
  - delete own comment via long-press/menu.
- Validation:
  - max 1000 chars.
- Edge cases:
  - rapid submit taps -> disable send until request finishes.
  - deleted post while viewing comments -> show unavailable message.

5.12.1 Lost Pet Comments Section
- Purpose: display and add comments inside the lost-pet detail screen.
- Layout and behavior:
  - same comment list and input behavior as observation posts.
  - comments are visible only inside the Lost Pet detail screen.

5.14 Leaderboard Screen
- Purpose: community ranking and engagement motivation.
- Layout:
  - tabs/segmented control: Most Active, Most Popular, Top Helpers
  - period switch: week/month/all
  - ranked user list items with avatar, name, observation count, and score
- Interactions:
  - tap user -> User Profile
- Edge cases:
  - no data yet -> friendly empty state.
  - ties -> stable ordering by earliest registration or user id.

5.15 User Profile Screen (Self)
- Purpose: manage personal profile and view contribution stats.
- Layout:
  - avatar, display name, bio
  - owner-only phone number
  - stats: observations, likes received, comments count
  - list: My Observations
  - actions: Adoption help, Edit Profile, Settings, Logout
  - if moderator: Moderator Tools entry
- Interactions:
  - tap Adoption help -> opens informational guidance about adopting a cat in Uzbekistan, including veterinary checks, identification/passport, ownership transfer, apartment/common-area rules, and official source links
  - edit profile fields,
  - tap Observations to view the user's observation posts,
  - tap Comments to view the user's comments,
  - open own posts list,
  - logout confirmation.
- Edge cases:
  - avatar load failure -> fallback placeholder.

5.16 User Public Profile Screen
- Purpose: view another contributor.
- Layout:
  - avatar, name, public stats
  - posts list
- Interactions:
  - open their posts
  - open their comments when public activity is enabled
- Privacy:
  - no private email shown.

5.17 Edit Profile Screen
- Purpose: update display name, phone number, bio, avatar.
- Layout:
  - avatar preview and "Change profile picture" button
  - camera option for new profile picture
  - editable fields
  - save button
- Validation:
  - name max 100,
  - phone number optional, owner-only for MVP and must use Uzbekistan format shown with placeholder digits: +998 xx xxx xx xx,
  - bio max 1000,
  - avatar type/size constraints from media policy.
- Edge cases:
  - save conflict/network failure -> keep unsaved changes and retry option.

5.17.1 Settings Screen
- Purpose: manage application preferences.
- Layout:
  - theme selector
  - language selector: English, Uzbek, Russian
  - privacy toggle: allow other people to view my observations and comments
  - About account entry
  - Save changes button
- Interaction:
  - theme and language changes remain pending until the user taps Save changes.
  - saving updates the app locale immediately and persists the language preference and activity privacy preference to the authenticated user's profile.
  - successful save returns the user to Profile.

5.17.2 About Account Screen
- Purpose: show account metadata that is not part of the main profile summary.
- Layout:
  - registration date
  - account email
  - account phone number
  - linked Privacy Policy and Terms of Service summaries
  - clickable account deletion explanation
- Interaction:
  - tapping Privacy Policy opens the in-app Privacy Policy screen.
  - tapping Terms of Service opens the in-app Terms of Service screen.
  - tapping Account deletion opens a confirmation dialog.
  - the confirmation dialog disables the final delete action for 5 seconds.
  - confirming deletion deactivates the account through the backend and signs the user out.
- Navigation:
  - Profile -> Settings -> About account.

5.18 Report Content Screen
- Purpose: submit moderation report.
- Layout:
  - target summary card
  - reason input
  - optional metadata field (text)
  - submit button
- Interactions:
  - submit report -> success toast
- Edge cases:
  - already reported recently -> show duplicate warning.

5.19 Moderator Reports List Screen (Moderator Only)
- Purpose: triage open/processed reports.
- Layout:
  - filters: open/resolved/dismissed
  - report cards with target type, reason, timestamp, reporter
- Interactions:
  - open report detail,
  - pagination/infinite scroll.
- Edge cases:
  - target already deleted -> mark with badge.

5.20 Moderator Report Detail Screen (Moderator Only)
- Purpose: inspect and resolve a report.
- Layout:
  - full report metadata
  - target preview
  - actions: Resolve, Dismiss, Remove Content, Suspend User (if needed)
  - optional moderator note
- Interactions:
  - perform action with confirmation dialog.
- Edge cases:
  - concurrent handling by another moderator -> refresh and show conflict message.

6. Interaction and State Standards
----------------------------------
- All network actions show clear pending state.
- Submit buttons disabled while request in progress.
- Use optimistic updates only for likes; rollback on failure.
- For destructive actions (delete/suspend), require confirmation dialog.
- Toast/snackbar messaging for success/failures should be concise and user-readable.

7. Edge Cases and Error UX Matrix
---------------------------------
7.1 Authentication
- Expired token -> force logout and redirect to Login with message.
- Invalid token -> clear token and re-authenticate.
- Unverified password account -> route to Verify Email screen and provide resend action.

7.2 Location
- Permission denied -> explain feature impact and show fallback mode.
- GPS timeout -> allow manual map placement.

7.3 Uploads
- Image too large -> immediate validation error.
- Unsupported format -> clear error with accepted formats.
- Network interruption -> retry with preserved form data.

7.4 Moderation
- Report target missing -> show "content no longer available".
- Moderator action failure -> keep pending state and allow retry.

7.5 Pagination
- End of list -> show "No more items" indicator.
- Duplicate item from race condition -> de-duplicate by id client-side.

8. Accessibility and Localization
---------------------------------
- Minimum touch target size: 48dp.
- Color contrast follows Material accessibility guidance.
- Provide text alternatives for icons.
- Support dynamic text scaling without layout breakage.
- MVP language: English (additional locales post-MVP).

9. Performance UX Targets
-------------------------
- Initial app shell visible quickly with skeleton state.
- Use thumbnails in list/map cards to reduce bandwidth.
- Avoid heavy animations; prioritize smooth scrolling and map interactions.

10. MVP Screen Inventory Checklist
----------------------------------
Required screens:
- Auth Gate
- Login
- Register
- Verify Email
- Map
- Add Observation Entry
- Add Observation Details
- Publish Success State
- Feed
- Post Detail
- Leaderboard
- Profile (self)
- Public User Profile
- Edit Profile
- Report Content
- Moderator Reports List
- Moderator Report Detail

11. Out of Scope for MVP UI
---------------------------
- Push notification center
- In-app chat/direct messages
- Offline mode synchronization UI
- Web layouts
- AI matching confidence visualization

Change Log
----------
- 2026-07-23: Initial MVP UI/UX architecture document.

