# Mushukistan Privacy Policy

Version: 2026-10-15

This Privacy Policy explains how Mushukistan collects, uses, stores, shares, and deletes personal data. It applies to the Mushukistan Android app and web app.

## 1. Who is responsible for your data

Mushukistan is operated by Sardor Muxtorov, an individual developer.

Data controller: Sardor Muxtorov

Privacy contact: sardor.datascience@gmail.com

## 2. Data Mushukistan collects

Mushukistan collects only the data needed to operate a social platform and interactive map for cat owners and the wider cat community in Tashkent.

Account data:
- Email address.
- Password hash for password accounts.
- Google Sign-In email/name when Google Sign-In is used.
- Registration time, last login time, coarse last-active time, preferred language, and accepted legal-document version.

Profile data:
- Name.
- Avatar URL.
- Phone number.
- Telegram username.
- Bio.
- Public activity visibility preference.

User content:
- Cat records and observations.
- Cat photos.
- Cat information and statuses.
- Descriptions and comments.
- Likes.
- Reports.
- Lost-pet alerts, photos, and additional information.
- Adoption and rehoming posts, photos, and additional information.

Location data:
- Current location when used for nearby search.
- Observation location when attached to a post.
- Cat canonical location.
- Place-search location.
- Lost-pet last-seen location.
- Last authorized device location stored privately only after a separate explicit nearby-alert disclosure and consent, with Android location permission; no location history is stored.

Contact data published by the user:
- Lost-pet and adoption/rehoming posts copy your profile phone number (and Telegram username, if you added one). They are shown only after you tick the contact consent box on the post, and only to signed-in Mushukistan users. Visitors who are not signed in never see them, and they are not shown in lists, feeds, maps or notifications. In the current app a signed-in user sees them after tapping Contact Owner; older app versions may show them as soon as the post is opened. Each user can view only a limited number of owners' contacts per day and per week (currently 15 and 40; the operator may change these limits). Mushukistan records which signed-in user viewed which post's contact and when, without storing the contact itself in that record.

Technical and security data:
- API request metadata used for authentication, rate limiting, abuse prevention, security, troubleshooting, and operational logs.
- Android push device token stored encrypted, token hash, notification preferences, inbox read state, and bounded delivery status.

## 3. Photos and media

Photos are validated, resized, compressed, thumbnailed, and processed without preserving EXIF metadata. This reduces unintended location and device metadata exposure.

Binary image files are stored in Cloudflare R2 when configured, or in local media storage during development. PostgreSQL stores media URLs.

When an account is deleted, Mushukistan attempts best-effort cleanup of uploaded profile, post, lost-pet, and adoption/rehoming media associated with that account. Media cleanup can fail if storage is unavailable, if a URL cannot be mapped to a stored object, or if the storage provider rejects the deletion request.

## 4. How Mushukistan uses data

Mushukistan uses data to:

- Create and manage accounts.
- Authenticate users and verify email addresses.
- Publish and display user content.
- Show nearby cats, places, and map content.
- Operate lost-pet and adoption/rehoming contact features.
- Enable comments, likes, reports, moderation, and account settings.
- Deliver structured in-app notifications and permitted Android push alerts.
- Prevent abuse, rate-limit requests, and secure the service.
- Comply with legal obligations and enforce policies.

## 5. Public information

Some information may be visible to other users or visitors, depending on the feature and account settings. Public information may include:

- Cat sightings, photos, descriptions, and locations.
- Cat profile information.
- Comments.
- Public profile summaries.
- Lost-pet photos and last-seen locations.

Contact details are not public information: section 2 explains who can see them.

Do not publish another person's private information, photo, phone number, address, or location unless you have permission.

## 6. Third-party services

Mushukistan uses or may use these third-party services:

- DigitalOcean for hosting and database infrastructure.
- Cloudflare R2 for uploaded media and object metadata when configured.
- Google when a user chooses Google Sign-In.
- Google Firebase Cloud Messaging for Android push delivery when configured and permitted.
- OpenStreetMap for map tiles and map/place data.
- PostHog for server-side product analytics and error reports, only when configured by the operator.

Email provider: not configured in the verified repository.

Backup provider: not configured in the verified repository.

The Mushukistan apps do not include analytics SDKs, advertising SDKs, crash reporting SDKs, or AI features, and Firebase Analytics collection is disabled in the Android app. Separately, the Mushukistan server can optionally send usage data to PostHog (server-side analytics) when the operator configures it; if it is not configured, nothing is sent. When enabled, it receives event names such as post created, comment created, post liked, report submitted, profile updated, password changed and owner contacted, simple counts such as the number of photos, the ID of the signed-in account so that events can be linked to an account, automatic reports of server errors with technical details, and health-check log lines. Event data does not include phone numbers, Telegram handles, email addresses, passwords, post text or photos. Android notifications use Firebase Cloud Messaging (Google) after device notification permission is granted. The web app has an in-app inbox but no browser push.

The notification inbox stores event type, relevant content/comment identifiers, actor and recipient references, creation time, and read time. Android push delivery stores encrypted device tokens and token hashes, preferences, bounded delivery attempts, and errors without full token values in ordinary logs. Push messages contain no phone numbers, Telegram handles, precise pet coordinates, private alert coordinates, or full comment text.

Nearby Lost Pet alerts use only the last authorized device location after a separate, explicit privacy disclosure and consent, plus Android location permission. The point is private, replaced on authenticated foreground launch/resume, and matched at a fixed 500 m. There is no map selection, fallback Tashkent position, background permission, continuous tracking, or location history. Consent can be withdrawn under Profile -> Settings -> Nearby alert privacy. Missing/revoked permission, disabled location services, withdrawal, and an invalid or unavailable fix clear the point and stop matching when the authenticated app next connects. Offline deletion is retried on a later active resume; a server cannot observe an offline OS permission change. One account retains one point, from the last consenting Android device; device consent is scoped to that account on that installation. Browser activity never uploads or clears an Android point.

Comments, replies, pet follow-ups, and inactivity reminders are enabled automatically, including previously saved disabled category choices. Inactivity reminders are push-only, once after seven full inactive days; Android push requires operating-system permission. The in-app inbox remains available when push is denied. Nearby alerts additionally require explicit privacy consent and an authorized location as described above.

## 7. Cookies and browser storage

The Android app does not use cookies.

The web app does not intentionally set advertising, analytics, or tracking cookies. The web app may use browser storage through the Flutter secure storage integration to keep the user's access token for authentication.

## 8. Account deletion and retention

Users can delete their Mushukistan account directly inside the app:

Settings -> About account -> Delete account

Users who cannot access the app can start account deletion from https://mushukistan.uz/delete-account. The website asks for the account email address and, if an active account exists, sends a time-limited confirmation link to that email address. The website does not reveal whether the submitted email address has an account. The account is deleted only after the confirmation link is opened and deletion is explicitly confirmed.

When account deletion is confirmed, Mushukistan deactivates and anonymizes the account. Login is disabled, authentication credentials are removed, and profile personal information is removed, including email address, password hash, name, avatar URL, phone number, Telegram username, bio, legal acceptance records, last-login and last-active data, device push tokens, notification preferences, and private alert point. Inbox rows received by the deleted account are removed; its actor reference on other users' notifications becomes anonymous.

Mushukistan also removes the user's likes, removes account-related blocking records, removes affected leaderboard cache entries, hides and anonymizes user-owned posts, comments, lost-pet posts, and adoption/rehoming posts, clears copied contact details from lost-pet and adoption/rehoming posts, and removes the user as creator/reporter/handler where possible.

Some non-public or anonymized records may remain after account deletion where they are needed for service integrity, moderation, safety, abuse prevention, or legal compliance. For example, Mushukistan may retain anonymized content records, cat records, content locations attached to retained records, timestamps, moderation/report records, and a non-personal internal tombstone identifier for the deleted account. These retained records are not intended to identify the deleted user and the deleted account is not publicly accessible or usable for authentication.

The verified repository does not define a guaranteed automatic deletion period for all retained records.

Backups are not configured in the verified repository. If backups are enabled later, backup retention and deletion schedules must be documented before production release.

## 9. Your rights and choices

Users may request access, correction, deletion, restriction, objection, portability, and withdrawal of consent where applicable by contacting sardor.datascience@gmail.com.

Users can manage some profile and privacy settings inside the app, including public activity visibility and account deletion.

## 10. International processing

Data may be processed outside the user's country by service providers such as DigitalOcean, Cloudflare, Google, and OpenStreetMap. Mushukistan should use provider data-processing terms or data-processing agreements where available.

## 11. Security

Mushukistan uses authentication, rate limiting, image validation, EXIF stripping, structured storage, and access controls to protect the service and user data. No system can be guaranteed completely secure.

## 12. Changes to this Privacy Policy

Mushukistan may update this Privacy Policy when the service, legal requirements, or operational practices change. If changes are material, Mushukistan should provide notice in the app or require renewed acceptance where appropriate.
