AUTH.md

Mushukent Authentication and Authorization (MVP)

Version: 1.0 (MVP)
Scope: Android app + FastAPI backend only

1. Purpose
----------
This document defines the canonical authentication and authorization design for MVP. It aligns with `PROJECT_BIBLE.md`, `PRD.md`, `ARCHITECTURE.md`, `DATABASE.md`, and `API.md`.

MVP constraints:
- No Redis, no RabbitMQ, no background workers.
- No additional identity provider besides Google OAuth and email/password.
- No web app in MVP.

2. Authentication Flows
-----------------------
2.1 Email/Password Registration
- Client submits email, password, optional display name.
- Backend validates payload and password policy.
- Backend creates user record with hashed password.
- Backend returns success response with user profile.
- For MVP, account can be active immediately (email verification optional and non-blocking).

2.2 Email/Password Login
- Client submits email and password.
- Backend looks up user by normalized email.
- Backend verifies password hash.
- Backend issues JWT access token.
- Client stores token securely and attaches it to protected requests.

2.3 Google OAuth Login
- Client obtains Google `id_token` using official Google Sign-In SDK.
- Client sends `id_token` to backend.
- Backend validates token signature, issuer (`iss`), audience (`aud`), and expiration (`exp`).
- Backend finds user by email:
  - if exists, log user in;
  - if not exists, create user with `password_hash = NULL`.
- Backend issues JWT access token.

2.4 Logout
- MVP logout is client-side token deletion.
- Backend `POST /auth/logout` may return 204 for consistency.
- Server-side token revocation/blacklist is out of MVP scope.

3. JWT Strategy
---------------
3.1 Token Type
- Access token only (Bearer JWT).
- Refresh token not used in MVP.

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
- `aud`: token audience (`mushukent-mobile`)
- `role`: `user` or `moderator`

3.4 Validation Rules
- Reject tokens with invalid signature.
- Reject expired tokens (`exp` in past).
- Reject tokens with invalid `iss` or `aud`.
- Reject tokens for deactivated users (`is_active = false`).

4. Token Lifetime
-----------------
MVP policy:
- Access token lifetime: 60 minutes.
- Clock skew tolerance: 60 seconds.
- Re-authentication required after expiration.

Rationale:
- Keeps implementation simple (no refresh-token lifecycle).
- Acceptable UX for MVP while reducing long-lived token risk.

5. Google OAuth Flow (Detailed)
-------------------------------
5.1 Client Steps
- User taps "Continue with Google".
- Android app obtains Google ID token.
- App sends `id_token` to `POST /api/v1/auth/google`.

5.2 Backend Steps
- Verify token with Google public keys.
- Validate:
  - `iss` is Google issuer,
  - `aud` matches configured client ID,
  - token not expired,
  - email exists in token payload.
- Upsert user:
  - set `email_verified = true` (for Google-authenticated emails),
  - update `last_login_at`.
- Issue local JWT access token.

5.3 Error Handling
- Invalid token -> 401 `INVALID_GOOGLE_TOKEN`.
- Missing email claim -> 400 `GOOGLE_EMAIL_MISSING`.
- Disabled user -> 403 `ACCOUNT_DISABLED`.

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

8. Account Lifecycle
--------------------
8.1 Creation
- Via email/password or Google OAuth.

8.2 Active State
- `is_active = true` means login allowed.
- `is_active = false` means authentication denied with 403 `ACCOUNT_DISABLED`.

8.3 Profile Updates
- User can update display name, bio, avatar URL.

8.4 Suspension (Moderator)
- Moderator can suspend account for abuse.
- Suspended users cannot authenticate or create content.

8.5 Deletion
- MVP behavior: soft-deactivate account (set `is_active = false`) and keep content for moderation/audit continuity.
- Hard-delete/anonymization workflow is post-MVP policy work.

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
- `POST /api/v1/auth/google`
- `POST /api/v1/auth/logout`

11. Out of Scope for MVP
------------------------
- Refresh tokens
- Password reset via email
- MFA
- Token revocation blacklist
- Single sign-on beyond Google

12. Future Evolution (Post-MVP)
-------------------------------
- Add refresh token flow with rotation.
- Add password reset flow.
- Add MFA for moderators.
- Add audit table for auth events.
- Move to asymmetric JWT signing and automated key rotation.

Change Log
----------
- 2026-07-23: Initial MVP auth architecture document.

