# Production configuration preflight (read-only checklist)

I did **not** connect to production, read the production `.env`, or open any secret file. Each item is something the operator checks and ticks. Never paste values into chat or logs; check only "set / not set / matches".

How the code enforces it: with `APP_ENV` production-like, `Settings.validate_production_settings` (`backend/app/core/config.py`) refuses to start on the errors below, so a **successful start with `APP_ENV=production` already proves** items 2-9 pass.

| # | Item | Expected | How to check without exposing secrets |
|---|---|---|---|
| 1 | `APP_ENV` | exactly `production` (a missing or unknown value fails startup) | `docker compose exec backend printenv APP_ENV` |
| 2 | `APP_DEBUG` | `false` | startup validation; also `GET /docs` must be unavailable if disabled in prod |
| 3 | `RATE_LIMIT_ENABLED` | `true` (startup refuses `false`); `RATE_LIMIT_BACKEND=memory` is correct only with ONE worker | `printenv` the name only |
| 4 | JWT | `JWT_ALGORITHM` in HS256/384/512; `JWT_SECRET_KEY` at least 32 chars and not a placeholder; different from dev | startup validation; compare lengths, never values |
| 5 | PostHog | optional; if used, key and host set, `POSTHOG_REQUIRED` unset unless you want startup to fail without it | start without it once in staging |
| 6 | Nginx proxy headers | `X-Forwarded-For $proxy_add_x_forwarded_for` and `X-Forwarded-Proto https` set on API locations (confirmed in `infrastructure/nginx/default.conf`); backend `TRUSTED_PROXY_CIDRS` must contain the nginx/docker-network address, and if Cloudflare is in front, client IP handling must be tested | send two requests with different spoofed `X-Forwarded-For` from outside: the limiter must NOT treat them as different clients |
| 7 | Backend workers | exactly 1 (`Dockerfile` runs `uvicorn` without `--workers`); more than one makes in-memory limits per-process | `docker compose exec backend ps` |
| 8 | Cloudflare R2 | account id, access key id, secret and `R2_PUBLIC_BASE_URL` all set (startup requires them); bucket public-read only for the media prefix; upload test passes | upload a test photo from staging |
| 9 | Firebase | credentials file, project id and `PUSH_TOKEN_ENCRYPTION_KEY` either all set or all unset; file is mounted read-only and not in git; project matches the app's `google-services.json` | startup validation |
| 10 | Other required | `CORS_ALLOWED_ORIGINS`, `PUBLIC_APP_BASE_URL`, `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `GOOGLE_OAUTH_CLIENT_ID`, non-default `POSTGRES_PASSWORD` | startup validation |
| 11 | Database backup | a backup made right before the release, restore tested into a scratch database, backup stored off the server; schedule exists | `pg_dump` + restore rehearsal; record time and size |
| 12 | Migrations | this series adds none; confirm `alembic current` equals `alembic heads` after deploy | one-line command |
| 13 | Rollback readiness | previous backend image tag and web build kept; previous Android release retained; rollback needs no DB change; list of commands written down | dry run in staging |
| 14 | Monitoring | health endpoint, 5xx and 429 rates, login failure rate, disk space on the host and volume holding media/db | dashboards |
| 15 | Post-deploy smoke | anonymous list has no phone; signed-in detail does; blocked users hidden; cat PATCH by non-owner is 403; register/verify email works | script in `docs/audits/phase4-release-readiness/` |

Open operational gaps (not code): no documented backup schedule, no crash reporting in the Flutter client, no dependency-vulnerability scan in CI.
