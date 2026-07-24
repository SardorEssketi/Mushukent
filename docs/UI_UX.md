UI_UX.md

Mushukent MVP UI/UX Specification

Version: 1.0 (MVP)
Primary platform: Android (Flutter)

1. Purpose
----------
This document describes every MVP screen in detail, including navigation flows, layout structure, interactions, and edge cases. It is the canonical UI/UX reference before implementation.

2. Design Principles
--------------------
- Map-first navigation and discovery.
- Minimal interactions to complete key tasks.
- Clear distinction: cats are core entities, posts are observations.
- Fast perceived performance on mid-range Android devices.
- Accessibility and readability over visual complexity.

3. Global App Structure
-----------------------
3.1 Primary Navigation
Bottom navigation with 5 tabs:
1. Map
2. Feed
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
- If valid token -> Map tab

4.2 Authenticated Main Flow
- Default landing tab: Map
- User can switch tabs anytime.
- Deep links to cat or post open details screen and preserve back stack.

4.3 Add Observation Flow
- User taps Add tab or map quick action
- Capture/select image -> location confirmation -> match/select cat -> submit -> success -> open created post or cat page

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
  - network timeout,
  - server unavailable.
- Edge cases:
  - repeated failed attempts -> show cooldown messaging from rate-limit response.

5.3 Register Screen
- Purpose: create account.
- Layout:
  - name (optional)
  - email
  - password
  - register button
  - link to Login
- Validation:
  - email valid,
  - password min 8,
  - name max 100.
- Success:
  - auto-login and route to Map or show success then Login (choose one consistently; MVP recommendation: auto-login).
- Edge cases:
  - duplicate email,
  - weak password,
  - network failure.

5.4 Map Screen (Primary MVP Screen)
- Purpose: discover cats geographically.
- Layout:
  - full-screen map canvas,
  - top search/filter bar,
  - optional recenter location button,
  - marker clusters or markers,
  - bottom sheet preview on marker tap.
- Filters:
  - Nearby Cats
  - Recently Seen
  - Needs Help
  - Recently Added
- Interactions:
  - pan/zoom map,
  - tap marker -> cat preview card,
  - swipe preview -> open full Cat Page,
  - filter selection updates marker set.
- Edge cases:
  - location permission denied -> show explanatory prompt and fallback to city-level default view.
  - no cats in visible area -> empty map helper message.
  - map tiles load failure -> retry banner.

5.5 Cat Preview Bottom Sheet
- Purpose: quick context before opening full cat page.
- Layout:
  - cover thumbnail
  - cat name/status
  - last seen timestamp
  - quick actions: Open, Add Observation
- Interaction:
  - tap Open -> Cat Detail screen
  - tap Add Observation -> prefilled Add flow with cat selected
- Edge cases:
  - cat deleted between fetch and tap -> show not found toast and refresh map.

5.6 Add Observation Entry Screen
- Purpose: start observation creation process.
- Layout:
  - options: Take Photo / Choose from Gallery
  - brief guidance text
- Interactions:
  - permission prompts for camera/gallery.
- Edge cases:
  - permission denied -> show system settings guidance.
  - user cancels image picker -> return to previous screen.

5.7 Add Observation Details Screen
- Purpose: complete metadata before submission.
- Layout:
  - image preview
  - description input
  - status selector (Healthy/Injured/Needs Help/Adopted/Unknown/Feed)
  - location preview map + "Use Current Location" + manual pin adjust
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
  - GPS unavailable -> allow manual pin drop.
  - no nearby suggestions -> emphasize "new cat" path.
  - upload failure -> keep draft data in memory and allow retry.

5.8 Observation Publish Success Screen/State
- Purpose: confirm successful post creation.
- Layout:
  - success message,
  - preview thumbnail,
  - buttons: View Post, View Cat, Back to Map.
- Edge cases:
  - follow-up fetch failure when opening details -> show retry.

5.9 Feed Screen
- Purpose: browse observations in list format.
- Layout:
  - top filter chips: Nearby, Recent, Popular
  - vertically scrolling post cards
- Post card contents:
  - thumbnail image,
  - author,
  - cat summary,
  - timestamp,
  - distance (if nearby),
  - like/comment counts,
  - quick like action.
- Interactions:
  - tap card -> Post Detail
  - pull to refresh,
  - infinite scroll pagination.
- Edge cases:
  - empty feed -> helper CTA to add first observation.
  - duplicate pagination response -> deduplicate by post id.

5.10 Post Detail Screen
- Purpose: full observation detail and discussion.
- Layout:
  - large image
  - author info
  - cat reference (tap to cat page)
  - description
  - location mini-map
  - likes/comments section
  - comment input field (if logged in)
- Interactions:
  - like/unlike,
  - open comments list,
  - report content,
  - owner options menu: delete post.
- Edge cases:
  - post removed by moderator -> show unavailable message and navigate back.

5.11 Comments Sheet/Screen
- Purpose: display and add comments for a post.
- Layout:
  - comment list
  - input box + send button
- Interactions:
  - submit comment,
  - delete own comment via long-press/menu.
- Validation:
  - max 1000 chars.
- Edge cases:
  - rapid submit taps -> disable send until request finishes.
  - deleted post while viewing comments -> close with message.

5.12 Cat Detail Screen (Cat Page)
- Purpose: represent cat as primary entity with history.
- Layout:
  - cover photo
  - cat name/status badges
  - stats row: first seen, last seen, observations, contributors, likes
  - observation timeline list (newest first default)
  - actions: Add Observation, Report
- Interactions:
  - tap history item -> Post Detail
  - filter/sort history (latest/oldest)
- Edge cases:
  - no history should not happen for valid cat; if empty due to moderation, show special notice.

5.13 Leaderboard Screen
- Purpose: community ranking and engagement motivation.
- Layout:
  - tabs/segmented control: Most Active, Most Popular, Top Helpers
  - period switch: week/month/all
  - ranked list items with avatar, name, score
- Interactions:
  - tap user -> User Profile
- Edge cases:
  - no data yet -> friendly empty state.
  - ties -> stable ordering by earliest registration or user id.

5.14 User Profile Screen (Self)
- Purpose: manage personal profile and view contribution stats.
- Layout:
  - avatar, display name, bio
  - stats: observations, likes received, comments count
  - list: My Observations
  - actions: Edit Profile, Logout
  - if moderator: Moderator Tools entry
- Interactions:
  - edit profile fields,
  - open own posts list,
  - logout confirmation.
- Edge cases:
  - avatar load failure -> fallback placeholder.

5.15 User Public Profile Screen
- Purpose: view another contributor.
- Layout:
  - avatar, name, public stats
  - posts list
- Interactions:
  - open their posts
- Privacy:
  - no private email shown.

5.16 Edit Profile Screen
- Purpose: update display name, bio, avatar.
- Layout:
  - editable fields
  - avatar picker/upload
  - save button
- Validation:
  - name max 100,
  - bio max 1000,
  - avatar type/size constraints from media policy.
- Edge cases:
  - save conflict/network failure -> keep unsaved changes and retry option.

5.17 Report Content Screen
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

5.18 Moderator Reports List Screen (Moderator Only)
- Purpose: triage open/processed reports.
- Layout:
  - filters: open/resolved/dismissed
  - report cards with target type, reason, timestamp, reporter
- Interactions:
  - open report detail,
  - pagination/infinite scroll.
- Edge cases:
  - target already deleted -> mark with badge.

5.19 Moderator Report Detail Screen (Moderator Only)
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
- Map
- Cat Preview Sheet
- Add Observation Entry
- Add Observation Details
- Publish Success State
- Feed
- Post Detail
- Comments
- Cat Detail
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

