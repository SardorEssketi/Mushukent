# Infrastructure Skeleton

This directory contains MVP infrastructure configuration.

## Included
- `docker-compose.yml` at repository root
- PostgreSQL + PostGIS service
- FastAPI backend service
- Nginx reverse proxy
- `.env.example` for environment configuration

## Out of scope (MVP)
- Redis
- RabbitMQ
- Background workers
- Monitoring stack (Prometheus/Grafana/ELK)
- AI services

## Quick start
```powershell
Copy-Item .env.example .env
docker compose up --build
```

## Production deployment
1. Set real production values in `.env`.
2. Build the Flutter web bundle with the production API origin:
   ```powershell
   cd frontend
   flutter build web --release --dart-define=MUSHUKISTAN_API_BASE_URL=https://your-domain.example
   ```
3. Start the production Compose overlay:
   ```powershell
   cd ..
   docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
   ```

Required production settings:
- `APP_ENV=production`
- `APP_DEBUG=false`
- `ENABLE_API_DOCS=false`
- `CORS_ALLOWED_ORIGINS=https://your-domain.example`
- strong `JWT_SECRET_KEY`
- non-default `POSTGRES_PASSWORD`
- `PUBLIC_APP_BASE_URL=https://your-domain.example`
- Resend HTTP API settings: `RESEND_API_KEY` and
  `RESEND_FROM_EMAIL=noreply@mushukistan.uz` or another verified sender
- complete Cloudflare R2 settings: `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`,
  `R2_SECRET_ACCESS_KEY`, `R2_BUCKET`, and optionally `R2_PUBLIC_BASE_URL`
- `GOOGLE_OAUTH_CLIENT_ID` when Google sign-in is enabled

### Production environment variables
| Variable | Required | Secret | Value to provide | Where to get it |
| --- | --- | --- | --- | --- |
| `APP_NAME` | No | No | Public service name, normally `Mushukistan API`. | Project choice. |
| `APP_ENV` | Yes | No | `production` on the VPS. | Deployment environment. |
| `APP_DEBUG` | Yes | No | `false`. | Deployment policy. |
| `ENABLE_API_DOCS` | No | No | `false` unless temporarily exposing docs on a private host. | Deployment policy. |
| `API_PREFIX` | Yes | No | `/api/v1`. | Project API contract. |
| `CORS_ALLOWED_ORIGINS` | Yes | No | Comma-separated HTTPS frontend origins, for example `https://example.com,https://www.example.com`. | Production domain list. |
| `POSTGRES_DB` | Yes | No | Production database name. | VPS/database provisioning. |
| `POSTGRES_USER` | Yes | No | Production database user. | VPS/database provisioning. |
| `POSTGRES_PASSWORD` | Yes | Yes | Strong production database password. | Password manager / server secret store. |
| `DATABASE_URL` | Optional in Compose | Yes | Full SQLAlchemy database URL for non-Compose runs. Compose builds this from the Postgres variables. | VPS/database provisioning. |
| `JWT_SECRET_KEY` | Yes | Yes | Random 32+ character signing secret. | Password manager / secret generator. |
| `JWT_ALGORITHM` | Yes | No | `HS256` unless deliberately changed with code review. | Project auth configuration. |
| `JWT_ACCESS_TOKEN_EXP_MINUTES` | Yes | No | Access token lifetime, currently `60`. | Security policy. |
| `JWT_CLOCK_SKEW_SECONDS` | Yes | No | Clock skew allowance, currently `60`. | Security policy. |
| `JWT_ISSUER` | Yes | No | `mushukistan-api`. | Project auth configuration. |
| `JWT_AUDIENCE` | Yes | No | `mushukistan-mobile`. | Project auth/client configuration. |
| `EMAIL_VERIFICATION_TOKEN_EXP_HOURS` | Yes | No | Verification token lifetime, currently `24`. | Security policy. |
| `PUBLIC_APP_BASE_URL` | Yes | No | Public HTTPS app origin used in email links. | Production domain. |
| `RESEND_API_KEY` | Yes | Yes | Resend API key used by the HTTP Email API. | Resend dashboard. |
| `RESEND_FROM_EMAIL` | Yes | No | Verified sender address, normally `noreply@mushukistan.uz`. | Resend verified domain. |
| `RATE_LIMIT_ENABLED` | Yes | No | `true`. | Security policy. |
| `RATE_LIMIT_AUTH_PER_MINUTE` | Yes | No | Auth endpoint limit, currently `10`. | Security policy. |
| `RATE_LIMIT_ANON_PER_MINUTE` | Yes | No | Anonymous default limit, currently `30`. | Security policy. |
| `RATE_LIMIT_PUBLIC_READ_PER_MINUTE` | Yes | No | Public read limit, currently `180`. | Security policy. |
| `RATE_LIMIT_USER_PER_MINUTE` | Yes | No | Authenticated user limit, currently `60`. | Security policy. |
| `RATE_LIMIT_UPLOAD_PER_MINUTE` | Yes | No | Upload limit, currently `10`. | Security policy. |
| `RATE_LIMIT_BACKEND` | Yes | No | `memory` for single-node MVP. | Deployment architecture. |
| `RATE_LIMIT_REDIS_URL` | No | Yes | Leave blank until Redis-backed limiter exists. | Future Redis provisioning. |
| `GOOGLE_OAUTH_CLIENT_ID` | Required if Google sign-in is enabled | No | OAuth client ID accepted by backend. | Google Cloud Console. |
| `R2_ACCOUNT_ID` | Yes | No | Cloudflare account ID. | Cloudflare dashboard. |
| `R2_ACCESS_KEY_ID` | Yes | Yes | R2 access key ID. | Cloudflare R2 API token. |
| `R2_SECRET_ACCESS_KEY` | Yes | Yes | R2 secret access key. | Cloudflare R2 API token. |
| `R2_BUCKET` | Yes | No | Production media bucket name. | Cloudflare R2 bucket. |
| `R2_PUBLIC_BASE_URL` | Recommended | No | Public media domain/base URL. | Cloudflare R2 custom domain or public URL. |
| `MEDIA_STORAGE_ROOT` | No for production | No | Local media root. Compose sets `/app/.data/media`; production should use R2. | Local/dev only. |

### Android release signing
Release builds must not use debug signing. The Gradle config reads private
signing values from `frontend/android/key.properties`, which is gitignored.

Create the file locally when preparing Play Store artifacts:
```properties
storeFile=../upload-keystore.jks
storePassword=<keystore password>
keyAlias=<key alias>
keyPassword=<key password>
```

The keystore file itself must also stay outside Git. Keep the keystore,
passwords, and Play App Signing credentials in a password manager.

## Notes
- The included Nginx config serves `frontend/build/web` and proxies `/api/` and
  `/media/` to FastAPI.
- Terminate HTTPS at this Nginx layer or at a trusted edge proxy/load balancer.
  Enable the HSTS header in `infrastructure/nginx/default.conf` only after TLS
  is active for the production hostname.

