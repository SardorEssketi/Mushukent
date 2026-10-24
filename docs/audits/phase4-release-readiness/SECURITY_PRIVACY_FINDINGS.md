# Remaining security and privacy findings (after Phase 4)

Legend: **Fixed** = changed and tested on branches `fix/user-blocking`, `fix/security-hardening`, `fix/reliability-ci`, `fix/release-readiness`. **Open** = confirmed, not fixed. **Decision** = needs a product/owner decision.

## Resolved in the four remediation branches
| Audit ID | Issue | Status | Evidence |
|---|---|---|---|
| F-01 | Blocking not enforced | Fixed | 26 backend tests, 30 browser checks |
| F-02/F-03 | Rate-limit bypass with random tokens, unbounded limiter memory | Fixed (single process) | 55 tests, live smoke (12 random-token requests: 4 allowed, 8 limited) |
| F-12 | `APP_ENV` default exposed verification tokens | Fixed | env and registration tests |
| F-05 | App would not start without PostHog | Fixed | 17 analytics tests, CI-like run without PostHog |
| F-16 | Outage looked like logout | Fixed | 40+ Flutter tests, 24-25/25 browser checks per viewport |
| F-04 | CI had no tests and failing Black | Fixed (unrun on GitHub) | local equivalents; two more CI defects found and fixed in this phase |
| F-13 | Anonymous access to owner phone numbers | **Fixed for anonymous/list/feed; Decision remains** | `docs/CONTACT_PRIVACY.md`, 7 backend + 4 Flutter tests, live API check |
| F-14 | Any user can edit any cat | Fixed | `docs/CAT_EDITING.md`, 8 backend tests; audit correction (PATCH never stored the URL) |

## Open findings
| # | Sev | Finding | Notes |
|---|---|---|---|
| S-1 | P2 | **Signed-in users can still read owner phone numbers** (one post at a time) | Bounded by per-user rate limit and verified email; stronger options listed in CONTACT_PRIVACY.md (Decision) |
| S-2 | P2 | **Adoption posts publish a phone number without an explicit consent step** | Matches `docs/PRD.md` today (Decision) |
| S-3 | P3 | `POST /posts` JSON mode accepts an arbitrary external `photo_url` | Same hotlinking concern as the cat cover URL; clients use multipart so it is API-only. Not changed (Decision) |
| S-4 | P3 | `python-jose` 3.5.0 (CVE-2026-85394, unmaintained, no fix) | Not exploitable as configured (HS256 pinned, symmetric key). Migrating to PyJWT is recommended but touches token issuing/verification, so it was **not** done in a release-prep phase |
| S-5 | P3 | `cryptography` 49.0.0 (PYSEC-2026-3552, fix 50.0.0) held back by the `<50.0.0` pin | Affects PKCS7 decryption, which the code does not use. Lifting the pin needs a dedicated compatibility run |
| S-6 | P3 | Refresh tokens do not rotate; web stores tokens in `localStorage` | Documented MVP choices (docs/AUTH.md) |
| S-7 | P3 | No nginx `limit_req`; per-process in-memory rate limits | Exact with one uvicorn process (current deployment); needs a shared store before scaling out |
| S-8 | P3 | No scheduled database backups documented; no Flutter crash reporting | Operational (see deployment sequence) |
| S-9 | P3 | Zero-photo lost-pet/adoption row makes reads fail (500) | Hardening; no API path found that creates one |
| S-10 | P3 | Production `.env` unverified | Phase 2/3 made `RATE_LIMIT_ENABLED=false`, `APP_DEBUG=true` and a missing/invalid `APP_ENV` fail startup. I did not read the real `.env` |

## Verified in this phase
- Anonymous detail and list endpoints return no phone or Telegram, only `contact_available`; a signed-in non-owner receives the number on the detail endpoint only; the owner keeps it for the edit form; `POST .../contact` still works (and requires sign-in).
- Non-owner cat PATCH returns 403 on a live isolated backend; moderator and creator succeed; look-alike storage hosts are rejected.
- `flutter analyze`, ruff and black clean.

## Not tested
Google sign-in, FCM/push delivery, R2 storage permissions, production configuration, Android secure storage, load behaviour.
