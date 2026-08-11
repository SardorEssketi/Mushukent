# Mushukistan Privacy Policy

Version: 2026-08-01

This Privacy Policy explains how Mushukistan collects, uses, stores, shares, and deletes personal data. It applies to the Mushukistan Android app and web app.

## 1. Who is responsible for your data

Mushukistan is operated by Sardor Muxtorov, an individual developer.

Data controller: Sardor Muxtorov

Privacy contact: sardor.datascience@gmail.com

## 2. Data Mushukistan collects

Mushukistan collects only the data needed to operate a social map for street cats in Tashkent.

Account data:
- Email address.
- Password hash for password accounts.
- Google Sign-In email/name when Google Sign-In is used.
- Registration time, last login time, preferred language, and accepted legal-document version.

Profile data:
- Name.
- Avatar URL.
- Phone number.
- Bio.
- Public activity visibility preference.

User content:
- Cat sightings.
- Cat photos.
- Cat profile information.
- Descriptions and comments.
- Likes.
- Reports.
- Lost-pet posts, photos, and additional information.

Location data:
- Current location when used for nearby search.
- Observation location when attached to a post.
- Cat canonical location.
- Place-search location.
- Lost-pet last-seen location.

Contact data published by the user:
- Lost-pet posts publicly show the user's profile phone number only after explicit phone-publication consent.

Technical and security data:
- API request metadata used for authentication, rate limiting, abuse prevention, security, troubleshooting, and operational logs.
- Security and operational logs are kept for up to 90 days unless needed for security or legal reasons.

## 3. Photos and media

Photos are validated, resized, compressed, thumbnailed, and processed without preserving EXIF metadata. This reduces unintended location and device metadata exposure.

Binary image files are stored in Cloudflare R2 when configured, or in local media storage during development. PostgreSQL stores media URLs.

## 4. How Mushukistan uses data

Mushukistan uses data to:

- Create and manage accounts.
- Authenticate users and verify email addresses.
- Publish and display user content.
- Show nearby cats, places, and map content.
- Operate lost-pet contact features.
- Enable comments, likes, reports, moderation, and account settings.
- Prevent abuse, rate-limit requests, and secure the service.
- Comply with legal obligations and enforce policies.

## 5. Public information

Some information may be visible to other users or visitors, depending on the feature and account settings. Public information may include:

- Cat sightings, photos, descriptions, and locations.
- Cat profile information.
- Comments.
- Public profile summaries.
- Lost-pet photos and last-seen locations.
- Lost-pet phone numbers when the user explicitly consented to publish the phone number.

Do not publish another person's private information, photo, phone number, address, or location unless you have permission.

## 6. Third-party services

Mushukistan uses or may use these third-party services:

- DigitalOcean for hosting and database infrastructure.
- Cloudflare R2 for uploaded media and object metadata when configured.
- Google when a user chooses Google Sign-In.
- OpenStreetMap for map tiles and map/place data.

Email provider: not configured in the verified repository.

Backup provider: not configured in the verified repository.

Mushukistan does not include analytics SDKs, advertising SDKs, crash reporting SDKs, push notifications, or AI features in the verified repository.

## 7. Cookies and browser storage

The Android app does not use cookies.

The web app does not intentionally set advertising, analytics, or tracking cookies. The web app may use browser storage through the Flutter secure storage integration to keep the user's access token for authentication.

## 8. Retention

Active account and content data is retained while the account or content remains active.

When an account is deleted, Mushukistan anonymizes the account, disables login, deletes likes, removes profile personal data, hides and anonymizes user-owned posts/comments/lost-pet posts, removes copied lost-pet phone numbers, and attempts media cleanup.

Mushukistan may retain limited records when necessary for legal compliance, security, fraud prevention, abuse prevention, copyright enforcement, or moderation audit purposes.

Backups are not configured in the verified repository. If backups are enabled later, backup retention and hard-delete schedules must be documented before production release.

## 9. Account deletion

Users can delete their Mushukistan account directly inside the app:

Settings -> About account -> Delete account

Users can also submit a deletion request by email:

support@mushukistan.uz

## 10. Your rights and choices

Users may request access, correction, deletion, restriction, objection, portability, and withdrawal of consent where applicable by contacting sardor.datascience@gmail.com.

Users can manage some profile and privacy settings inside the app, including public activity visibility and account deletion.

## 11. International processing

Data may be processed outside the user's country by service providers such as DigitalOcean, Cloudflare, Google, and OpenStreetMap. Mushukistan should use provider data-processing terms or data-processing agreements where available.

## 12. Security

Mushukistan uses authentication, rate limiting, image validation, EXIF stripping, structured storage, and access controls to protect the service and user data. No system can be guaranteed completely secure.

## 13. Changes to this Privacy Policy

Mushukistan may update this Privacy Policy when the service, legal requirements, or operational practices change. If changes are material, Mushukistan should provide notice in the app or require renewed acceptance where appropriate.
