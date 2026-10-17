# Backend 0.2.0 deployment plan (for operator review; NOTHING HERE HAS BEEN EXECUTED)

Branch `fix/release-readiness`, local head `5b2e312` (two commits ahead of `origin`, not pushed). Production database: Alembic `20261013_0026`. This release applies exactly one migration, `20261015_0027` (new table `contact_reveals`, four nullable consent columns; additive).

## 0. Assessment

**NOT READY to execute today. The code, migration and configuration are ready; two preconditions are open:**
1. The production server state has never been read: free disk, the active Compose overlay set, the backend start command and the image tags. The existing read-only script `docs/audits/release-handoff/prod_readonly_inspect.sh` was blocked from running by the permission layer.
2. The two local commits are unpushed, so CI has not run on the head that will be deployed (they change only `pubspec.yaml` and docs, so the risk is low, but the deployed SHA should be CI-green).

Nothing else blocks the backend. Android Google Sign-In, push receipt, email delivery and Play data block the **Android rollout**, not the backend (section 7).

## 1. Release artifacts

| Artifact | Value |
|---|---|
| Source | PR #1 merge commit on `main` (preferred), or branch head after push and green CI. Record the SHA. `origin/production-deploy` is stale (`0012`); do not use it |
| Backend commits | everything in `origin/main..HEAD` (63 commits); the last two are `0bfdbfd` (pubspec `0.2.0+9`) and `5b2e312` (docs). Neither touches backend code |
| Migration | `20261015_0027` (head). Single linear chain `... -> 0025 -> 0026 -> 0027` |
| Backend + worker image | one image built from the release SHA, shared by `backend` and `notification-worker` |
| Android AAB | `frontend/build/app/outputs/bundle/release/app-release.aab`, 67,271,141 bytes, SHA-256 `a87eeffcc951f3ed3fb5824dacf7af368698aad6c1e6dce3fa8ee006ba46bb5e` (upload to internal testing only after section 5 passes) |
| Web | **Not part of this deployment.** Flutter web and the static site stay as deployed. Old web clients work in legacy contact mode |

### Local uncommitted changes (not required for the backend; preserved)
| Change | Needed for backend release? | Recommendation |
|---|---|---|
| `.gitignore` (`/release/`) | No | Optional tiny `chore` commit; keeps AAB/APK output out of Git |
| Website default language `ru` at `/`, `/en/` (`website/*`, `infrastructure/nginx/default.conf`, `local.conf`, `docs/DEPLOYMENT.md`, `docs/adr-public-homepage.md`; 11 files; website unit tests pass, 9/9) | **No.** Changes Nginx routing and the site; only takes effect on a web/Nginx release | Keep out of PR #1; commit on its own branch for a separate web release. Backend steps below never touch Nginx |
| `docs/audits/*` (untracked), `.claude/` | No | Commit only `final-integration/`; leave the rest and `.claude/` untracked |

Unrelated local changes are untouched.

## 2. Configuration readiness (names only; no values were printed)

| Area | Requirement | Status |
|---|---|---|
| Cloudflare R2 | `R2_ACCOUNT_ID`, `R2_ACCESS_KEY_ID`, `R2_SECRET_ACCESS_KEY`, `R2_PUBLIC_BASE_URL` (mandatory in production); `R2_BUCKET` | Names present in the reviewed `.env`; **production upload, public read and delete passed** |
| Resend | `RESEND_API_KEY`, `RESEND_FROM_EMAIL` (mandatory) | Key present. See mismatch below. DNS (DKIM, SPF, MX, DMARC) published; Resend domain status and real delivery **unverified** |
| Google OAuth | `GOOGLE_OAUTH_CLIENT_ID` (mandatory); must equal the AAB `serverClientId` | Backend and AAB values identical. Android OAuth client + SHA-1 **unverified** (console) |
| Firebase FCM | `FIREBASE_PROJECT_ID`, `PUSH_TOKEN_ENCRYPTION_KEY`, `FIREBASE_CREDENTIALS_HOST_PATH` (mounted by `docker-compose.notifications.yml`); all-or-none, enforced at startup | Present; project IDs agree (`FIREBASE_PROJECT_ID` = service account = `google-services.json`); dry-run authenticated. **Never change the encryption key**: stored device tokens become unreadable |
| Contact reveal | `CONTACT_REVEAL_MAX_PER_DAY` (15), `..._PER_WEEK` (40), `..._MIN_ACCOUNT_AGE_HOURS` (0), `CONTACT_LEGACY_DETAIL_ENABLED` (true) | Not set in the reviewed `.env`, so the defaults apply, which is the intended launch config. Keep legacy **true**: installed Android `0.1.0` (code 8) and web depend on it. Reveals are counted in the database, so the quota does not depend on the in-memory rate limiter |
| PostHog | `POSTHOG_PROJECT_TOKEN` + `POSTHOG_HOST` (both or analytics are off); `POSTHOG_REQUIRED` unset | Both names present. Code sends only event names, pseudonymous id, language, moderator flag; no email/name/free text; exception autocapture off; GeoIP off (`test_analytics_privacy.py`). **Owner action:** older code sent `email`/`name` person properties; if analytics ever ran in production, purge them in PostHog (code cannot) |
| Rate limit / proxy | `RATE_LIMIT_ENABLED=true` (required), `TRUSTED_PROXY_CIDRS` | Defaults trust loopback and `172.16.0.0/12` (Docker bridge). Single uvicorn process assumed |
| Other mandatory | `APP_ENV=production`, `APP_DEBUG=false`, strong `JWT_SECRET_KEY`, `POSTGRES_PASSWORD`, `CORS_ALLOWED_ORIGINS`, `PUBLIC_APP_BASE_URL` | Startup refuses to run if any is wrong |

### `EMAIL_FROM` vs `RESEND_FROM_EMAIL`
The backend reads only `RESEND_FROM_EMAIL` (`backend/app/core/config.py:60`); `.env.example` and `infrastructure/README.md` also use it. The reviewed `.env` defines `EMAIL_FROM`, which nothing reads. The code default is `noreply@mushukistan.uz`, so mail already goes out from that address and **behavior does not change**. Fix: in the server `.env` rename the key `EMAIL_FROM` to `RESEND_FROM_EMAIL` (same value). Do it during the window (containers are recreated anyway). No code change is needed or proposed. Caveat: the reviewed `.env` may be the local copy; run the check below on the real server file.

Run on the server against a **copy** (prints PASS/FAIL names only, never values):
```bash
cp .env /tmp/env.preflight && python backend/scripts/prod_preflight.py --env-file /tmp/env.preflight; rm -f /tmp/env.preflight
grep -c '^EMAIL_FROM=' .env; grep -c '^RESEND_FROM_EMAIL=' .env   # counts only
```
Stop on any FAIL.

## 3. How the migration is triggered (and what we do about it)

`backend/Dockerfile` ends with `CMD ["sh","-c","alembic upgrade head && exec uvicorn ..."]`: **any start of the new image migrates the database.** `docs/DEPLOYMENT.md` says the previous release overrode this with a private overlay (`docker-compose.notification-release.yml`, command `uvicorn ...` only). So there are two possible server states; step 1.2 reads which one is real.

Approach (works in both states): run the migration as an **explicit, separate step** from the new image after the backup and while the old backend still serves (the schema change is additive, so the old code ignores it), then swap the containers. At swap time the start-up `alembic upgrade head` is a no-op, or is skipped by the overlay.

Rollback hazard found while reading the Dockerfile: after `0027` is applied, an **old image whose CMD runs `alembic upgrade head` will crash-loop** ("Can't locate revision 20261015_0027"). Rollback therefore must override the command (section 6).

## 4. Rollout (commands for operator review)

Placeholders: `REL` = new versioned release directory; `SHA` = release commit. Overlay set: use the **exact set recorded from the running container labels** (step 1.2); the example is the one documented in `docs/DEPLOYMENT.md`.

```bash
DC="docker compose --profile notifications -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.notifications.yml -f docker-compose.notification-release.yml"
```

### Phase 1: read-only preparation (before the window)
1.1 Server facts (this is `prod_readonly_inspect.sh`; or by hand):
```bash
df -h / /root /var/lib/docker
docker exec mushukistan-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select pg_size_pretty(pg_database_size(current_database()))"'
free -m; docker ps --format '{{.Names}} {{.Image}} {{.Status}}'
```
1.2 Record state (save the output in the release record):
```bash
docker inspect mushukistan-backend --format '{{.Image}} {{json .Config.Cmd}}'   # CMD: migrates on start, or uvicorn only?
docker inspect mushukistan-backend --format '{{index .Config.Labels "com.docker.compose.project.config_files"}}'
docker ps -q --filter name=mushukistan | xargs docker inspect --format '{{.Name}} {{.Id}}' > /root/pre-release-ids.txt
docker exec mushukistan-backend alembic current ; docker exec mushukistan-backend alembic heads   # current MUST be 20261013_0026
```
1.3 Stage the release without touching the running stack:
```bash
git clone <repo> REL && cd REL && git checkout SHA && git rev-parse HEAD
cp <active>/.env . ; cp <active>/docker-compose.notification-release.yml . ; # private overlays/pins
$DC config --quiet                                   # validate; do not print the output (contains secrets)
docker tag mushukistan-backend:local mushukistan-backend:pre-0.2.0   # keeps the rollback image
$DC build backend                                    # builds image mushukistan-backend:local; running containers are NOT replaced
docker run --rm --entrypoint alembic mushukistan-backend:local heads     # expect 20261015_0027
```
Requirement: free disk at least 3x the database size (dump) plus 3 GB (image build). The build tag `:local` replaces the old tag, which is why `pre-0.2.0` is created first.

### Phase 2: window start
2.1 Announce freeze; no other changes. 
2.2 **Fresh backup, immediately before:**
```bash
B=/root/mushukistan-backups/mushukistan-$(date +%Y%m%d-%H%M%S)-pre-0.2.0.dump
docker exec mushukistan-db sh -c 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$B"
test -s "$B" && ls -l "$B" && sha256sum "$B" | tee "$B.sha256"
docker exec -i mushukistan-db pg_restore --list < "$B" | wc -l            # must succeed, many entries
docker exec -i mushukistan-db pg_restore --list < "$B" | grep -E ' TABLE DATA public (users|lost_pets|adoption_posts|alembic_version)' 
```
Copy the dump and its `.sha256` off the server (from the operator machine: `scp`). Stop if the file is empty, `pg_restore --list` fails, a core table is missing, or the size is far below the previous dump. The earlier production backup already passed a full restore rehearsal; a scratch restore of this fresh file is recommended if time allows (`postgis/postgis:15-3.4`, never the production database).
2.3 Re-confirm `alembic current` = `20261013_0026`. Capture the **baseline of the old backend** (public, read-only), for the privacy comparison:
```bash
curl -s https://api.mushukistan.uz/api/v1/health
curl -s 'https://api.mushukistan.uz/api/v1/lost-pets' | grep -c owner_phone_number     # record, expect > 0 on the old backend
```

### Phase 3: explicit migration (old backend still serving)
```bash
$DC run --rm --no-deps -T backend alembic upgrade head          # applies only 0026 -> 0027
docker exec mushukistan-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select version_num from alembic_version"'   # 20261015_0027
curl -sf https://api.mushukistan.uz/api/v1/health                # old backend still healthy
```
Stop if the migration errors or the revision is anything else (the migration is a single transaction on PostgreSQL; a failure leaves `0026`). Do not rerun blindly: read the error first.

### Phase 4: coordinated backend + worker swap
```bash
$DC stop -t 60 notification-worker                               # old worker first: never two workers at once
docker exec mushukistan-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select status,count(*) from notification_push_jobs group by 1"'
```
`sending` must be 0 (leases last two minutes; wait and recheck). Then:
```bash
$DC up -d --no-deps --no-build --force-recreate backend
until [ "$(docker inspect -f '{{.State.Health.Status}}' mushukistan-backend)" = healthy ]; do sleep 3; done
$DC up -d --no-deps --no-build --force-recreate notification-worker
docker ps -q --filter name=mushukistan | xargs docker inspect --format '{{.Name}} {{.Id}}' | diff - /root/pre-release-ids.txt
```
Expected diff: only the backend and the worker differ. Nginx and the database keep their IDs (they are never recreated here). Backend downtime is the container restart (seconds).

### Phase 5: verification (all non-mutating; no users created, no email or push sent)
```bash
docker exec mushukistan-backend alembic current                  # 20261015_0027 (head)
docker logs --since 5m mushukistan-backend 2>&1 | grep -ciE 'error|traceback|critical'      # expect 0
docker logs --since 5m $($DC ps -q notification-worker) 2>&1 | tail -20                     # started, polling
curl -sf https://api.mushukistan.uz/api/v1/health
curl -s -o /dev/null -w '%{http_code}\n' https://api.mushukistan.uz/docs                    # not 200 (docs off)
curl -s 'https://api.mushukistan.uz/api/v1/lost-pets'     | grep -c owner_phone_number     # 0 (guest no longer sees contacts)
curl -s 'https://api.mushukistan.uz/api/v1/adoption-posts' | grep -c owner_phone_number     # 0
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://api.mushukistan.uz/api/v1/lost-pets/00000000-0000-0000-0000-000000000000/contact-reveal   # 401
```
Plus: `python backend/scripts/r2_disposable_smoke.py --execute` (a disposable object only; already passed against production), and `python website/tool/check_production_http.py --flutter frontend/build/web --website website/dist` if the web bundle is at hand (read-only).
Owner-performed, authenticated (uses the owner's **existing** account, no new user): a signed-in reveal on the new AAB once installed from internal testing, and a post with a photo. Mark these NOT VERIFIED until done.
Watch for 24 h: 5xx, 429, login failures, worker `failed` jobs.

## 5. Stop conditions (halt; roll back only if marked)
| Condition | Action |
|---|---|
| `alembic current` is not `20261013_0026` before | Stop; plan is invalid, re-plan from the real revision |
| Free disk below the section 4 minimum | Stop before the build/backup |
| Backup empty, `pg_restore --list` fails, core table missing, no off-server copy | Stop; nothing changes |
| `prod_preflight.py` FAIL, `$DC config` error | Stop |
| Migration error, or revision not `0027` after | Stop; backend untouched; read the error |
| `sending` jobs not draining | Do not start a second worker; investigate |
| New backend not healthy within 2 minutes, or crash-loops | Roll back (section 6) |
| Guest list still contains `owner_phone_number` | Roll back is not the fix (old code leaks more); investigate the deployed image/SHA |
| Guest reveal not 401, health fails, 5xx above 1% for 10 minutes | Roll back |
| Container IDs of Nginx/db changed unexpectedly | Stop and investigate |

## 6. Rollback

**Prefer a forward fix.** Rolling back only the application is safe for data (the schema is additive, rows written stay valid) but it is a **privacy regression**: the previous production backend returns owner phone/Telegram in detail responses to every signed-in user with no quota, and, because it predates the contact-privacy work, probably to anonymous users and in list responses too (the Phase 2.3 baseline measures this). New Android `0.2.0` clients get `404` on reveal under the old backend, so stop testing/distributing the AAB while rolled back. Rollback returns to today's production privacy level, not below it.

6.1 Application rollback (backend + worker together):
```bash
$DC stop -t 60 notification-worker
docker tag mushukistan-backend:pre-0.2.0 mushukistan-backend:local
cat > docker-compose.rollback.yml <<'EOF'
services:
  backend:
    command: ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
DCR="$DC -f docker-compose.rollback.yml"
$DCR up -d --no-deps --no-build --force-recreate backend      # command override is mandatory: the old image cannot parse revision 0027
until [ "$(docker inspect -f '{{.State.Health.Status}}' mushukistan-backend)" = healthy ]; do sleep 3; done
$DCR up -d --no-deps --no-build --force-recreate notification-worker
```
Then verify health, login with the owner's account, and that Nginx/db IDs are unchanged. Keep `0027` in the database.

6.2 Schema: **do not** `alembic downgrade` unless data review requires it; it would drop `contact_reveals` (reveal history and quota counters) and the consent columns (consent evidence for posts created in the window).

6.3 Data restore (last resort, only for data loss/corruption, owner decision, destructive): everything written after the backup is lost. Restore to a scratch database first, compare, then stop backend and worker, and only with explicit approval restore to production from `$B`. Never delete `mushukistan_postgres_data`.

## 7. Remaining blockers requiring owner action

| # | Blocks | Owner action |
|---|---|---|
| 1 | Backend deploy | Run the read-only inspect script on the VPS and share the output (no secrets): `ssh root@<host> 'sh -s' < docs/audits/release-handoff/prod_readonly_inspect.sh > prod_inspect.txt` |
| 2 | Backend deploy | Approve push of `0bfdbfd`, `5b2e312` (+ the docs commit) and CI on the head; merge PR #1 yourself |
| 3 | Backend deploy | Confirm the server `.env` renames `EMAIL_FROM` to `RESEND_FROM_EMAIL`; run `prod_preflight.py` on a copy |
| 4 | Android rollout | Android OAuth client + upload and Play App Signing SHA-1 for `uz.mushukistan.app`; Play versionCode history (9 unused) |
| 5 | Android rollout | One controlled verification email and Resend domain status; one push to a test token |
| 6 | Hygiene | Purge legacy PostHog person properties if analytics ever ran with the old code; native/legal review of RU/UZ wording |

## 8. Smallest next action
Run the one-line inspect script (blocker 1) and send the output. It resolves free disk, the real overlay set and whether the backend already skips migrations at start, which are the only unknowns in this plan.
