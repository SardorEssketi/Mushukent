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
- Four contribution types: Cat post, Cat needs help, Lost Pet, and Find a new home. Cat records remain internal entities.
- Fast perceived performance on mid-range Android devices.
- Accessibility and readability over visual complexity.

3. Global App Structure
-----------------------
3.1 Primary Navigation
Bottom navigation with 5 tabs on main tab roots:
1. Feed
2. Map
3. Add
4. Leaderboard
5. Profile

3.2 Shared UI Elements
- App bar on screens that need title/actions.
- Bottom navigation is visible on main tab roots and hidden after entering a creation workflow. `/add` remains a normal tab with navigation visible.
- Selecting a different tab opens that tab's root route. Returning to a tab does not restore a nested edit or settings screen.
- Re-tapping the active Feed root scrolls its existing feed to the top; returning to Feed from another tab preserves its scroll position.
- Consistent cards for cat/post summary.

3.3 Global States
- Loading (skeletons/spinners)
- Empty
- Error with retry
- Offline/no network notification

4. Navigation Flows
-------------------
4.1 First Launch Flow
- App opens -> Feed tab while session restoration runs independently.
- If no valid token/session -> remain in the public product as a guest.
- If valid token -> restore authenticated account state without an auth/feed redirect chain.
- Guests are asked to sign in only when they choose an identity-dependent action.

4.2 Authenticated Main Flow
- Default landing tab: Feed
- User can switch between main tabs anytime; creation workflows hide bottom navigation until the user finishes or backs out.
- Deep links to posts open details screens and preserve back stack.

4.3 Create Flow
- User taps Add.
- Cat post opens one casual form for general cat content, including the user's own cat, a street cat, a photo, a moment, or an update. The form accepts 1–5 photos, an optional cat name, optional location, and optional note. Gallery and camera use the existing image preparation pipeline. A chosen location may show the post on Map under existing visibility rules.
- Cat needs help opens the same form with a stronger help context. It requires 1–5 photos, a location, and a description of the help needed; cat name remains optional. Location can come from the current location service or a bounded map picker. Published help posts appear in Feed and Map under existing visibility rules.
- Both ordinary post types publish through `/posts` with their existing internal `observation` or `needs_help` kind. Successful ordinary posts, Lost Pet posts, and rehoming posts return to Feed with a concise localized snackbar. The ordinary-post draft retains photos, kind, name, location, and text while using the map picker.
- Lost Pet and Find a new home retain their existing creation and lifecycle flows.

4.4 Moderation Flow (for moderators)
- Profile -> Moderator tools -> Reports list -> report detail -> action (resolve/dismiss/remove content)

5. Screen Specifications
------------------------
5.1 Startup and Authentication Requirement Screens
- Purpose: keep public browsing available while session restoration runs and explain authentication only when an action requires identity.
- Layout:
  - the web shell shows a minimal loading surface until Flutter renders its first frame;
  - an action-level authentication screen offers Sign in, Create account, and Continue browsing.
- Interaction:
  - public routes remain usable without waiting for session restoration;
  - after successful authentication, return to the intended protected route when safe.
- Edge cases:
  - expired access token with refresh/session token -> silently refresh before routing.
  - invalid refresh/session token -> clear auth state and continue as guest.
  - transient refresh failure -> public screens remain available.
  - corrupted or unavailable browser storage -> recover as guest; do not leave a blank page.

5.2 Login Screen
- Purpose: authenticate existing users.
- Layout:
  - title: "Welcome back"
  - linked "By continuing with Google, you agree to the Terms of Service and Privacy Policy" notice
  - "Continue with Google" button
  - simple "or continue with email" divider
  - email and password inputs
  - login button
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
  - linked "By continuing with Google, you agree to the Terms of Service and Privacy Policy" notice
  - "Continue with Google" button
  - simple "or continue with email" divider
  - name
  - email
  - password
  - one checkbox accepting both linked Terms of Service and Privacy Policy
  - register button
  - link to Login
- Interactions:
  - tapping Register after valid fields submits registration using the current app language.
  - clicking Google is a deliberate acceptance action for the linked legal notice; acceptance remains versioned and recorded by the backend.
- Validation:
  - email valid,
  - password min 8,
  - name required, max 100.
- Success:
  - show Verify Email screen; password users cannot log in until confirmation is complete.
- Edge cases:
  - duplicate normalized email gets a generic next-steps message and creates no second user; do not reveal whether an address already has an account.
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

5.5 Account Security Screen
- Purpose: let a signed-in user review their email state and manage a Mushukistan password.
- Layout:
  - email address and Verified / Needs verification status
  - Change password only for accounts with a password
  - Log out
  - no Google connection state or manual Connect Google action
- Interactions:
  - changing a password requires the current password.
  - Google-only accounts have no Password section.
  - Google sign-in may ask once for the existing Mushukistan password directly
    inside the sign-in flow. Never direct users to provider management.

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
  - compact floating layer control with a count when filters differ from the default; manual refresh sits in the layer sheet,
  - legible crosshair recenter control that requests location only after a tap,
  - compact icon markers with round animal and rounded-square place shapes; alert markers use stronger fills,
  - zoom-aware category clusters with counts inside their marker body,
  - compact marker previews with clear actions and a bounded width on wide screens.
- Visibility:
  - cats appear on the map only when their latest public observation is within the last 10 days.
- older cats remain available through Feed posts.
- Filters:
  - Animals: Cats, Cat needs help, Lost Pets.
  - Places: Veterinary Clinics, Veterinary Pharmacies, Pet Shops, Shelters.
  - Multiple layers may be visible together; layer changes apply immediately.
  - The layer sheet can show or hide all layers.
- Interactions:
  - pan/zoom map,
  - tap a cat or Lost Pet marker -> select it and open a short preview with a post action,
  - recenter on the user's location with a smooth transition and north-up map orientation,
  - tap vet/shop/shelter marker -> place preview with actions, address and hours first, then optional contact and description details,
  - tap the layer control -> choose visible marker types without a confirmation step,
  - filter selection updates marker set.
- Edge cases:
  - location permission denied -> show explanatory prompt and fallback to city-level default view.
  - no cats in visible area -> empty map helper message.
  - viewport data request failure -> keep existing markers and show a compact retry banner.

5.6 Cat Profiles
- Cat profile pages are not part of the MVP.
- Cat records are still used internally to group observations, display cat names in posts, and support map markers.

5.7 Create Entry Screen
- Purpose: choose what kind of cat update or help to share.
- Layout:
- A short introduction sits above four compact, fully tappable action cards: Cat post, Cat needs help, Lost Pet, and Find a new home.
- Cards form a centered 2-by-2 grid on wide screens and one column on compact screens. Icons and restrained accents distinguish the types; Lost Pet has the strongest urgency cue.
- An existing ordinary-post draft appears in a separate continuation section with Continue and Delete draft actions, not as a fifth creation type.
- The Add tab lets the user choose a post type.
- Cat post: casual content with 1–5 photos and optional name, location, and note.
- Cat needs help: an actionable post with 1–5 photos, required location, and required help details.
- Lost Pet: creates a lost pet post shown in the feed.
- Lost Pet detail: another signed-in user can select Contact Owner to use the
  published phone number. Guests are asked to sign in before the contact event
  is recorded or the phone action proceeds.
- A due owner follow-up appears in app with exactly Yes and No. Yes removes the
  resolved Lost Pet from Feed and Map. The owner can find active and resolved
  Lost Pets in the existing Profile area.
- The owner can also mark a Lost Pet found directly, with confirmation, and
  reopen it from its detail page. Found posts leave Feed and Map. Their detail
  links remain available without public contact or exact last-seen location.
- Interactions:
- permission prompts for camera/gallery.
- the ordinary-post form offers current location and a bounded, tappable Tashkent map picker.
- tapping Lost Pet checks for a valid Uzbekistan phone number; if missing or invalid, show a Lost-Pet-specific prompt with an Edit Profile action.
- Find a new home applies the same phone check with its own requirement message before opening the existing rehoming form.
- The owner can mark a rehoming post complete directly, with confirmation, and
  reopen it from its detail page. Rehomed posts leave Feed and remain in Profile;
  their detail links remain available without public contact information.
- The bottom navigation remains visible on the Add entry screen and is hidden in the ordinary post, needs-help, Lost Pet, and rehoming creation workflows. Back navigation remains available.
- Continue draft returns to the shared form; Delete draft asks for confirmation, resets the draft, and shows feedback.
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
  - explicit consent to show the profile phone number publicly
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

5.7.2 Lost Pet Detail Screen
- Center the gallery, title, location/contact tiles, information, owner actions, and comments in a readable column bounded by AppWidths.readable; compact screens use normal page padding.
- Keep Edit secondary and Delete clearly destructive. Put Report in the app-bar overflow menu.
- After a successful delete, return to the destination and show a localized success message.

5.8 Cat Post and Cat Needs Help Form
- A single shared form shows a type badge, purpose-specific heading, photo thumbnails with removal, optional cat name, compact location selection, and text input. Both types allow gallery and camera and require 1–5 photos. Photo processing disables duplicate picker actions.
- Cat post uses “Add a note (optional)” and allows no location. Help text explains that a location can show the post on Map. No separate location decision page or prominent “Unnamed cat” label appears.
- Cat needs help uses “What help does the cat need?” and requires both a location and nonblank help details, including for API callers. Both text types have a 2000-character maximum.
- The location control uses the existing current-location service or opens a Tashkent-bounded map picker. The selected location can be changed; Cat post location can be removed.
- The backend creates a cat record automatically; users do not match existing cats. Upload failure keeps the draft for retry. Successful publication returns to Feed with a localized snackbar; the legacy success URL redirects to Feed and no UUID is shown.

5.10 Feed Screen
- Purpose: browse recent Cat posts, Cat needs help requests, Lost Pets, and rehoming posts.
- Layout:
  - one lazy scrolling column, nearly full width on mobile and centered at a readable maximum width on tablet/web; the title aligns with that column.
  - horizontal, scrollable filters: Recent, Popular, Cat needs help, Lost pets, and Adoption on mobile and desktop; Recent is visibly selected by default.
  - tapping the selected filter keeps it selected.
  - Popular alone shows compact Today, Month, All time period chips.
  - each feed card has an author/date header, bounded media frame, compact body, and icon/count actions on a subtle shared surface.
  - media uses a contained image in a neutral frame; its height is capped on tablet/web. Multiple photos have a count and quiet previous/next controls.
- Post card contents:
  - author avatar/name with initials fallback and publication date; tapping the author opens their public profile.
  - ordinary Cat posts remain neutral, showing a useful cat name and note without a kind badge; Cat needs help uses a calm semantic badge and top accent.
  - Lost Pet uses a restrained error accent and badge, pet name, additional information, comments, and View on Map.
  - Adoption/Rehoming uses a tertiary accent and badge, pet name, additional information, and comments.
  - ordinary post actions show like/count and comments/count; other kinds only show supported actions.
  - long descriptions are limited to three lines with localized Read more / Show less controls that expand inline.
- Interactions:
  - tapping a card opens the matching ordinary-post, Lost Pet, or Adoption/Rehoming detail.
  - ordinary-post likes update optimistically, reconcile with the API, and restore the prior state on failure; guests use the authentication flow.
  - pull to refresh replaces the loaded pages with a fresh first page.
  - scrolling near the bottom requests the next server cursor; items append with identity/type deduplication. Filter and Popular period changes start a new page sequence.
- Edge cases:
  - initial loading shows quiet card placeholders; initial errors show Retry and empty filters show category-specific messages.
  - a later-page error keeps loaded cards visible with a bottom Retry; no further page request occurs after a null cursor.

5.11 Post Detail Screen
- Purpose: full Cat post or Cat needs help detail and discussion.
- Layout:
  - photo gallery, then a quiet Cat post context or a stronger Cat needs help badge
  - meaningful cat name if known, otherwise the natural contribution title
  - author, publication date, and edited state
  - compact “View on map” location action only when a location exists
  - optional note for Cat post, or “What help is needed” section for Cat needs help
  - compact like and comment counts, comments, and report action
  - owner edit/delete and moderator delete/history controls remain available
- Interactions:
  - tap author -> User Profile
  - like/unlike,
  - report content,
  - owner options menu: delete post.
- A successful delete shows a localized confirmation on the destination screen; errors retain distinct error feedback.
- Edge cases:
  - post removed by moderator -> show unavailable message and navigate back.

5.12 Comments Section
- Purpose: display and add comments inside the post detail screen.
- Layout:
  - comment list rendered as nested conversation threads,
  - each comment shows author, full publication date, content, report action, and Reply action,
  - reply composer identifies the selected parent comment and can be cancelled,
  - input box + send button
- Interactions:
  - tap comment author -> User Profile
  - submit comment,
  - reply to any comment; replies may be nested without a depth limit,
  - delete own comment via long-press/menu.
- Validation:
  - max 1000 chars.
- Edge cases:
  - rapid submit taps -> disable send until request finishes.
  - deleted post while viewing comments -> show unavailable message.

5.12.1 Lost Pet Comments Section
- Purpose: display and add comments inside the lost-pet detail screen.
- Layout and behavior:
  - same comment list and input behavior as ordinary posts.
  - comments are visible only inside the Lost Pet detail screen.

5.14 Leaderboard Screen
- Purpose: community ranking and engagement motivation.
- Layout:
  - two-option segmented control: Active and Popular
  - compact period selector: Day, Week, Month, All time; Month is the default
  - modest emphasis for the top three users, followed by a clean list for later ranks
  - show avatar, name, rank, and only the metric used for that ranking: posts for Active, likes for Popular
- Interactions:
  - tap user -> User Profile
- Edge cases:
  - no data yet -> friendly empty state.
  - ties -> stable ordering by earliest registration or user id.

5.15 User Profile Screen (Self)
- Purpose: manage personal profile and view contribution stats.
- Layout:
  - shared profile summary surface with large avatar, display name, short bio, and secondary owner-only email, phone, and Telegram details.
  - compact stats: posts, likes received, comments. Posts and Comments open their existing activity screens.
  - Your activity section: My lost pets and My rehoming posts.
  - Resources and account section: adoption guidance and Settings.
  - moderator-only Moderation reports section.
  - app bar: Donate to author (icon only on compact screens), Edit Profile, and Logout in the overflow menu.
  - donation dialog identifies Sardor Muxtorov as the recipient and shows the existing support card number as selectable text with a copy action.
  - one column on phones; on wide screens, summary and actions sit side by side in a centered layout bounded by AppWidths.wide.
- Interactions:
  - tap Adoption help -> opens informational guidance about adopting a cat in Uzbekistan, including veterinary checks, identification/passport, ownership transfer, apartment/common-area rules, and official source links
  - edit profile fields,
  - tap Posts to view the user's Cat posts and Cat needs help posts,
  - tap Comments to view the user's comments,
  - open My lost pets and My rehoming posts from their existing routes,
  - logout confirmation.
- Edge cases:
  - missing or failed avatar -> initials fallback; load failure -> retry state.

5.16 User Public Profile Screen
- Purpose: view another contributor.
- Layout:
  - same identity and stats surface as the self profile, with name, avatar, short public bio, posts, likes received, and comments. No email, phone, Telegram, language, or account internals appear.
  - Recent posts shows up to four current Feed post cards and a See all action to the existing posts screen; comments open from the stat.
  - on wide screens, the summary stays fixed in the left column while the recent-post list scrolls within the available viewport height; compact screens use one vertical page scroll.
  - Report and Block appear in the app bar overflow menu. A successful block disables the Block action for that screen session.
  - one column on phones; on wide screens, identity/stats and recent posts sit side by side within AppWidths.wide.
- Interactions:
  - open posts and comments from stats when public activity is enabled; tap a post card for its existing detail route.
  - Report opens the existing report route. Block retains its sign-in requirement and confirmation.
- Privacy:
  - when public activity is disabled, the profile remains visible, the activity stats do not navigate, and a calm private-activity state replaces the preview. No preview request is sent when privacy is already known.
  - a privacy response during a preview request also suppresses previews and navigation.

5.17 Edit Profile Screen
- Purpose: update display name, phone number, Telegram username, bio, and avatar.
- Layout:
  - a centered form no wider than AppWidths.readable, with comfortable mobile padding.
  - compact profile-photo surface with an 88px avatar, initials fallback, and one Change photo action.
  - Change photo opens a Material source sheet for gallery or camera; a selected photo previews immediately.
  - Personal information groups name, optional Uzbekistan phone, Telegram username, and multiline bio.
  - Save changes is the primary action, beside Cancel on wide screens and full width on mobile.
- Save changes is disabled until a field or avatar changes, and becomes disabled again if text values are restored to their initial values. The empty Bio field has no example placeholder.
- Validation:
  - name max 100,
  - phone number optional, owner-only for MVP and must use Uzbekistan format shown with placeholder digits: +998 xx xxx xx xx,
  - Telegram username is 5–32 letters, numbers, or underscores; a leading @ is removed before saving,
  - bio max 1000,
  - avatar type/size constraints from media policy.
- Edge cases:
  - back or Cancel with unsaved text or avatar changes asks whether to discard them.
  - avatar uploads before profile details. If the avatar saves but details fail, keep the form, refresh profile data, and retry details without uploading that avatar again.
  - save conflict/network failure -> keep unsaved details and retry option.
- Successful Save changes returns to Profile with a localized confirmation.

5.17.1 Settings Screen
- Purpose: manage application preferences.
- Layout:
  - theme selector
  - language selector: English, Uzbek, Russian
  - privacy toggle: allow other people to view my posts and comments
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
- MVP languages: English, Russian, and Uzbek (EN / RU / UZ).

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
- Create Entry
- Cat Post / Cat Needs Help Form
- Ordinary Post Map Picker
- Feed
- Post Detail
- Leaderboard
- Profile (self)
- Public User Profile
- Edit Profile
- Report Content
- Moderator Reports List
- Moderator Report Detail

Notifications
-------------
- The authenticated Feed app bar contains a bell with an unread badge. The inbox lists newest first, shows unread state and time, supports load more, and has an explicit Mark all as read action.
- Tapping a comment or reply opens its post at the existing comments section. Tapping a nearby Lost Pet opens its detail. A due follow-up push opens Feed so the existing persisted follow-up listener can present the due question. An inactivity push opens Feed, not an empty inbox. Unavailable content is handled without an external URL.
- Notification settings provide independent Android push choices for comments, replies, follow-ups, nearby Lost Pets, and inactivity. Nearby alerts require an explicit map point; a one-time current-location button is available. Disabling nearby removes the saved point. The fixed radius is 500 m. No background location permission or tracking is used.
- Android notification permission is requested only after explanatory context in settings. If denied or Firebase is not configured, the inbox remains functional and the setting explains why device push is unavailable. Web uses the inbox without browser push.

11. Out of Scope for MVP UI
---------------------------
- Web Push and iOS push
- In-app chat/direct messages
- Offline mode synchronization UI
- Web layouts
- AI matching confidence visualization

Change Log
----------
- 2026-07-23: Initial MVP UI/UX architecture document.

