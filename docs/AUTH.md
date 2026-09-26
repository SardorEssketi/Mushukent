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
- Client submits email, password, optional display name.
- Backend validates payload and password policy.
- Backend creates user record with hashed password.
- Backend returns a verification-required response containing the email address and, in development only, a verification token for local testing.
- Account remains inactive for password login until email verification is completed.

2.2 Email/Password Login
- Client submits email and password.
- Backend looks up user by normalized email.
- Backend verifies password hash.
- Backend rejects unverified users with `EMAIL_NOT_VERIFIED`.
- Backend issues a short-lived JWT access token and a refresh/session token.
- Client stores both credentials using secure storage and attaches only the access token to protected requests.

2.3 Email Verification
- Client submits verification token received through email delivery.
- Backend validates token signature, issuer, audience, expiration, and token type.
- Backend marks the matching user as `email_verified = true`.
- Verification tokens expire after 24 hours by default. Replay before expiry is idempotent and does not issue a session or change other account data; tokens are not strictly single-use.
- Development flow may expose the verification token in API responses for local testing; production must deliver the token by email provider only. Verification tokens are not logged.

2.4 Google OAuth Login
- Client obtains Google `id_token` using official Google Sign-In SDK.
- Client sends `id_token` to backend.
- Backend validates the token signature, issuer (`iss`), configured audience (`aud`), authorized party (`azp`) when applicable, expiration (`exp`), issued-at (`iat`), email, `email_verified`, and stable `sub`.
- Backend looks up an existing Google identity by `sub` first. Email is not the permanent identity key.
- With a new `sub`, automatic email matching is allowed only for exactly one active Mushukistan account whose email is already verified and exactly matches the verified consumer Gmail address. Google's signed, authoritative Gmail claim proves control of the address, and Mushukistan's existing verified-email state protects the target password account. Password hash and user data remain on that same row.
- Same-email Workspace and other external-domain accounts are never automatically linked by email, even when Google reports a verified email. Those addresses may be reassigned; the user must sign in to Mushukistan and connect Google from Account Security. Unverified password accounts are also never auto-linked.
- An already-linked subject continues to sign into its original Mushukistan user if the Google email changes. The Mushukistan email and verification state are not changed by a different provider email.
- New Google users get Mushukistan `email_verified = true` only for an authoritative Gmail or verified hosted-domain claim. Other provider-verified addresses can authenticate by `sub` while Mushukistan password login still requires Mushukistan email verification.
- Multiple normalized email matches, an inactive matching account, or a subject already attached elsewhere fail closed. Separate user rows are never merged based on email.
- Google login and password login issue the same Mushukistan access and refresh session types.
- A new Google user is created with `password_hash = NULL` only after explicit Terms and Privacy acceptance.
- Backend issues a short-lived JWT access token and a refresh/session token.
- Google login rejections log only provider, status, and error code; raw credentials and claims are not logged.

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
- If the backend returns `LEGAL_ACCEPTANCE_REQUIRED`, the app shows explicit Terms of Service and Privacy Policy consent controls and resubmits the same Google ID token with `accept_terms=true` and `accept_privacy=true`.
- The client must not silently accept legal documents or require the user to choose their Google account twice.

5.2 Backend Steps
- Verify token with Google public keys.
- Validate:
  - `iss` is Google issuer,
  - `aud` matches a configured Google OAuth client ID and `azp` is valid when applicable,
  - token is not expired and `iat` is not in the future,
  - `email_verified` is true,
  - email and stable `sub` exist in token payload.
- Find or create user:
  - for new users, require `accept_terms=true` and `accept_privacy=true`;
  - record current Terms and Privacy versions and a backend-owned acceptance timestamp when legal acceptance is provided;
  - set Mushukistan `email_verified = true` only when the Google email claim is authoritative (consumer Gmail or `email_verified=true` with a hosted-domain claim);
  - update `last_login_at`.
- Require a non-empty Google `sub`; store it uniquely on the existing user row.
- For an already connected subject, keep the account's Mushukistan email unchanged if the Google email later changes.
- Issue local JWT access token.

5.3 Error Handling
- Invalid token -> 401 `INVALID_GOOGLE_TOKEN`.
- Missing email claim -> 400 `GOOGLE_EMAIL_MISSING`.
- Missing required legal acceptance -> 422 `LEGAL_ACCEPTANCE_REQUIRED`.
- Disabled user -> 403 `ACCOUNT_DISABLED`.
- Unsafe/ambiguous email match or identity already linked elsewhere -> 409; never merge users automatically.

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
- Authenticated `GET /auth/methods` returns `has_password`, `google_connected`, and `email_verified`; it returns no provider subject or credential material.
- Authenticated `POST /auth/set-password` is allowed only while `password_hash` is null. It requires a fresh server-verified Google ID token matching the account email and any already linked subject, plus a matching confirmation, then stores an Argon2 hash on the same user row.
- Authenticated `POST /auth/change-password` requires the current password and a matching new-password confirmation.
- Authenticated `POST /auth/connect-google` verifies the Google ID token and requires its verified email to match the signed-in Mushukistan account. A Google subject already attached to another account is rejected.
- Credential mutations retain existing access and refresh sessions under the MVP session policy. There is no unlink or password-removal operation, so Google-only users cannot remove their only method.
- Eligible legacy consumer Gmail accounts are marked as unbound by migration until the next verified Google sign-in. Setting a password requires Google reauthentication and records its stable subject, clearing the legacy marker. External-domain legacy accounts require authenticated or support-assisted linking because their email address may be reassigned.

8. Account Lifecycle
--------------------
8.1 Creation
- Via email/password or Google OAuth.

8.2 Active State
- `is_active = true` means login allowed.
- `is_active = false` means authentication denied with 403 `ACCOUNT_DISABLED`.
- `email_verified = false` means password login is denied with 401 `EMAIL_NOT_VERIFIED`.
- Google email verification follows the trusted-claim rules in section 5.2. Login by an already linked Google `sub` remains available even when Mushukistan does not trust that email for password login.

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
- `POST /api/v1/auth/set-password`
- `POST /api/v1/auth/change-password`
- `POST /api/v1/auth/connect-google`

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

