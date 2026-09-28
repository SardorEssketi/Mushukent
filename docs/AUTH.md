AUTH.md

Mushukistan Authentication and Authorization (MVP)

Version: 1.0 (MVP)
Scope: Flutter Android/web app + FastAPI backend

1. Purpose
----------
This document defines the canonical authentication and authorization design for MVP. It aligns with `PROJECT_BIBLE.md`, `PRD.md`, `ARCHITECTURE.md`, `DATABASE.md`, and `API.md`.

MVP constraints:
- No Redis, no RabbitMQ, no background workers.
- No additional identity provider besides Google OAuth and email/password.
- Flutter web is available for the MVP production frontend.

2. Authentication Flows
-----------------------
2.1 Email/Password Registration
- Client submits name, email, password, and required Terms/Privacy acceptance.
- Backend validates payload and password policy.
- Backend creates user record with hashed password.
- Backend returns a verification-required response containing the email address and, in development only, a verification token for local testing.
- A normalized-email duplicate returns the same public response shape and creates no second user; clients must not reveal whether an arbitrary address already has an account.
- Account remains inactive for password login until email verification is completed.

2.2 Email/Password Login
- Client submits email and password.
- Backend looks up user by normalized email.
- Backend verifies password hash.
- Backend rejects unverified users with `EMAIL_NOT_VERIFIED`.
- Backend issues a short-lived JWT access token and a refresh/session token.
- Android stores credentials in platform secure storage; web uses localStorage
  with a memory fallback. Only the access token is attached to protected requests.

2.3 Email Verification
- Client submits verification token received through email delivery.
- Backend validates token signature, issuer, audience, expiration, and token type.
- Backend marks the matching user as `email_verified = true`.
- Verification tokens expire after 24 hours by default. Replay before expiry is idempotent and does not issue a session or change other account data; tokens are not strictly single-use.
- Development flow may expose the verification token in API responses for local testing; production must deliver the token by email provider only. Verification tokens are not logged.

2.4 Google OAuth Login
- The backend verifies signature, issuer, audience, applicable azp, expiry, iat,
  email, email_verified=true and a nonempty stable Google sub.
- A known sub signs in its original active user. A changed Google email never
  moves the subject or overwrites the stored Mushukistan email.
- For a new sub with no email collision, create one Google-only account after
  legal acceptance. Gmail/Googlemail and hosted Workspace email claims establish
  current email ownership; other Google emails remain locally unverified.
  Those Google-only users can still sign in by sub.
- For an email collision, lock and re-read the matching active user. Reject
  ambiguity, a different bound sub, or a changed stored email.
- An already verified Gmail/Googlemail account may bind automatically. These
  consumer addresses are treated as non-reassignable; do not canonicalize dots,
  plus aliases, or gmail.com/googlemail.com into a different email.
- A verified Workspace/custom-domain password account requires its current
  Mushukistan password in the same Google login request. The client asks once
  inside sign-in and reuses the token only in memory for that attempt. Every
  retry verifies the Google token again. Later Google sign-ins use sub directly.
- An unverified account is never automatically claimed, verified, or cleared by
  Google. Finish password login/email verification first, then retry Google.
  A person who did not create the pending account must contact support. This
  accepts a registration-squatting availability risk rather than data exposure.
  email_verified is a mailbox-status flag, not pending-registration provenance.
  The schema does not guarantee that unverified rows own no data; unverified
  bound Google accounts can already use the app. The flag cannot authorize reclaiming data.
- Passwordless legacy Gmail/Googlemail rows with verified email follow the same
  bounded Gmail rule. External legacy rows without a bound sub need support;
  current ownership of a reassigned address does not prove historical ownership.
- No user rows are merged, deleted, or moved. Password hashes remain unchanged.
- Legal acceptance is displayed beside the Google action; the backend retains
  current versions and a timestamp, and does not rewrite unchanged acceptance.
- Token/password material is never logged. Google rejections log only status
  and error code. Both login methods use the same sessions.

2.5 Logout
- Client calls `POST /auth/logout` with the current refresh token when available, then deletes local credentials.
- Backend revokes the matching refresh session only when it belongs to the authenticated user, or all active refresh sessions for that user when no token is provided.
- Access-token blacklist remains out of MVP scope.

3. JWT Strategy
---------------
3.1 Token Types
- Access token: Bearer JWT.
- Refresh/session token: opaque random token stored hashed server-side.

3.2 Signing
- Algorithm: HS256 for MVP simplicity.
- Signing secret stored in environment variable and never committed.
- Future: rotate to RS256 with key rotation when infra matures.

3.3 Required Claims
- `sub`: user UUID
- `exp`: expiration timestamp (UTC)
- `iat`: issued-at timestamp
- `nbf`: not-before timestamp
- `iss`: token issuer (backend service name)
- `aud`: token audience (`mushukistan-mobile`)
- `role`: `user` or `moderator`

3.4 Validation Rules
- Reject tokens with invalid signature.
- Reject expired tokens (`exp` in past).
- Reject tokens with invalid `iss` or `aud`.
- Reject tokens for deactivated users (`is_active = false`).

4. Token Lifetime
-----------------
- Access token lifetime: 60 minutes.
- Refresh/session lifetime: 30 days.
- Refresh uses sliding renewal and keeps the refresh token stable for MVP to avoid accidental sign-outs from stale tabs or clients.
- Clock skew tolerance: 60 seconds.
- Re-authentication is required only when the refresh/session token is expired, revoked, invalid, or the account is disabled/deleted.

Startup/session restore:
- public product UI renders independently of session restoration.
- valid access token -> restore the authenticated account without blocking public navigation.
- expired access token with valid refresh session -> silently refresh and persist renewed credentials.
- invalid/revoked/expired refresh session -> clear local auth state and continue as a guest.
- transient network/server failure during refresh -> keep public browsing available; protected actions can offer retry/sign-in.
- browsing public feed, map, public content details, places, leaderboards, and permitted public profiles does not require authentication.
- creating or changing content, liking, commenting, reporting, account routes, and moderation require authentication at the point of action.

5. Google OAuth Flow (Detailed)
-------------------------------
5.1 Client Steps
- User taps "Continue with Google".
- Flutter mobile or web obtains a Google ID token through its official Google Sign-In flow.
- Client sends `id_token` to `POST /api/v1/auth/google`.
- The app presents the linked notice "By continuing with Google, you agree to the Terms of Service and Privacy Policy" before the Google button and submits `accept_terms=true` and `accept_privacy=true` in the initial request. It does not retain a Google ID token for a legal-consent retry.
- Existing current-version acceptance is not recorded again. If legal versions change, clicking the linked agreement and continuing records the new current versions through the same server-side acceptance checks.

5.2 Backend Steps
Apply the verified-sub and collision rules in section 2.4 in a transaction.
Use unique normalized-email and Google-sub constraints, row locking, and one
bounded retry after an integrity violation. A locked read refreshes ORM state.

5.3 Error Handling
- Invalid token: 401 INVALID_GOOGLE_TOKEN; missing email: GOOGLE_EMAIL_MISSING.
- Missing legal acceptance: 422 LEGAL_ACCEPTANCE_REQUIRED.
- Disabled account: 403 ACCOUNT_DISABLED.
- Password proof needed: 409 GOOGLE_PASSWORD_REQUIRED, only after valid Google proof.
- Wrong confirmation password: 401 INVALID_CREDENTIALS; no binding/session.
- Pending email verification: 409 GOOGLE_ACCOUNT_UNVERIFIED; no mutation/session.
- Ambiguous, differently bound, or unrecoverable legacy match: GOOGLE_IDENTITY_CONFLICT.

6. User Roles and Permissions
-----------------------------
6.1 Roles (MVP)
- `user`: standard account.
- `moderator`: can process reports and remove violating content.

6.2 Permission Matrix
- `user` permissions:
  - create/update own profile;
  - create posts/cats/comments/likes;
  - delete own comments/posts;
  - report content.
- `moderator` permissions:
  - all user permissions;
  - view moderation queue;
  - resolve/dismiss reports;
  - soft-delete violating posts/comments;
  - suspend users (set `is_active = false`) if required.

6.3 Authorization Rules
- Ownership check for user-managed content.
- Role check for moderation endpoints.
- Return 403 `FORBIDDEN` when user lacks permission.
- Auth session responses and `GET /users/me` expose `is_moderator` so the client can show moderator navigation. This is a discoverability hint only; every moderation endpoint still enforces the server-side role check.

7. Password Hashing
-------------------
7.1 Algorithm
- Preferred: Argon2id.
- Acceptable fallback: bcrypt (cost factor >= 12).

7.2 Rules
- Never store plaintext password.
- Never log password or hash.
- Use constant-time compare via hashing library.
- Enforce max password length (128 chars) to prevent abuse.

7.3 Password Policy (MVP)
- Minimum length: 8
- Maximum length: 128
- No complexity hard-fail beyond length for MVP (to reduce registration friction), but UI should recommend strong passwords.

7.4 Account Security
- GET /auth/methods remains the small authenticated read used for has_password
  and email_verified. Its old google_connected field stays for response
  compatibility but is not displayed. Renaming this endpoint adds no value.
- POST /auth/change-password requires the current password and matching new
  password confirmation. Google-only users have no Password section.
- Add password and manual Google connection are removed from UI and backend.
  /auth/set-password and /auth/connect-google now return 404. Old clients must
  update for these actions and for inline collision confirmation.
- Google-only users continue using Google. No password recovery feature is
  claimed; a separate password reset design remains outside this change.
- legacy_google_unbound stays as historical schema metadata, is cleared on
  binding, and grants no authority. Removing the column would needlessly add a migration.
- Password changes retain the existing session policy. Account Security shows
  email verification, Change password when applicable, and Log out.

8. Account Lifecycle
--------------------
8.1 Creation
- Via email/password or Google OAuth.

8.2 Active State
- `is_active = true` means login allowed.
- `is_active = false` means authentication denied with 403 `ACCOUNT_DISABLED`.
- `email_verified = false` means password login is denied with 401 `EMAIL_NOT_VERIFIED`.
- Google email verification follows section 2.4; an external non-hosted claim alone does not establish current mailbox ownership.

8.3 Profile Updates
- User can update display name, bio, avatar URL.

8.4 Suspension (Moderator)
- Moderator can suspend account for abuse.
- Suspended users cannot authenticate or create content.

8.5 Deletion
- Account deletion is available from Settings -> About account -> Delete account.
- The backend anonymizes and deactivates the account instead of hard-deleting the `users` row.
- Login is disabled by setting `is_active = false`; existing access tokens are rejected on subsequent protected requests because the account is inactive.
- Authentication credentials and profile personal data are removed, including email address, password hash, name, avatar URL, phone number, Telegram username, bio, legal acceptance records, and last-login data. The Google `sub` remains on the inactive anonymized row as a tombstone so a deleted identity cannot silently create a replacement account.
- User-owned posts, comments, lost-pet posts, and adoption/rehoming posts are hidden and anonymized.
- User likes, user block rows, and affected leaderboard cache entries are removed.
- Shared domain records such as cats may remain when they no longer identify the deleted user; user attribution is cleared where possible.
- Some anonymized operational and moderation records may remain for service integrity, moderation, safety, abuse prevention, or legal compliance.

9. Security Controls Specific to Auth
-------------------------------------
- Rate limit auth endpoints (10 req/min per IP).
- Generic login error messages to avoid account enumeration.
- Use HTTPS in production only.
- Rotate JWT signing secret manually when needed.

10. API Alignment
-----------------
This document aligns to these endpoint families in `API.md`:
- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `POST /api/v1/auth/resend-verification`
- `POST /api/v1/auth/verify-email`
- `POST /api/v1/auth/google`
- `POST /api/v1/auth/logout`
- `GET /api/v1/auth/methods`
- `POST /api/v1/auth/change-password`

11. Out of Scope for MVP
------------------------
- Password reset via email
- MFA
- Access-token revocation blacklist (refresh-session revocation is implemented)
- Single sign-on beyond Google
- Production email delivery provider implementation details

12. Future Evolution (Post-MVP)
-------------------------------
- Add password reset flow.
- Add MFA for moderators.
- Add audit table for auth events.
- Move to asymmetric JWT signing and automated key rotation.

Change Log
----------
- 2026-07-23: Initial MVP auth architecture document.


Compatibility and session audit (2026-09-27)
--------------------------------------------
- Commit 0179a7b included set-password without Google reauthentication;
  7213afb added required id_token. Both use Android version 0.1.0+8.
  Git proves source history, not Play publication; distributed client state is unknown.
- No schema/configuration/OAuth changes. Deployment requires existing migrations
  20260924_0020 and 20260926_0021; the latter refuses legacy email duplicates.
- Access JWT defaults to 60 minutes plus 60 seconds skew. Refresh tokens use
  secrets.token_urlsafe(48), SHA-256 storage and 30-day sliding expiry. They
  remain stable; the repository method named rotate_refresh_session renews them.
- Logout revokes the supplied owned refresh session; no token means all user
  refresh sessions. Already issued access JWTs survive logout until expiry.
- Inactive users fail login, refresh and protected requests. Revocation attempted
  while rejecting inactive refresh originally rolled back with the exception;
  rejection alone did not persist revocation. The rejection now occurs after
  the revocation transaction commits, preventing refresh revival on reactivation.
- Web localStorage exposes tokens to same-origin script/XSS. Cookie-based web
  session storage is a separate session-hardening design, not changed here.
- Separate follow-up: refresh rotation/reuse detection and absolute lifetime,
  password-change session revocation, and access-token immediate revocation.
- Google key fetching currently caches keys for the process lifetime; key-cache
  expiry/refresh is a separate reliability follow-up. Real OAuth must be checked.
- Reference: https://developers.google.com/identity/gsi/web/guides/verify-google-id-token
  explains stable sub and why non-hosted email_verified does not prove current ownership.
