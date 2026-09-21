SECURITY.md

Mushukistan Security Architecture (MVP)

Version: 1.0 (MVP)
Scope: Android app + FastAPI backend + PostgreSQL/PostGIS + Cloudflare R2

1. Purpose
----------
This document defines security principles and controls for Mushukistan MVP. It is implementation guidance for secure-by-default behavior while keeping MVP delivery practical.

2. Security Principles
----------------------
- Least privilege: every user/service gets minimum required permissions.
- Deny by default: protected endpoints require explicit auth/authorization.
- Validate all input server-side; never trust client-side checks.
- Fail safely: return controlled errors, never raw stack traces.
- Keep secrets out of source code and logs.
- Prefer simple, auditable controls over complex unverified designs in MVP.

3. Input Validation
-------------------
3.1 General
- All request payloads validated with strict Pydantic schemas.
- Reject unknown fields where appropriate.
- Enforce type checks, length bounds, enum constraints, and coordinate bounds.

3.2 Field-Level MVP Baselines
- UUID fields must be valid UUIDv4.
- Email max 254 chars and valid format.
- Password length 8-128.
- Text fields:
  - comment content max 1000,
  - post description max 2000,
  - display name max 100.
- Coordinates:
  - latitude in [-90, 90],
  - longitude in [-180, 180].

3.3 Response Errors for Validation
- Return 422 `VALIDATION_ERROR` with structured `details` map.
- Never expose internal schema paths that leak implementation details unnecessarily.

4. Authorization
----------------
4.1 Authentication Enforcement
- JWT Bearer required for protected endpoints.
- Token validation checks signature, exp, iat/nbf, iss, aud.

4.2 Role-Based Access Control (RBAC)
- Roles: `user`, `moderator`.
- Moderator-only routes under moderation namespace.

4.3 Ownership Checks
- Users may modify/delete only their own content unless moderator.
- Unauthorized ownership action -> 403 `FORBIDDEN`.

4.4 Account Status Checks
- Disabled users (`is_active = false`) cannot authenticate or mutate data.

5. Rate Limiting
----------------
MVP baseline limits:
- Anonymous endpoints: 30 req/min per IP.
- Public read endpoints used for Feed, Map, places, lost pets and leaderboards: 180 req/min per IP or authenticated token.
- Authenticated endpoints: 60 req/min per user.
- Auth endpoints and upload endpoints: 10 req/min per IP/user.
- CORS preflight requests are not counted against user-facing request buckets.

Behavior:
- Exceeding limits returns 429 `RATE_LIMIT_EXCEEDED`.
- Include `Retry-After` header.

Notes:
- Implementation can use in-process limiter for MVP.
- External distributed limiter (Redis) is out of MVP scope.
- Current MVP implementation uses an in-process fixed-window limiter. This is sufficient for a single backend process and should be replaced with a shared Redis-backed limiter before horizontal scaling.
- The limiter is split into rate-limit policy and storage. `RATE_LIMIT_BACKEND=memory` is active now; `RATE_LIMIT_BACKEND=redis` and `RATE_LIMIT_REDIS_URL` are reserved for a future Redis-backed store so route behavior and response envelopes do not need to change.

6. File Upload Security
-----------------------
6.1 Allowed Types
- `image/jpeg`, `image/png` only.

6.2 Size Limits
- Max upload size: 10 MB per image.

6.3 Validation Controls
- Validate MIME type and magic bytes.
- Reject malformed/corrupt files.
- Strip EXIF metadata before long-term storage to reduce privacy leakage.
- Normalize image orientation and re-encode output.

6.4 Storage Controls
- Store files in Cloudflare R2 private bucket policy suitable for app usage.
- Save only generated canonical URLs in DB.
- Never trust user-provided path names.

7. Secrets Management
---------------------
7.1 Required Secrets
- JWT signing secret
- Database credentials
- Google OAuth client configuration
- Cloudflare R2 access key and secret key
- Resend API key for transactional email delivery

7.2 Rules
- Secrets must come from environment variables.
- Never hardcode secrets in source files or docs examples.
- Never print secrets in logs.
- Use separate secrets per environment (dev/staging/prod).

7.3 Rotation
- Manual secret rotation process for MVP:
  - update environment values,
  - restart services,
  - verify health and auth behavior.

8. Logging and Auditing
-----------------------
8.1 Log What Matters
- Authentication success/failure (without credentials).
- Authorization failures.
- Upload validation failures.
- Moderation actions.
- Unhandled exceptions.

8.2 Sensitive Data Redaction
- Never log passwords, token values, or full secret material.
- Avoid logging full personal payloads when not needed.

8.3 Audit Expectations (MVP)
- At minimum, moderation actions should be traceable by user id and timestamp.
- Full immutable audit event store is post-MVP.

9. Security Headers
-------------------
Set headers at reverse proxy and/or app layer:
- `Strict-Transport-Security: max-age=31536000; includeSubDomains`
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: no-referrer`
- `Content-Security-Policy` for API responses as applicable (minimal strict policy)

Notes:
- APIs typically return JSON; still enforce `nosniff` and HSTS.
- CORS should allow only trusted app origins/channels where applicable.

10. OWASP Considerations (MVP Mapping)
--------------------------------------
- A01 Broken Access Control:
  - enforce RBAC + ownership checks server-side.
- A02 Cryptographic Failures:
  - HTTPS only, secure password hashing, signed JWT.
- A03 Injection:
  - ORM parameterization, strict validation, no raw SQL with unsanitized input.
- A04 Insecure Design:
  - canonical docs-first design and review before implementation.
- A05 Security Misconfiguration:
  - hardened defaults, no debug mode in production.
- A06 Vulnerable Components:
  - pin and regularly update dependencies.
- A07 Identification and Authentication Failures:
  - strong token validation, rate-limited login.
- A08 Software and Data Integrity Failures:
  - controlled CI/CD and image provenance checks where possible.
- A09 Security Logging and Monitoring Failures:
  - structured logs for key security events.
- A10 SSRF:
  - do not fetch arbitrary remote URLs from user input in MVP flows.

11. Incident Handling (MVP)
---------------------------
- Detect: error spikes, auth failure spikes, suspicious moderation reports.
- Respond: temporarily tighten rate limits, disable abused endpoints if needed.
- Recover: rotate compromised secrets, patch vulnerable dependency, redeploy.
- Review: document incident and add preventive controls.

12. Out of Scope for MVP
------------------------
- WAF tuning program
- Advanced SIEM pipeline
- Distributed rate limit via Redis
- Hardware security module integration
- Formal penetration test report

13. Security Checklist Before Production
----------------------------------------
- HTTPS enforced end-to-end.
- All protected endpoints require JWT.
- Auth and upload rate limits active.
- Password hashing verified.
- Secret values loaded from environment.
- EXIF stripping enabled in image pipeline.
- Moderation actions logged.
- Debug mode disabled.

Change Log
----------
- 2026-07-23: Initial MVP security architecture document.

