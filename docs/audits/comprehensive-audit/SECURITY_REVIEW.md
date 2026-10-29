# Security Review (updated after phase 2)

Scope: defensive, local-only. No production access. No secrets were read or reproduced; the repo's root `.env` was not opened. All dynamic testing used a disposable database and an isolated backend.

## Findings (details in TECHNICAL_FINDINGS.md)
| ID | Sev | Summary | Status |
|----|-----|---------|--------|
| F-01 | P1 | Blocking has no effect on feed, comments, likes, notifications or owner contact | Confirmed |
| F-02 | P2 | Rate limits bypassed by random Bearer tokens (0/200 limited) | Confirmed; downgraded from P1 after measuring reach |
| F-03 | P2 | Limiter memory grows without bound; counters per process | Confirmed |
| F-12 | P2 | `APP_ENV` defaults to `development`; dev mode returns email-verification tokens in the API response | Confirmed |
| F-13 | P2 | Anonymous clients can read owner phone numbers; scraping is throttle-free via F-02 | Confirmed (documented design) |
| F-14 | P2 | Any user can rename/relocate any cat and set an arbitrary external cover URL | Confirmed (documented MVP) |
| F-19 | P3 | Refresh tokens never rotate; replay works; no absolute lifetime | Confirmed (documented) |
| F-08 | P3 | Tokens in web localStorage | Confirmed |
| F-09 | P3 | No nginx-level throttling | Config-confirmed |
| F-20 | P3 | python-jose / cryptography / ecdsa advisories | Scanned; not exploitable as configured |
| F-07 | P3 | Media cleanup on account deletion is best-effort | Code-confirmed |
| F-25 | P3 | Zero-photo lost-pet row crashes reads (availability) | Confirmed with seeded row |

## Authorization (executed)
See AUTHORIZATION_MATRIX.md for all 81 routes.
- Authentication: all 53 protected routes return 401 without a token (`test_unauthenticated_sweep`).
- Ownership/IDOR: another user cannot edit, delete or resolve posts, comments, lost pets or adoption posts (403); notifications of another user return 404; moderation endpoints return 403 to normal users and 200 to a moderator.
- Role escalation: a non-moderator cannot set cat `status` or `merged_into` (403).
- Privacy: the public profile omits email, phone, telegram and moderator flag; `allow_public_activity_view=false` blocks other users from the owner's posts/comments (403).
- Account state: disabled-account token -> 403; deleted-account token -> 403 for both profile reads and writes (like).
- Tokens: garbage and tampered JWTs -> 401.
- **Gaps:** F-01 (blocking), F-14 (cats), F-13 (public phones). Contact-owner endpoints are also reachable by a blocked user (204).
- **Not covered:** `follow-ups/*/answer`, device registration/unregistration across users, `reports` handling by moderators beyond the 403 check, comment/notification interplay with deleted accounts, and media URL access control. R2 bucket permissions were not examined; in local mode `/media` serves all stored files without auth, by design.

## Injection, XSS, uploads
- SQL access is through SQLAlchemy; no raw string-built queries were seen in the paths I read (not a full audit of every repository).
- The web client renders to a canvas, so classic stored XSS has little surface; the CSP forbids inline scripts. Landing-site (`website/`) rendering of user content was not reviewed.
- Uploads: text, GIF, SVG, empty and mislabelled files rejected; 36 MP rejected by the pixel cap; 6th image rejected; a JPEG with trailing HTML accepted (server re-encodes; stored bytes not inspected).
- `cover_photo_url` and post `photo_url` accept arbitrary `http(s)` URLs (F-14); they are only fetched by clients, so no SSRF, but they enable tracking pixels and off-platform content.

## Authentication
- JWT: HS256, issuer/audience/iat checked, algorithms pinned. Email verification and registration were exercised; registering one email 10 times in parallel created one user (no enumeration difference in the response).
- F-12 is the main hazard: a misconfigured production environment would silently run in dev mode.
- Google OAuth not exercised.

## Transport and exposure (config review)
- nginx: TLS 1.2+, HSTS, nosniff, frame-deny, CSP, `Referrer-Policy`. Prod compose removes the backend host port and disables Swagger. The default (dev) compose publishes `127.0.0.1:8300` and nginx on port 80.
- CORS: explicit allow-list in production; localhost regex in dev. `allow_credentials=False`.

## Dependencies (scanned with pip-audit)
See F-20. No Flutter/pub advisory scan was possible.

## Privacy
- Location is only uploaded after an explicit "Use current location?" dialog (observed). Nearby-alert location handling is documented in `docs/ARCHITECTURE.md` and was not runtime-tested (Android).
- Account deletion anonymises the row and removes avatars/photos best-effort (F-07); UI flow not executed.
- The "Welcome" onboarding dialog shows the author's personal card number to every user. A product choice, not a vulnerability.

## Remaining unverified security items
Google sign-in token validation, Firebase service-account handling, R2 permissions, production environment values, per-endpoint authorization for the untested routes above, and Android storage (flutter_secure_storage) behaviour.
