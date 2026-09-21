  ## 1. Overall assessment

  Mushukistan has most of its MVP flows represented, and the warm cream/terracotta/sage palette gives it a useful identity. The full-screen map, cat/Tashkent imagery, photography,
  and straightforward Material icons are good foundations.

  The interface currently feels like a functional prototype assembled screen by screen rather than one coherent product:

  - Visual hierarchy changes between screens.
  - Cards, pills, badges, and centered state panels are overused despite the AGENTS.md constraints.
  - Feed and map presentation files are oversized and contain many one-off components.
  - Lost-pet, adoption, and observation experiences solve similar problems using different layouts and state patterns.
  - Loading, errors, empty states, success feedback, media galleries, and profile layouts are inconsistent.
  - Several documented actions are absent or inaccessible.
  - Responsive behavior is mostly “scroll or constrain width,” with little deliberate support for small Android screens, landscape, or large text.

  The most serious finding is not cosmetic: location denial or GPS failure returns a fixed Tashkent coordinate and presents it as the user’s actual location. Creation flows can
  consequently publish a false coordinate.

  Primary implementation touchpoints are frontend/lib/core/theme/app_theme.dart:6, frontend/lib/core/widgets/app_surface.dart:5, frontend/lib/core/routing/app_router.dart:42,
  frontend/lib/core/widgets/app_shell_scaffold.dart:12, frontend/lib/features/feed/presentation/screens/feed_screen.dart:59, frontend/lib/features/map/presentation/screens/
  map_screen.dart:119, and frontend/lib/core/location/location_service.dart:18.

  ## 2. Most important UI/UX problems

   Priority    Problem                                                                             Required outcome                                                                 
  ━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   P0          GPS denial, disabled service, and errors silently become a fallback coordinate      Represent actual, denied, unavailable, and city-fallback states separately.
                                                                                                   Never show or publish fallback as measured location.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P0          Report flow exposes editable target type and UUID                                   Keep the target immutable and show a human-readable target summary. Users should
                                                                                                   never handle internal IDs.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P0          Moderator UI is not discoverable or role-gated in the client                        Add role-aware entry and routing. Backend authorization remains mandatory.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P0          Moderator detail depends on the report being present in the currently loaded        Fetch a report directly or provide a reliable cross-status lookup; never leave a
               open-report page                                                                    deep link on an indefinite spinner.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P1          Map entities lack a strong visual taxonomy and clustering                           Use shape, icon, and color together; add clusters, legend/filter clarity, and
                                                                                                   predictable layer priority.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P1          Navigation differs from documentation and loses context                             Restore “Feed / Map / Add / Leaderboard / Profile,” select the Add tab normally,
                                                                                                   and preserve branch stacks.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P1          Creation routes retain bottom navigation and do not guard unsaved drafts            Make creation a focused flow or confirm before abandoning it. Preserve entered
                                                                                                   data on back, retry, and rotation.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P1          Feed begins with a dismissible hero-like block and nested quick-action cards        Remove it. Start with visible feed filters and content.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P1          State handling is fragmented                                                        Replace raw exceptions, plain centered text, and 36 spinner usages with shared
                                                                                                   loading, empty, error, retry, and success patterns.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P1          Accessibility requirements are not consistently met                                 Restore 48dp touch targets, avoid FittedBox text shrinking, support large text,
                                                                                                   and add semantics to images, markers, and icon actions.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P2          The light palette has contrast failures and the dark theme loses product            Use the existing dark color variants for accessible controls and define a
               identity                                                                            complete explicit dark theme.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P2          Localization is incomplete                                                          Remove hard-coded English in auth, lost-pet creation, status labels, validation,
                                                                                                   controller messages, and legal screens.
  ──────────  ──────────────────────────────────────────────────────────────────────────────────  ──────────────────────────────────────────────────────────────────────────────────
   P2          Similar components are repeatedly reimplemented                                     Consolidate galleries, badges, contact actions, error states, profile sections,
                                                                                                   forms, and comment presentation.

  Measured light-theme contrast concerns:

  - White on terracotta: 4.03:1.
  - White on sage: 3.59:1.
  - Terracotta on cream: 3.83:1.
  - White on terracottaDark: 6.60:1.
  - White on sageDark: 6.39:1.

  Use the dark variants for small text and filled controls. Keep the lighter colors for decorative backgrounds, borders, and larger icons.

  ## 3. Proposed design direction

  The direction should be a warm, practical community utility—not a social-media clone and not a decorative startup dashboard.

  - Friendly through cat photography, plain language, helpful empty states, and warm surfaces.
  - Mature through restrained color, compact spacing, ordinary rectangular controls, and clear information hierarchy.
  - Map-first where location matters, feed-first for community browsing.
  - Functional labels only. Avoid decorative badges, promotional copy, and mini-explanations around every section.
  - Use borders and spacing for hierarchy. Shadows should be limited to map controls and overlays that genuinely need separation.
  - Keep the realistic cat/Tashkent app icon, but do not import its blue skyline into the interface palette. The established warm UI palette should remain dominant.
  - Do not add mascot illustrations, cartoon paw backgrounds, gradients, glows, or oversized rounded containers.

  ## 4. Recommended design-system changes

  ### Color

  Retain cream, warmSurface, graphite, terracotta, sage, lost, and adoption.

  - Use terracottaDark as the primary light-theme button/link color.
  - Use terracotta for selected icons, subtle emphasis, and tinted backgrounds.
  - Use sageDark where white foreground text is required.
  - Reserve lost for lost-pet urgency, errors, and destructive actions.
  - Reserve adoption for adoption/rehoming identity.
  - Do not let entity colors leak into unrelated controls.
  - Define the dark theme explicitly from warm charcoal neutrals and the existing inverse/warm colors. Do not use ColorScheme.fromSeed as the complete dark design.

  ### Typography

  Keep Roboto because it is already the Android product font.

  - Screen/app-bar title: 20–22sp, weight 600–700.
  - Section title: 17–18sp, weight 600.
  - Body: 15–16sp, weight 400.
  - Secondary/meta: 12–14sp with tested contrast.
  - Button labels: 14sp, weight 600.
  - Stop using weight 800 as a default.
  - Navigation labels should be at least 12sp.
  - Do not use FittedBox to shrink translated text. Allow wrapping or switch compact controls to dropdown/list patterns.

  ### Spacing and layout

  Retain the existing 4/8/12/16/24/32 scale and eliminate ad hoc 6/10/14/18/20/28 values where possible.

  - Horizontal page inset: 16dp on compact phones, 20dp on larger phones.
  - Form width: maximum 560dp.
  - Reading/detail width: maximum 760dp.
  - Feed width: approximately 560–620dp for a single readable column.
  - Avoid fixed-height grids for cards containing variable localized text.

  ### Shape and elevation

  - Standard card radius: 8–10dp.
  - Inputs and buttons: 8dp.
  - Bottom-sheet top radius: 12dp.
  - Dialog radius: 10–12dp.
  - Status labels: 6–8dp, not 999.
  - Circular shape is reserved for avatars, location indicators, and genuinely circular icon controls.
  - Content cards should use a subtle border and zero elevation.
  - Map controls may use a small neutral shadow, no more than approximately 0 2px 8px.

  ### Navigation and controls

  - Keep the five-item NavigationBar, but remove its selected pill. Use selected color, weight, and filled icon.
  - Show “Leaderboard,” not “Community,” because the destination contains only rankings.
  - Use normal text tabs or an underline for content filters.
  - Use checkboxes in map filters and radio rows for mutually exclusive choices.
  - Filled buttons represent one primary action per section.
  - Reporting, blocking, and secondary contact methods belong in menus or secondary actions.

  ### Images

  - Feed media: consistent 4:3 frame using thumbnails.
  - Detail media: consistent 4:3 gallery, optionally constrained on tablets.
  - Creation thumbnails: consistent square 88–96dp.
  - Use the same unavailable-image placeholder everywhere.
  - On phones, use swipe and a compact current/total counter. Hide desktop-style arrows unless pointer/large-screen behavior warrants them.
  - Add semantic descriptions such as “Photo 2 of 4 for lost pet Momiq.”

  ## 5. Recommended changes screen by screen

   Screen or flow                    Implementation brief                                                                                                                           
  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Native splash and Auth Gate       Keep the warm native background and brand image. Make the Flutter startup state visually continuous with it. Use one small status line.
                                     Failure should show a concise explanation and Retry; avoid a card-within-centered-panel composition.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Login                             Use one title, not an app-bar title plus a second headline. Present labels above fields. Remove promotional subtitle copy. Keep Google
                                     secondary and use a plain “or” divider. Localize all text. Show API errors next to the relevant field where possible.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Registration                      Fix the contradiction where the label says “optional” but name validation requires a value. Keep legal rows readable and fully tappable. Move
                                     Google’s conditional legal acceptance into a dedicated dialog/sheet so the form does not abruptly expand after an API response.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Verify Email                      Emphasize the destination email, verification status, resend cooldown, and return-to-login action. Show development verification help only in
                                     development. Use distinct pending, success, expired, and resend-failed states.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Authenticated onboarding          Keep the documented language and welcome/support sequence, but make both dialogs scroll-safe. Language rows should be simple radio rows. De-
                                     emphasize the payment card number; support is optional tertiary content, not the visual focus of a mandatory first-run dialog.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Main navigation                   Use the documented labels. Selecting Add should navigate to the Add root rather than opening a modal while another tab remains selected.
                                     Preserve each branch’s history; only reset a branch when its already-selected tab is tapped intentionally.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Add root                          Use a plain three-row selector for Observation, Lost pet, and Adoption/rehoming. Remove card-with-circle-icon repetition. Show an existing
                                     observation draft as a normal continuation row, not a status card.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Feed header and filters           Remove _HomeHeader, its badge, decorative headline, and four-card action grid. Use app-bar title “Feed,” then a visible filter strip. Use
                                     Recent, Popular, Needs help, Lost pets, Adoption. Popular period should be a compact secondary control.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Observation feed card             Order content as author/avatar + relative time, image, cat/observation name with one functional status label, description preview, then like/
                                     comment actions. Remove the chevron and “Cat name:”/“Description:” prefixes. Hide Unknown as documented.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Lost-pet feed card                Preserve a strong but restrained lost indicator and left accent. Show resolved/found state using isResolved. Include Contact owner and View
                                     map actions without requiring entry into details.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Adoption feed card                Use the same structural rhythm as other feed cards, with an adoption label and Contact owner action. Do not add location treatment.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Feed behavior                     Implement cursor pagination and a bottom loading/end state. Empty state should include one relevant action. Preserve optimistic likes. Do not
                                     switch to a fixed-ratio two-column grid unless card height is bounded and tested.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Observation detail                Remove the outer all-content card and nested stat cards. Use author row, gallery, action row, cat/status, description, publication date,
                                     location summary, and comments. Add View on map when location exists. Put Report and owner-only Delete in an overflow menu.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Comments                          Use one shared implementation for all target types. Replace rounded bubbles at every depth with compact rows and a subtle thread connector.
                                     Limit visual indentation while retaining unlimited logical nesting. Restore 48dp Reply/Report controls. Add own-comment deletion when
                                     supported. Use a clear reply context above the composer.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Map startup and permission        Show the Tashkent city map immediately. Explain location use in a small banner/sheet and request permission only when Nearby or Recenter is
                                     used. Manual placement must work without GPS permission. Never represent the fallback city coordinate as the current user.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Map markers                       Define one stable taxonomy: cats use a paw/location silhouette, lost pets use an alert shape, vets use a medical cross, shops use storefront,
                                     shelters use home/shelter. Use shape and icon in addition to color. Use 44–48dp hit regions and cluster dense markers.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Map overlays                      Keep Refresh, Filters, and Recenter in fixed positions. Do not move the recenter button when a footer appears. Remove the transient
                                     coordinate/count footer. Show brief result text only when filters or refresh change the visible set.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Map filtering                     Keep a scrollable checkbox sheet with clear Apply and Cancel actions. Add a short legend matching the exact marker visuals. Avoid count badges
                                     floating over filter controls. Load map layers independently so one failed layer does not blank the entire map.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Cat marker preview                Do not navigate directly after an invisible network fetch. Open a compact sheet with available image, name or “Cat observation,” status, last-
                                     seen date, distance when available, and “Open latest observation.” Do not implement a full cat profile until documentation resolves its MVP
                                     status.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Place preview sheet               Use a scrollable sheet capped around 75–80% height. Order information as name/category, address and hours, primary Call/Directions actions,
                                     website/social links, description, then verification/source metadata. Show multiple categories as plain compact text or restrained labels.
                                     Handle failed external launches.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Lost-pet map sheet                Show thumbnail, name, alert date/status, Contact owner, and Open alert. Do not make “Open post” the only useful action.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Observation location selection    Do not start GPS resolution on screen entry. Present Use current location, Mark on map, and Continue without location first. Manual map starts
                                     at Tashkent and remains usable after denial. Invoke the documented confirmation before attaching current coordinates.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Observation details               Show selected photo thumbnails, a clear location summary, description, visibility if the API continues to support it, and Publish. Preserve
                                     values when returning from location selection. Remove the pill-style located/feed-only badge.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Observation success               Keep a dedicated success state, but remove the technical post ID and unnecessary unnamed-cat summary. Show thumbnail, “Observation published,”
                                     View post/feed, and Add another.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Lost-pet creation                 Reuse the common photo picker and form sections. Display the actual profile phone number read-only before consent. Keep the Tashkent map but
                                     handle GPS denial visibly. Preserve the draft and provide consistent success feedback.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Adoption creation                 Share photo, pet-name, information, phone-preview, consent, error, and submission components with lost-pet creation. Keep it location-free.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Lost/adoption details             Share the gallery, author metadata, description, contact actions, comments, and overflow actions. Lost details additionally show last-seen map
                                     action and resolved state. Contact owner must be the clear primary action.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Self profile                      Replace the header card and orphaned metric-card grid with a plain profile header and one horizontal stat row separated by dividers. Reduce
                                     four app-bar icons to Edit plus overflow. Add normal rows for Settings, Adoption help, and moderator tools. Show a short My observations
                                     preview or a clear list entry.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Public profile                    Match the self-profile visual structure. Put Block in overflow rather than a prominent chip. Do not show both action chips and a duplicate
                                     inline observation list; use one activity presentation with Observations and Comments.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Activity lists                    Show thumbnails for observations, useful content context for comments, localized dates, pagination, and coherent empty/error states.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Edit profile                      Use the shared content width. Open one photo-source sheet from the avatar action. Label required/optional fields accurately. Preserve unsaved
                                     edits and only enable Save after a change.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Settings                          Rename “Original” to “System.” Replace horizontally scrolling segmented controls and repeated language icons with vertical radio rows or
                                     compact dropdowns. Persist theme locally. Keep changes pending until Save as documented.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   About account and legal           The basic list structure and delayed deletion confirmation are sound. Group account, legal, and destructive rows with ordinary section
                                     hierarchy. Make legal content available in all supported languages or clearly declare that it is English-only.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Leaderboard                       Restore the destination title “Leaderboard.” Remove decorative subtitle copy. Use underline tabs for ranking type and a compact period
                                     control. Render rows with dividers instead of separate cards; retain functional gold/silver/bronze rank distinction.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Report content                    Hide target type and UUID. Render an immutable target summary using available title, author, excerpt, and type. Use radio-style reason rows,
                                     details only for Other, and return or show a completed confirmation after submission. Handle duplicate reports specifically.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Moderator report list             Add Open/Resolved/Dismissed tabs, reporter, target type, reason, time, target availability, cursor pagination, and retry. Use localized labels
                                     instead of raw backend values.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Moderator report detail           Fetch reliably by ID. Show report metadata and target preview first. Replace generic status/action dropdown combinations with explicit
                                     Resolve, Dismiss, Remove content, and Suspend user actions valid for that target. Every destructive action requires confirmation and supports
                                     an optional note.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Dialogs and sheets                Make long content scrollable, retain 48dp actions, use 10–12dp radius, and avoid cards inside dialogs/sheets. Destructive confirmation uses
                                     one red action.
  ────────────────────────────────  ────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────
   Loading/empty/error/success       Feed/profile lists receive skeleton rows; initial isolated pages may use a centered spinner. Maps retain the canvas while layers load. Empty
                                     states use one sentence and at most one action. All errors use localized user messages and Retry where recovery is possible.

  ### Contract gaps to resolve before promising UI behavior

  - PostSummary contains no distance value, despite the documented feed distance requirement.
  - Frontend user models contain no moderator role, so a moderator-only navigation entry cannot currently be rendered reliably.
  - The frontend client exposes no owner post deletion or own-comment deletion method.
  - There is no direct report-detail fetch; current moderation detail relies on the open report list.
  - Report target summaries do not expose image URLs.
  - UI_UX.md says cat profile pages are outside MVP, while the PRD still describes a Cat Page. The current router omits cat details and the existing screen is only a skeleton.
    Resolve the documentation before implementing one.

  - UI_UX.md also contains a stale “English only” statement while the PRD and application support English, Uzbek, and Russian.

  These are documentation/API decisions, not reasons to fake UI data.

  ## 6. Reusable components to create or refactor

  - AppPageBody: standard phone padding, maximum width, keyboard-safe scrolling.
  - AsyncStateView: loading, empty, error, retry, and retained-content refresh handling.
  - InlineErrorBanner: localized user message without raw exception text.
  - EntityTypeLabel: restrained rectangular Lost/Adoption/Needs help label.
  - UserMetaRow: avatar, name, publication time, and overflow action.
  - PhotoCarousel: shared feed/detail gallery, counters, placeholders, semantics.
  - PhotoPickerGrid: shared one-to-five photo selection, removal, processing, and error feedback.
  - FeedEntityCard: shared card anatomy with type-specific actions.
  - EngagementBar: like/comment counts and pending behavior.
  - ContactActions: call, Telegram, website, and launch-failure feedback.
  - LocationChoicePanel and LocationPickerMap: explicit location-state handling.
  - MapEntityMarker, MapClusterMarker, and MapLegendRow.
  - PlacePreviewSheet, CatPreviewSheet, and LostPetPreviewSheet.
  - CommentComposer and CommentThreadRow.
  - ProfileHeader and ProfileStatsRow.
  - SettingsSection and SettingsChoiceRow.
  - ReportTargetSummary.
  - ConfirmActionDialog, including destructive and moderation variants.

  Refactor without changing the established architecture:

  - Move feed pagination/filter state into a feature Riverpod controller.
  - Move map layers, permission state, refresh state, and independent layer failures into a map discovery controller.
  - Move lost/adoption form drafts out of individual widgets so they survive navigation and retry.
  - Parameterize the three comments wrappers around one target adapter.
  - Share lost/adoption visual components while keeping their domain models and business rules distinct.

  ## 7. Components and patterns that should remain unchanged

  - Feature-first Flutter organization, Riverpod, GoRouter, and Material 3.
  - The five documented primary destinations.
  - Full-screen flutter_map, OpenStreetMap attribution, and Tashkent boundaries.
  - The existing warm palette and realistic cat/Tashkent brand asset.
  - The established spacing scale and AppContentWidth concept.
  - Material icon family; outlined icons for normal state and filled icons for selected state.
  - Thumbnail use in feed and swipeable multi-photo galleries.
  - Maximum five photos.
  - Uzbekistan phone validation and explicit public-phone consent.
  - Automatic unnamed Unknown cat creation; no matching, naming, or nearby-cat selection flow.
  - Optimistic likes with rollback.
  - Account-deletion confirmation and five-second delay.
  - External call, Telegram, website, and official-source behavior.

  ## 8. Potential UX regressions to avoid

  - Never publish a fallback or clamped coordinate as user-selected GPS.
  - Do not add cat matching, AI confidence, cat naming, messaging, following, notifications, or other roadmap features.
  - Do not introduce a cat profile until the documentation conflict is resolved.
  - Do not make lost-pet and adoption content visually indistinguishable from observations.
  - Do not encode map entities by color alone.
  - Do not hide location or phone-publication consent.
  - Do not reset tab stacks on every navigation-bar tap.
  - Do not discard form text/photos after upload failure, back navigation, rotation, or temporary permission denial.
  - Do not expose UUIDs, enum codes, exception strings, or backend action names.
  - Do not flatten comment relationships; limit visual indentation while preserving reply ancestry.
  - Do not reduce touch targets to make dense layouts fit.
  - Do not use FittedBox to defeat text scaling or localization.
  - Do not replace thumbnail URLs with full-resolution feed images.
  - Do not block the entire map because one optional layer failed.
  - Do not make support/donation content the dominant mandatory onboarding action.
  - Do not reintroduce hero copy, metric-card grids, pill overload, large radii, gradients, or decorative shadows.

  ## 9. Recommended implementation order

  1. Resolve documentation/API gaps: cat page scope, supported locales, moderator role, report detail, ownership/delete actions, and feed distance.
  2. Add visual regression and widget-test baselines at 320×568, 360×800, 412×915, and 640×360 landscape; test text scaling at 1.0, 1.3, and 2.0 in light and dark themes.
  3. Rebuild theme tokens and shared page/state/control primitives.
  4. Correct primary navigation, branch history, focused-flow navigation, and draft-abandonment behavior.
  5. Correct location-state modeling before touching map visuals.
  6. Redesign the map marker taxonomy, clustering, controls, independent loading, and preview sheets.
  7. Refactor feed cards, filters, media, pagination, and feed states.
  8. Refactor observation/lost/adoption details and shared comments.
  9. Refactor observation, lost-pet, and adoption creation flows with persistent drafts and shared form components.
  10. Polish startup, authentication, verification, and onboarding.
  11. Rebuild self/public profiles, activity, edit profile, settings, and account/legal screens.
  12. Rebuild report and moderation flows, then simplify the leaderboard.
  13. Run final accessibility, localization, keyboard, TalkBack semantics, image failure, offline/error, deep-link, and mid-range Android performance checks.