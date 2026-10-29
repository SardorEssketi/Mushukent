# Production release procedure

This is the canonical release procedure for the Mushukistan website and Google
Play Android App Bundle. Run commands from the repository root unless a step
says otherwise. Never commit `.env`, `frontend/android/key.properties`, a
keystore, or any service-account credentials.

## Agent runbook: read this first

Last audited 2026-10-19 against the repository, Git history, and earlier release
records. Scripts live in `scripts/deploy/` and are tested offline with
`bash scripts/deploy/test_deploy_scripts.sh`.

### Ground rules for every deployment

1. Deploy only when the user asks in the current conversation, and ask again
   before each production-changing step. Approval of one step is not approval of
   the next. Nothing in this file authorizes a deploy by itself.
2. Never guess an SSH target, container name, path, or environment variable. Use
   the values below; if they are not listed or marked unknown, ask.
3. Never print, copy into Git, or overwrite a production `.env`, keystore,
   `key.properties`, Firebase file, or OAuth secret. Compare `.env` key *names*
   only. Never remove the database or media volumes (`docker compose down -v`,
   `docker volume rm`, `docker system prune --volumes`) or run
   `alembic downgrade` without explicit approval.
4. Agent SSH to production is gated by Claude Code's permission classifier
   ("Production Reads"). It was denied in earlier audits and at the start of the
   2026-10-19 session; the user then granted the agent permission for the
   reviewed read-only inspection only. That grant covers `remote-inspect.sh` and
   equivalent read-only reads (`cat`/`ls`/`sha256sum`/`docker inspect`). It does
   **not** cover uploads, backups, container changes, or `--execute` of any
   script: the user runs those with `! ssh -t <ssh-target> ...`. If SSH is
   denied, do not work around it; give the user the exact command and ask for the
   output. The restricted deploy account used by `release-web` is a separate
   identity with its own rules (see "Approval-based automation" below and
   `CLAUDE.md` rule 6).
5. **Release branch: `main`** (owner decision, 2026-10-19). Release only from a
   commit that is on `origin/main`, pushed, and CI-green. Never release from a
   feature branch, from `production-deploy` (stale), or from a dirty tree. The
   packaging scripts refuse a dirty tree; `build-backend-image.sh` warns when the
   commit is not on `origin/main`.
6. **Every production deployment needs the user's explicit approval**, given in the
   current conversation for the specific commit. Use the approval gates below.
   Do not activate old staged releases (for example the `20261018-bf9c91d-*`
   directories): build each release from the intended, verified `main` commit.
7. **Never build Docker images on the production VPS** (a small host with limited memory). Build
   locally with `scripts/deploy/build-backend-image.sh`, move the tarball, and
   `docker load` it on the server.
8. The hosting provider is **unverified**. Do not state a provider as fact, and do
   not change infrastructure documentation based on a hostname, until the user confirms.
9. Mark every flow `VERIFIED`, `FAILED`, or `NOT VERIFIED` in the release record.

### Approval gates

Each gate is a separate question to the user; one "yes" does not carry over. State
the commit SHA, the exact command, what it changes, the rollback, and any downtime.

| Gate | Action | Server impact |
| --- | --- | --- |
| G0 | Build and package locally (`build_production.ps1`, `package-release.sh`, `build-backend-image.sh`) | none |
| G1 | Read-only inspection over SSH (`remote-inspect.sh`) | none; permitted once the user has granted the agent's SSH read rule |
| G2 | Upload and extract a release / load an image; create a new release directory | adds files and an image tag; running containers untouched |
| G3 | Database backup (`backup-db.sh --execute`) | adds a dump file; brief read load |
| G4 | Activation: `activate-web-release.sh --execute`, or backend/worker recreate | **replaces containers**; Nginx recreate is a few seconds of downtime, backend swap is longer |
| G5 | Migration (`alembic upgrade head`) | schema change; needs its own review of the revision |
| G6 | Rollback | replaces containers; do it as soon as a stop condition hits, then report |

G4-G6 are always run by the user in a real terminal (`! ssh -t <ssh-target> ...`):
the scripts need a typed confirmation and refuse without a terminal.

### Fact status

Evidence levels: **VERIFIED** = observed directly on 2026-10-19 (read-only SSH
inspection with `scripts/deploy/remote-inspect.sh`, public HTTPS, `git`); **RECORD**
= only stated in older documents; **UNKNOWN** = nobody has confirmed it. Re-run the
inspection before every deployment: this state changes with each release.

**This repository is public.** Host addresses, sizing, backup inventories, row counts and
hardening notes are therefore kept out of Git, in the gitignored
`docs/private/PRODUCTION_STATE.md` on the operator machine. If that file is missing, run the
inspection and ask the user; do not reconstruct it from memory.

**SSH target.** It is not stored in Git. It comes from the gitignored `scripts/deploy/local.env`
(`MUSHUKISTAN_SSH_TARGET=user@host`, see `local.env.example`) or the `MUSHUKISTAN_SSH_TARGET`
environment variable; `bash scripts/deploy/ssh-target.sh` prints it. Below, `<ssh-target>` means
that output. If none is configured, ask the user. SSH works non-interactively from the operator
workstation with `ssh -o BatchMode=yes -o StrictHostKeyChecking=yes <ssh-target>`; the agent needs
the user's explicit permission rule for it.

**Repository (VERIFIED)**

- Compose project `mushukistan`. Services: `db` (`postgis/postgis:15-3.4`, `mushukistan-db`), `backend` (`./backend`, container `mushukistan-backend`), `notification-worker` (profile `notifications`, same image, auto-named `mushukistan-notification-worker-1`), `nginx` (`nginx:1.27-alpine`, `mushukistan-nginx`). Volumes `postgres_data`, `backend_media`.
- `docker-compose.prod.yml` mounts `./frontend/build/web` -> `/usr/share/nginx/html`, `./website/dist` -> `/var/www/landing`, `./infrastructure/nginx/default.conf`, `/etc/letsencrypt`, `./infrastructure/certbot/www`. `docker-compose.notifications.yml` mounts the Firebase service-account file from `$FIREBASE_CREDENTIALS_HOST_PATH`.
- `backend/Dockerfile` runs `alembic upgrade head && uvicorn`, but production overrides it (below), so production does **not** migrate on start.
- Backend runtime dependencies are locked in `backend/constraints.txt` (a `pip freeze` of the production image) and used by the Dockerfile and CI.
- Nginx proxies to `backend:8000` without a `resolver`: it must be reloaded after the backend container is recreated.

**Git (VERIFIED 2026-10-19)**

- Canonical remote: `origin` (GitHub, public repository). **`main` is the release branch** (owner decision). `production-deploy` is stale; do not use it.

**Production (VERIFIED by read-only inspection on 2026-10-19)**

- Four containers run under the Compose project: Nginx, backend, notification worker, database. Backend and worker run `mushukistan-backend:<sha7>` (image tag = release commit's sha7). Older images are retained for rollback.
- Compose labels of every container name one working directory under `/opt/mushukistan-releases/` and this file order: `docker-compose.yml`, `docker-compose.prod.yml`, `docker-compose.notifications.yml`, `docker-compose.notification-release.yml`.
- **The Compose working directory is not necessarily the web release.** On 2026-10-19 it was a *backend-only* release (its `README_RELEASE.txt`: "frontend/build/web, website/dist are symlinks to the active web release") whose web and landing directories were symlinks into an older web release. The public `main.dart.js` hash matched that older web release. Always determine the served web release from Nginx's bind mounts with symlinks resolved (the inspect script and `activate-web-release.sh` do this), and never delete either directory of the current pair: together they are the rollback target.
- After the 2026-10-24 web release, Nginx's labels and bind mounts name the web release `20261024-5b4bd33-feed-redesign` (real `frontend/build/web` and `website/dist`, no symlinks), while backend and worker still name the backend-only release `20261018-fb1f6d4-backend`; this mixed state is expected (see the release record).
- Staged web releases from 2026-10-18 exist but are **not** active and must not be activated (owner decision); build each release from the intended verified `main` commit.
- The private overlay `docker-compose.notification-release.yml` (not in Git, about 250 bytes) is identified and contains no secrets. It pins backend and worker to `mushukistan-backend:<sha7>`, overrides the backend command to `uvicorn app.main:app --host 0.0.0.0 --port 8000` (no auto-migration), and sets `healthcheck.start_interval: 2s`. A sanitized template is `infrastructure/docker-compose.notification-release.example.yml`. Releases carry different versions of it, so always copy it from the *active* working directory and change only the tag.
- Release directory conventions: name `<YYYYMMDD>-<sha7>-<label>`; files `RELEASE_COMMIT.txt` (full SHA), `README_RELEASE.txt`, and in some releases `PREVIOUS_STATE.*` and `ROLLBACK.sh`. Releases are copied source, not Git clones. Each has its own `.env` (mode 0600). Never print `.env` files.
- Database: PostgreSQL 15 / PostGIS 3.4, Alembic revision `20261015_0027` (head of the deployed code). `.env` provides every required variable name; `TRUSTED_PROXY_CIDRS` and `CONTACT_*` are unset (code defaults apply); `APP_ENV=production`, `APP_DEBUG=false`.
- Backups: manual dumps exist under `/root/mushukistan-backups/` with the naming `mushukistan-YYYYMMDD-HHMMSS-<label>.dump` (+ `.sha256`). A baseline backup taken on 2026-10-19 passed `pg_restore --list` and a restore rehearsal in a disposable PostGIS (details in the private state file). Automated encrypted backups are prepared but **not enabled** (`docs/BACKUP.md`). Take a fresh backup before any change.
- Automatic TLS renewal uses certbot's webroot method with the persistent host directory `/var/www/certbot`, mounted into Nginx by `docker-compose.prod.yml` (phase 1 on 2026-10-20, phase 2 on 2026-10-21), plus a deploy hook that reloads Nginx. Certificate valid until 2027-01-18. See `docs/TLS_RENEWAL.md`.
- The server can reach its own public HTTPS (needed by `activate-web-release.sh`), and has `curl`, `script`, `sha256sum`, `readlink`, `git`, `python3`, Docker Compose v2. `scripts/deploy/verify-public.sh` passes against the live site.

**RECORD only (not re-verified)**: Cloudflare in front of `media.mushukistan.uz` (R2) and its cache rules; Google Cloud OAuth clients and SHA-1s; Play Console version codes; Firebase project setup.

**UNKNOWN**: the hosting provider (**unverified; do not state one as fact**: older docs say Hetzner); who may merge to `main` and the release approval flow beyond the gates below; where the private overlay and server `.env` files are backed up off the server.

To refresh these facts (read-only, no secrets in the output):

```powershell
ssh (bash scripts/deploy/ssh-target.sh) 'sh -s' < scripts/deploy/remote-inspect.sh > prod_inspect.txt
```

`prod_inspect*.txt` is gitignored (it names hosts, container IDs, and row counts).

### What each component is and what deploying it touches

| Component | Built from | Runs as | Deploy touches |
| --- | --- | --- | --- |
| Backend API | `backend/` Docker image | container `mushukistan-backend` | image, container, DB migrations (on start) |
| Notification worker | same image as backend | `notification-worker` (profile `notifications`) | must be replaced together with the backend, never two at once |
| Flutter Web | `frontend/` via `frontend/tool/build_production.ps1 -Target Web` -> `frontend/build/web` | static files in the Nginx container | Nginx container only |
| Landing page | `python website/build.py` -> `website/dist` | static files in the Nginx container (`/var/www/landing`) | Nginx container only |
| Android | `build_production.ps1 -Target Android` (AAB) / `AndroidApk` | Google Play (internal testing, then staged rollout) | nothing on the server |
| Database | `postgis/postgis:15-3.4` | container `mushukistan-db`, volume `mushukistan_postgres_data` | **never recreated**; only Alembic migrations and backups |
| Media | Cloudflare R2 (`R2_*` in `.env`), served from `media.mushukistan.uz` | external | nothing (local `backend_media` volume is dev only) |
| TLS | Let's Encrypt on the host, `/etc/letsencrypt` | host files mounted read-only | nothing |

Flutter Web and the landing page are **one release unit** with the Nginx config.
They are always replaced as complete directories, never file by file.

### Release strategy (unchanged)

Each release is a new versioned directory `/opt/mushukistan-releases/<YYYYMMDD>-<sha7>-<label>`
with the reviewed source, a copy of the active `.env`, and the private overlay
`docker-compose.notification-release.yml`. The Compose project (`name: mushukistan`) is
run from a release directory, so volumes, networks, and container names stay the
same. Two release shapes are in use:

- **Backend-only release** (e.g. `20261018-fb1f6d4-backend`): new source and image
  pin; `frontend/build/web` and `website/dist` are symlinks to an existing web
  release, so the Compose working directory differs from the served web directory.
- **Web release** (e.g. `20261013-4eff1f2-main`): complete real
  `frontend/build/web` and `website/dist`; activated by recreating only Nginx.

Previous releases stay intact and are the rollback targets. "Active" is not one
directory: read the backend image, command, and overlay from the Compose labels
and the served web directory from Nginx's bind mounts with symlinks resolved.

### Which procedure to use

| Change | Procedure |
| --- | --- |
| Flutter Web and/or landing/Nginx config only | A |
| Backend code, with or without Web | B (then A for the Web part) |
| Android app only | C |
| Migration | B, with the gate in "Database backup and migration gate" below |

**Approval-based automation (web releases only): INSTALLED (2026-10-29).** Procedure A is
normally run with the `release-web` CLI: `docs/DEPLOYMENT_AUTOMATION.md`, section 13 ("Operating
runbook"). The agent prepares and deploys through the restricted `mushukistan-deploy` account;
the server executes only what an owner-signed approval allows (stage, backup, activate,
auto-rollback) for that exact artifact and time window. The owner signs every approval in their
own terminal, and that signature replaces the typed confirmations of G2-G4 (and G6 with an
owner-signed rollback approval) for web releases. Procedures B and C, migrations (G5) and
anything that is not a web release stay manual. The manual procedure A below remains the
fallback whenever the automation is unavailable; both scripts' typed-confirmation paths are
unchanged, and `--approval-token` accepts only a root-owned single-use token written by the
approval broker.

### A. Web / landing release (Nginx only)

No backend, worker, database, or volume is touched. Container IDs of everything
except Nginx must be identical before and after.

1. **Build locally, from a clean committed and pushed tree** (PowerShell, repo
   root): set `$env:MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID` from the user's secure
   configuration (ask; never commit it). Then run the canonical sequence in
   "Canonical production web build" and "Public homepage release addition"
   below: `build_production.ps1 -Target Web`, `python website/build.py`, website
   tests, `check_flutter_bundle.py`, and `check_nginx_http.py`.
2. **Package** (local, uploads nothing):
   `bash scripts/deploy/package-release.sh --label <short-label>`. It refuses a
   dirty tracked tree (unless `--allow-dirty`, which is recorded), a missing or
   non-production bundle, and any secret-like file. Output: `release/<name>.tar.gz`
   plus `.sha256` (the directory is gitignored). The archive includes
   `RELEASE_COMMIT.txt` and `scripts/deploy/`, which the server-side steps below use.
3. **Inspect, then stage on the server** (each needs user approval): run the
   inspection (see Fact status), upload the archive to `/opt/mushukistan-releases/`,
   verify the checksum, extract, then **copy** `.env` and
   `docker-compose.notification-release.yml` from the current Compose working
   directory (the `project.working_dir` label; on 2026-10-19 that was
   `20261018-fb1f6d4-backend`) into the new directory. The overlay's image tag
   stays as it is: a web release does not replace the backend. Never modify the
   old directory.
4. **Dry run** (changes nothing), on the server:
   `bash /opt/mushukistan-releases/<name>/scripts/deploy/activate-web-release.sh <name>`.
   It reads the Compose labels and Nginx bind mounts, resolves symlinks, prints
   `web: <currently served> -> <new>`, re-uses the exact overlay file set (and the
   `notifications` profile when the worker runs), checks the bundle (production
   API URL, no dev hosts, local CanvasKit), compares `.env` key *names* with the
   current one, validates `docker compose config`, and runs `nginx -t` in a
   disposable container.
5. **Backup** (needs approval): `ssh -t <ssh-target> bash /opt/mushukistan-releases/<name>/scripts/deploy/backup-db.sh --label web-<sha7> --execute`.
   Copy the dump and `.sha256` off the server.
6. **Switch** (needs approval; run it in a real terminal because it requires
   typing `ACTIVATE <name>`): `ssh -t <ssh-target> bash /opt/mushukistan-releases/<name>/scripts/deploy/activate-web-release.sh <name> --execute --backup-file <dump>`.
   It refuses without a non-empty dump younger than 12 h that passes
   `pg_restore --list`, writes `PREVIOUS_STATE.txt` (including the rollback
   command) into the new directory, runs only `up -d --no-deps --no-build
   --force-recreate nginx`, checks `nginx -t` and the new mounts, compares
   container IDs, and runs `verify-public.sh` against the new bundle hash. On any
   failure it prints the rollback command and exits non-zero.
7. **Verify** with "Health checks" and the browser/route lists in "Website
   deployment" below, then record the result in `docs/` or the release record.

**TLS renewal and Nginx replacement.** The dry run (step 4b) and the post-switch check compare certbot's
webroot with the ACME directory the release mounts. If a release changes that mount, run the printed
`set-webroot.sh <path> --execute` right after activation (and after any Nginx rollback to an older
release). See `docs/TLS_RENEWAL.md`.

Re-running step 6 for what Nginx already serves is a safe no-op that only
re-verifies.

### B. Backend (+ worker) release

Higher risk and intentionally **not** automated: it needs a coordinated worker
swap, an explicit migration decision, and an Nginx reload. The reviewed worked
example is `docs/audits/final-integration/BACKEND_DEPLOYMENT_PLAN.md` (it
describes the release that was then executed as `20261018-fb1f6d4-backend`; reuse
its structure, not its revision numbers). Production already runs the
uvicorn-only command (no migration on start) with the overlay pinning
`mushukistan-backend:<sha7>`. Mandatory order:

1. Run the inspection. Stop if `alembic current` is not the revision the release
   plan assumes (`20261015_0027` on 2026-10-19) or if the running image differs
   from the overlay.
2. Stage a new directory as in A.2-A.3 (package, upload, extract, copy `.env` and
   the overlay), then edit **only the two image tags** in the new overlay to
   `mushukistan-backend:<sha7>` and set `frontend/build/web`/`website/dist` to the
   web release that should stay live (symlinks, as `20261018-fb1f6d4-backend` does).
   Validate with `$DC config --quiet` (never print the output). Use `--no-build` on every
   `up` so Compose can never trigger a build on the server.
3. **Build locally, never on the server** (dependencies are locked in `backend/constraints.txt`). `bash scripts/deploy/build-backend-image.sh`
   (from the pushed `main` commit) builds `linux/amd64`, checks for exactly one
   Alembic head, and writes `release/mushukistan-backend-<sha7>.tar.gz` plus a
   checksum. After approval (G2) upload it and run `gunzip -c ... | docker load` on
   the server; that adds an image tag and touches no running container.
4. `backup-db.sh --execute`; confirm with `pg_restore --list`; copy off-server.
5. Run `backend/scripts/prod_preflight.py` on a *copy* of `.env` (it prints
   PASS/FAIL names only; remove the copy afterwards).
6. If the release has migrations, apply them as a separate explicit step while
   the old backend still serves (`$DC run --rm --no-deps -T backend alembic upgrade head`);
   only additive migrations are acceptable without separate review.
7. Stop the old worker, wait until no push job is `sending`, recreate the backend,
   wait until healthy, then recreate the worker. Never run two workers at once.
8. **Immediately** run `docker exec mushukistan-nginx nginx -t && docker exec mushukistan-nginx nginx -s reload`
   (Nginx keeps the old backend IP otherwise).
9. Verify health, logs, guest endpoints, `alembic current`, and that the db and
   Nginx container IDs are unchanged.

### C. Android

Local only; nothing is deployed to the server. Increment the build number
(`+N` in `frontend/pubspec.yaml`) only after confirming in Play Console that the
code was never uploaded, set `MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID`, then run
`.\frontend\tool\build_production.ps1 -Target Android` (AAB) or `-Target AndroidApk`
(add `-EnableAndroidPush` for push builds). Upload happens in Play Console by the
user (internal testing first, then staged rollout). Signing inputs
(`frontend/android/key.properties`, keystore, `google-services.json`) are ignored
by Git; if missing, the build fails by design. Artifacts are written under
`frontend/build/app/outputs/` (gitignored); `release/` is the gitignored place
for kept copies.

### Health checks

| Check | Command / expectation |
| --- | --- |
| Public smoke (read-only) | `bash scripts/deploy/verify-public.sh [--flutter-dir frontend/build/web]` -> `ALL CHECKS PASSED` |
| Deep artifact/header gate | `python website/tool/check_production_http.py --flutter frontend/build/web --website website/dist --report .data/production-http.json` |
| API | `curl -sf https://api.mushukistan.uz/api/v1/health` |
| Containers | `docker ps --format '{{.Names}} {{.Status}}'` shows backend `healthy`; no restart loops |
| Served web release | Nginx bind mounts (`docker inspect mushukistan-nginx`), symlinks resolved, equal the intended release |
| Migration state | `docker exec mushukistan-backend alembic current` equals `alembic heads` |
| Logs | `docker logs --since 10m mushukistan-backend 2>&1 \| grep -ciE 'error\|traceback\|critical'` is 0 |
| Isolation | Container IDs of everything except the replaced services are unchanged |
| Certificate renewal | `bash scripts/tls/check-tls.sh` (public: days left, HTTP-01 routing) and, on the server, `bash /usr/local/lib/mushukistan-tls/check-tls.sh --all` (renewal webroot equals Nginx's ACME mount, deploy hook, timer, end-to-end probe). Check before every release; procedure in `docs/TLS_RENEWAL.md`. |

### Rollback

| Situation | Action |
| --- | --- |
| Web/landing release failed | Switch only Nginx back with the command printed by `activate-web-release.sh` (also saved in the new release's `PREVIOUS_STATE.txt`): Compose from the previous working directory, same file set, `up -d --no-deps --no-build --force-recreate nginx`. That directory's symlinks still point to the previous web release, so keep both directories. Then `verify-public.sh` against the old bundle hash. No data or migration is involved. |
| Backend failed, schema additive | Run Compose from the previous release directory (its overlay pins the previous image and the uvicorn-only command): stop the worker, recreate backend, wait healthy, recreate worker, then `nginx -s reload`. Keep the migrated schema; do not `alembic downgrade`. Check whether the rollback regresses privacy (see the plan's section 6). |
| Data loss/corruption | Last resort and the user's decision: restore the pre-release dump to a scratch database first, compare, and only with explicit approval restore to production. Never delete `mushukistan_postgres_data`. |

### Troubleshooting

| Symptom | Cause / fix |
| --- | --- |
| Whole API returns 502 after recreating the backend | Nginx resolved `backend` once. `docker exec mushukistan-nginx nginx -s reload`. |
| A rolled-back backend exits with `Can't locate revision` | Old image against a newer schema without the uvicorn-only command; the overlay must keep the command override. |
| `docker compose up --build` on the server replaced my backend | `--build` rebuilds and recreates dependents. Never use the quick-start in `infrastructure/README.md` on the production host; use the procedures above. |
| The Compose working dir looks like the wrong web release | Expected for backend-only releases: web/dist are symlinks. Read the resolved Nginx mounts. |
| `config` fails on `FIREBASE_CREDENTIALS_HOST_PATH` | `docker-compose.notifications.yml` needs it set in the release's `.env`. |
| Safari/old shell mismatch after a release | Files were changed inside a live directory. Always switch to a complete new directory. |
| `main.dart.js` download times out on the workstation | The bundle is about 4.7 MB; slow links need 20-60 s. `verify-public.sh` allows 180 s for it. |
| `flutter build web` output lacks `useLocalCanvasKit` | A plain `flutter build web` was run after the script. Rebuild with `build_production.ps1 -Target Web`. |
| Backend refuses to start in production | Startup validation rejects placeholder secrets, `APP_DEBUG=true`, missing R2/CORS values. Read `docker logs mushukistan-backend`; names only, never values. |
| `.env` has both `EMAIL_FROM` and `RESEND_FROM_EMAIL` | Only `RESEND_FROM_EMAIL` is read; `EMAIL_FROM` is a harmless leftover. |
| `certbot renew` fails with `Could not bind TCP port 80` | The lineage uses the `standalone` authenticator, which cannot work while the Nginx container owns port 80. Use the webroot method: `docs/TLS_RENEWAL.md` (never stop Nginx to renew). |
| `check-tls.sh --server` says the renewal webroot is not what Nginx serves | An Nginx (re)creation or rollback changed the ACME mount. Run the printed `set-webroot.sh <path> --execute` (typed confirmation); no container change. |
| Agent SSH denied | The permission classifier blocks it unless the user grants a rule (see ground rule 4). Ask the user. |

### Off-server backups (proposal, NOT implemented; needs the user's decision)

Nothing below copies a secret anywhere. Automated encrypted backups are prepared but not
enabled (`docs/BACKUP.md`); there is no confirmed off-server copy of anything yet.

| Asset | Sensitivity | Proposed strategy |
| --- | --- | --- |
| Database dumps (`/root/mushukistan-backups/*.dump`) | personal data (emails, phones, posts) | 1) pre-release: `backup-db.sh` (G3), then pull with `scp` to the operator workstation and verify the `.sha256`. 2) Nightly `pg_dump -Fc` by cron on the server (a 22 MB database), keep 14 daily + 8 weekly. 3) Off-site copy **encrypted before it leaves the server** with `age` (public key on the server, private key kept offline by the owner), uploaded to a private bucket separate from the media bucket with a write-only token. Quarterly restore rehearsal. |
| Server `.env` per release (mode 0600) | secrets (JWT, DB, R2, Resend, Firebase key, Fernet key) | Never in Git, chat, or an unencrypted cloud folder. Owner keeps one current copy in a password manager or an `age`-encrypted file made on the server and pulled as ciphertext. `PUSH_TOKEN_ENCRYPTION_KEY` must never change (stored device tokens become unreadable). |
| Private overlay `docker-compose.notification-release.yml` | no secrets (verified) | Template in Git (`infrastructure/docker-compose.notification-release.example.yml`); the real one is a copy of the active file with the tag changed, and each release directory keeps its own. |
| Firebase service account file (host path in `FIREBASE_CREDENTIALS_HOST_PATH`) | secret | Same vault as `.env`; can be re-issued from the Firebase console if lost. |
| Release directories | source copies, `.env` copies | Rebuildable from `main`; keep at least the active and previous release. No retention policy exists yet; do not prune without approval. |

Decisions needed from the user: off-site destination (external drive, a private
bucket, or both), whether to approve the nightly cron, and who holds the `age`
private key. A restore rehearsal was done on 2026-10-19 (below) and takes minutes.

### Known risks of the activation procedure

| Risk | Status / mitigation |
| --- | --- |
| Nginx recreate drops connections for a few seconds (single container, no blue/green) | Accepted; schedule low-traffic windows; the script is Nginx-only. |
| Backend swap has more downtime and needs an Nginx reload | Manual procedure B; the reload is a mandatory step. Untested end to end on the real server. |
| First `activate-web-release.sh` run happens from a freshly extracted release (the scripts are not on the server yet) | The package includes `scripts/deploy/`. Dry run first. |
| `.env` copied into a new release can be stale | The script compares key *names* with the active `.env`; values are not compared. Copy it from the active directory at staging time. |
| Different overlay versions across releases (image pins) | Always copy from the active working directory; only the backend procedure edits image tags. |
| Rollback relies on the previous directory and its symlink targets still existing | Never delete `20261013-4eff1f2-main` or `20261018-fb1f6d4-backend` until a newer pair is proven; `PREVIOUS_STATE.txt` records the targets. |
| Rollback restarts Nginx again (second short outage) | Accepted. |
| `verify-public.sh` needs the server to reach its own public HTTPS | Verified on 2026-10-19 (hairpin works, `curl` present). |
| Migrations are manual; old images cannot parse newer revisions | Overlay keeps the uvicorn-only command; backups precede every migration. |

### Readiness by deployment path

| Path | Status |
| --- | --- |
| Local build + package (`package-release.sh`, `build-backend-image.sh`) | Package: **VERIFIED** offline (tests, Debian). Image build script: syntax checked; see the release record for a real build. |
| Read-only inspection and public smoke check (`remote-inspect.sh`, `verify-public.sh`) | **VERIFIED** against production on 2026-10-19, including from the server itself. |
| Database backup | **VERIFIED**: a baseline backup on 2026-10-19 passed `pg_restore --list` and a restore rehearsal in a disposable PostGIS (identical Alembic revision and row counts); details are in the private state file. A copy is on the operator workstation (gitignored). No confirmed off-site copy. `backup-db.sh --execute` has only run against stubs (no terminal available to the agent). |
| Web activation (`activate-web-release.sh`) | **VERIFIED** in a disposable Linux + real Docker Compose rehearsal (`scripts/deploy/e2e_disposable.sh`): symlinked backend-only release layout, label/mount parsing, dry run, wrong confirmation, success, idempotent re-run, rollback restoring the previous release, failed verification, refused release; only the Nginx container changed. **NOT VERIFIED** on the real server (never run there). |
| Backend/worker release (procedure B) | Dependencies are locked and the image rebuilds reproducibly; manual steps only; the image `docker load` flow and a real backend swap are **NOT VERIFIED** on the server. |
| Android | Local build procedure only; not exercised in this audit. |

### Next-release readiness (updated 2026-10-20)

| Item | Status |
| --- | --- |
| Backend dependency drift (found 2026-10-19) | **Resolved on `main`.** `backend/constraints.txt` is the `pip freeze` of the production image and is used by the Dockerfile and CI. Cause: with unpinned FastAPI 0.149 / Starlette 1.9 an absent optional `bool` form field is parsed as `False` (instead of `None`), so older app versions posting an adoption without the consent checkbox got `422 CONTACT_CONSENT_REQUIRED`. With the locked 0.143.3 / 1.8.0 they work (two regression tests cover it). The rebuilt image's package set is identical to production's (90 pins). To change dependencies, follow the header of `constraints.txt` and rerun the full suite. |
| Backend code vs production | Production runs `fb1f6d4`. Full backend suite with the locked dependencies: 537 passed, 2 skipped, 0 failed; ruff and black clean. `main` differs only by two lines of Google-token audience logging in `auth/infrastructure/tokens.py` and the dependency lock. No behavior change, so a backend release is optional and can wait for the next real backend change. |
| Web, landing and Nginx | **Deployed 2026-10-24** as `20261024-5b4bd33-feed-redesign` (see the release record). Rollback target retained. |
| Staged old web releases (`20261018-bf9c91d-*`) | Not to be activated (owner decision). |

### Release record

| Date | Release | Scope | Result |
| --- | --- | --- | --- |
| 2026-10-20 | `20261020-b117e64-web-posthog` (`main` commit `b117e64`, CI green) | Web only: Russian-default landing at `/`, `/ru` and `/ru/` -> `/` (301), `/en/`, cookieless PostHog page-view beacon, rebuilt Flutter web bundle (icons, manifest, privacy page), updated Nginx config. | **Activated by the owner** (typed confirmation); Nginx recreated (about 3 s). Backend, worker and database untouched (container and image IDs identical before and after). Rollback target retained: Compose from `20261018-fb1f6d4-backend` (whose web/dist symlinks point to `20261013-4eff1f2-main`). |
| 2026-10-21 | `20261021-e4bd3f9-acme-mount` (`main` commit `e4bd3f9`, CI green) | Source-only, Nginx-only: the ACME mount becomes the persistent `/var/www/certbot`; web and landing are symlinks to the directories of `20261020-b117e64-web-posthog`, so served bytes are identical. | **Activated by the owner**; Nginx recreated (about 2 s). Backend, worker and database untouched (container and image ids identical). Certbot webroot synchronized and staging-validated. Rollback target retained: Compose from `20261020-b117e64-web-posthog`. **Do not delete `20261020-b117e64-web-posthog`**: the active release's web files are symlinks into it. |
| 2026-10-24 | `20261024-5b4bd33-feed-redesign` (`main` commit `5b4bd33`, CI green: run 40083632886) | Web only: Feed redesign (compact header, denser cards, blurred photo backdrop rendered once, gallery controls, compact guest card, Cat needs help "View on map") and the Map rule that unsupported deep-link coordinates never show a clamped focus. Rebuilt Flutter bundle; landing, legal pages, `index.html`, bootstrap, CanvasKit, icons, manifest, Nginx config and Compose files byte-identical to the previous release (only `main.dart.js` and `.last_build_id` differ). Web client ID taken from the live bundle (public value, unchanged). | **Activated by the owner** (typed confirmations for backup and activation); only Nginx recreated. Backend, worker and database untouched (container and image ids identical, Alembic `20261015_0027`). Pre-activation backup verified (checksum, `pg_restore --list`). Certbot webroot unchanged (`/var/www/certbot`), all TLS checks pass. Rollback target retained: Compose from `20261021-e4bd3f9-acme-mount` (web/dist symlinked to `20261020-b117e64-web-posthog`); keep both. |

Verification after activation (all read-only; **VERIFIED**): served `main.dart.js` SHA-256 equals the release (`2767e35a...32c47`); 63 deep public HTTPS artifact checks passed; `/` is `lang="ru"` with canonical `/` and hreflang ru/en/uz/x-default; `/en/` and `/uz/` serve; `/ru`, `/ru/` return 301 to `/`; the sitemap lists `/`, `/en/`, `/uz/`; the manifest (`start_url=/feed`), all five icons and the privacy page match the release byte for byte; the page's PostHog `$pageview` (EU host) returned HTTP 200 with no cookies, no local/session storage, no CSP violations, `$process_person_profile=false`, and only these fields: random per-load UUID, page URL/path/host, referrer, screen size, browser language, page language; backend `healthy`, worker running, zero restarts, no new errors in Nginx, backend, worker or database logs. Not exercised: Google sign-in, authenticated flows, real-device behavior (**NOT VERIFIED**).

Verification after the 2026-10-24 activation (read-only): **VERIFIED**: served `main.dart.js` SHA-256 equals the release (`49daa99c...e7d8`) inside the container and publicly; `verify-public.sh` passed from the server and the workstation; 63 deep public HTTPS checks passed (artifact hashes, headers, locale redirects, legal pages, API health, notification-API auth); guest Feed on a 412 px phone viewport shows the new header, filters, guest card, photo backdrops and gallery counters/arrows on real posts; Map deep link with a Tashkent location opens with the focus ring, and an out-of-area location (Samarkand) opens the default Tashkent view; backend `healthy`, worker running, zero restarts; no new errors in Nginx, backend, worker or database logs and no 5xx responses since activation; all server TLS checks pass. **NOT VERIFIED on production**: Lost Pet, Cat needs help and adoption cards (production had no such posts at release time; verified on the preview build and a physical Android device), in-app Russian and Uzbek (needs a signed-in account; verified on preview and the device), authenticated flows and Google sign-in, PostHog beacon delivery (landing and shell are byte-identical to the previous verified release).

Lessons learned (apply to the next release):

- **Order that worked:** package -> upload -> checksum on the server -> extract with `--no-same-owner` -> copy `.env` and the overlay with `cp -p` (compare hashes, never print) -> dry run -> fresh backup (<12 h) -> the owner types the activation -> read-only verification.
- **Mixed Compose labels are expected.** After a web release, Nginx's `working_dir` label names the new web release while backend and worker still name the backend-only release. Read each service's own labels; the overlay set is read from Nginx and is identical in both.
- **Check certificate renewal before every release** (read-only: `certbot certificates` and `journalctl -u certbot.service`). It is a release-independent risk that went unnoticed until this audit.
- **Windows Python cannot verify the Let's Encrypt chain** (an expired cross-signed path). `curl` works. Run the Python checkers with `SSL_CERT_FILE=$(python -c "import certifi;print(certifi.where())")`, or from Linux.
- **`check_production_http.py` cannot run over stdin** (it locates its repo from its own path); run it from a checkout.
- **Git Bash rewrites `/path` arguments** (also inside `curl -w` formats). Set `MSYS_NO_PATHCONV=1` for ad-hoc checks and any `docker` call with Unix paths, but **not** for `verify-public.sh` on Windows: it then writes curl output to `/tmp` paths MinGW curl cannot open and every check reports status `000`.
- **The operator link can be slow** (about 200 KB/s on 2026-10-24: `main.dart.js` about 25 s, `canvaskit.wasm` about 2 min). Give browser smoke tests several minutes before judging a stuck loading screen; the server-side `verify-public.sh` is the authoritative availability check.
- **Log scans:** a broad regex such as `5[0-9][0-9] ` matches byte counts in access logs and `200 OK` health lines. Use `" 5[0-9][0-9] "` against the status field and expect the known `http2` deprecation warnings from Nginx 1.27.
- **Expected benign results:** `/docs` returns 404 (API docs are closed, and `verify-public.sh` requests it); `/ru/index.html` falls back to the Flutter shell (200), which is harmless.
- **The repository is public.** Never commit host addresses, backup inventories, row counts, hardening notes or secrets; keep them in `docs/private/PRODUCTION_STATE.md` and `scripts/deploy/local.env` (both gitignored).
- **Analytics note:** PostHog receives the visitor's IP address as part of the HTTP request (inherent to any beacon). The payload itself carries no identifiers; confirm the project's IP/GeoIP handling in PostHog settings.

### Open questions for the user

1. Which provider hosts the server? It stays unverified until the user confirms; do not edit `PROJECT_BIBLE.md`/`DATABASE.md` on a guess.
2. Off-server backup destination, who owns the `age` private key, and approval to enable the nightly timer (see `docs/BACKUP.md`).
3. Should earlier commits that exposed host details in public Git history be rewritten (force-push), or accepted? Rewriting needs the owner's explicit approval.
4. Is the optional backend release (token-logging change only) wanted, or should it wait for the next real backend change?

## Required release configuration

Flutter production builds require all of the following compile-time values:

| Target | Required Dart define | Production value/source |
| --- | --- | --- |
| Web and Android | `MUSHUKISTAN_API_BASE_URL` | `https://api.mushukistan.uz/api/v1/` |
| Web | `MUSHUKISTAN_GOOGLE_CLIENT_ID` | Web application OAuth client ID from the operator's secure configuration |
| Android | `MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID` | The same Web application OAuth client ID used by the backend |

Set the OAuth value in the current PowerShell session without adding it to Git:

```powershell
$env:MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID = '<production-web-oauth-client-id>'
```

Production backend configuration remains in the server-side `.env`. At minimum
it must contain the production database/JWT/Resend/R2 values documented in
`infrastructure/README.md`, plus `GOOGLE_OAUTH_CLIENT_ID`. The backend value must
accept the same Web OAuth client ID embedded in both Flutter targets. Android
ID tokens can carry the Android OAuth client as `azp`, and the backend requires
`azp` to be allowed too, so list both IDs, comma-separated:
`GOOGLE_OAUTH_CLIENT_ID=<web-client-id>,<android-client-id>`. A rejected
`aud`/`azp` is logged as `google_token_audience_rejected` /
`google_token_azp_rejected`.

Google Cloud must have:

- a Web OAuth client whose authorized JavaScript origin includes exactly
  `https://mushukistan.uz`;
- an Android OAuth client for package `uz.mushukistan.app` and the appropriate
  signing SHA-1;
- the upload-certificate SHA-1 for locally installed upload-signed release
  builds, and the Play App Signing certificate SHA-1 for Play-distributed
  builds when those certificates differ.

The pinned `google_sign_in` Android implementation does not use a
`google-services.json` file in this repository, so Dart initialization must pass
the Web application client ID as `serverClientId`.

## Pre-release checks

1. Record `git status --short --branch`, `git rev-parse HEAD`, and all local
   changes. Do not overwrite unrelated worktree changes.
2. Review `docs/`, Compose/Nginx configuration, Flutter environment providers,
   auth code, Android manifest/Gradle configuration, signing files, package ID,
   and `pubspec.yaml` version.
3. In Google Play Console, confirm that the `versionCode` in `pubspec.yaml` has
   never been uploaded. Increment only the build number (`+N`) when required.
4. Verify `frontend/android/key.properties` has `storeFile`, `storePassword`,
   `keyAlias`, and `keyPassword`, and that `storeFile` points to the upload
   keystore. The Gradle release configuration deliberately fails when any of
   these inputs are missing.
5. Run the relevant backend and Flutter automated tests and static analysis.

## Canonical production web build

Clean stale Flutter output once before the final web build:

```powershell
Set-Location frontend
flutter clean
Set-Location ..
.\frontend\tool\build_production.ps1 -Target Web
```

The script executes this release build and verifies the generated JavaScript:

```powershell
flutter build web --release `
  --no-web-resources-cdn `
  --dart-define=MUSHUKISTAN_API_BASE_URL=https://api.mushukistan.uz/api/v1/ `
  --dart-define=MUSHUKISTAN_GOOGLE_CLIENT_ID=$env:MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID
```

Do not run a later plain `flutter build web --release`; it would omit mandatory
Google configuration and could switch CanvasKit back to its remote CDN. The
`--no-web-resources-cdn` flag keeps the CanvasKit JavaScript/WebAssembly files
on the Mushukistan origin, which is required for reliable Safari/WebKit startup.
Inspect the final `frontend/build/web/main.dart.js` for the production API URL
and configured client ID, confirm `frontend/build/web/flutter_bootstrap.js`
contains `"useLocalCanvasKit":true`, the pre-Flutter first-frame/failure hooks,
and legacy Flutter service-worker retirement, and reject localhost/emulator
URLs before deployment. Mushukistan does not provide offline mode, and the web
bootstrap does not register a new service worker. The retirement step removes
service workers left by older Flutter builds and reloads once if an old worker
still controls the page.

The application shell and its non-hashed executable files form one release
unit. Nginx sends `no-store` for `index.html`, `flutter_bootstrap.js`,
`main.dart.js`, and `version.json`, and requires revalidation for JavaScript,
JSON, WebAssembly, and local CanvasKit files. Any Cloudflare cache rule must
honor or be at least as strict as these origin headers for those paths. Do not
add an edge rule that caches HTML or `main.dart.js` across releases.

Uploaded media has unique object keys and may keep its one-year immutable cache
header. Remote-image views retry once with a session-specific query only after
an image from `media.mushukistan.uz` fails, so a bad response held in a
browser's media cache can recover without clearing site data. Other hosts are
never given a retry query. This retry does not provide offline media.

Production cache audit (2026-10-04): successful media objects return
`Cache-Control: public, max-age=31536000, immutable` from R2 object metadata.
Before the Cloudflare correction, missing media returned `404` with
`Cache-Control: max-age=14400` and repeat requests were edge cache hits. The
operator then enabled a Cache Response Rule for errors, set Browser Cache TTL
to Respect Existing Headers, and purged the media hostname. A live check
confirmed a successful `200` retained the immutable header and a deliberately
missing `404` returned `Cache-Control: no-store` with `cf-cache-status: BYPASS`
on two consecutive requests.

Keep a Cloudflare Cache Response Rule with expression
`(http.host eq "media.mushukistan.uz" and http.response.code ge 400)`. Set the
`no-store` Cache-Control directive with **Cloudflare only off**, and remove any
`max-age`, `s-maxage`, `public`, `immutable`, or `stale-if-error` directives on
matching responses. Place the rule after any broader Cache Response Rules.
Add a Cache Rule matching `http.host eq "media.mushukistan.uz"` with cache
eligibility **Eligible for cache** and Browser TTL **Respect origin** (or use
zone-wide Browser Cache TTL **Respect Existing Headers** if appropriate). This
keeps the R2 one-year header on successful media and prevents Cloudflare from
inserting a four-hour browser lifetime on errors. Purge known
cached error URLs individually (including their query strings), rather than
purging the full media hostname. A status-only purge is not available; unknown
cached error URLs must expire unless they can be identified in logs. Then
verify repeated missing-object requests are not edge hits and successful
objects retain their immutable header.

## Database backup and migration gate

On the production VPS, before any migration or container replacement:

1. Record `docker exec mushukistan-backend alembic current` and
   `docker exec mushukistan-backend alembic heads`.
2. Create a timestamped custom-format logical backup outside the Docker volume:

   ```bash
   mkdir -p /root/mushukistan-backups
   docker exec mushukistan-db sh -c \
     'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' \
     > /root/mushukistan-backups/mushukistan-YYYYMMDD-HHMMSS.dump
   test -s /root/mushukistan-backups/mushukistan-YYYYMMDD-HHMMSS.dump
   ```

3. List pending repository migrations. Never reset, recreate, or remove the
   production database or its `mushukistan_postgres_data` volume.
4. Apply `alembic upgrade head` only when the deployed code has a newer head,
   then record the resulting revision.

## Notification deployment requirements (future release)

This notification code is not deployed by this implementation task. Before building Android with push, provision a Firebase project with an Android app whose package ID is `uz.mushukistan.app`. Download that app's public Firebase configuration as `frontend/android/app/google-services.json`; it is ignored by Git. Android builds without this file keep FCM disabled and still support the in-app inbox. Push-enabled builds use `--dart-define=ENABLE_ANDROID_PUSH=true` and fail if the file is missing. Do not invent values or commit generated Firebase files. Web builds do not use Firebase Messaging and keep the in-app inbox without browser push.

Create a Firebase Admin service account with messaging permission. Store its JSON outside Git, readable only by the deployment account, and set `FIREBASE_CREDENTIALS_HOST_PATH` to its absolute host path. Set `FIREBASE_PROJECT_ID` and a stable 32-byte URL-safe Fernet `PUSH_TOKEN_ENCRYPTION_KEY` in the private production environment. Losing or rotating this key without a re-encryption plan makes stored device tokens unreadable. Never log or commit the service account or key. The backend and worker mount the service account read-only at `/run/secrets/firebase-admin.json` through `docker-compose.notifications.yml`.

Back up the database, apply forward Alembic migration `20261007_0025`, then activate a backend/web release and the worker from the same commit/image. The worker is enabled with the `notifications` Compose profile and the notification overlay, for example `docker compose --profile notifications -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.notifications.yml up -d --build`. Verify `docker compose ... config` first, then verify backend health, worker startup, inbox API authorization, and a controlled FCM send. The worker uses existing PostgreSQL, polls every 30 seconds, claims jobs with a two-minute lease, and tries each delivery at most four times (initial, then 1, 5, and 30 minute delays). No Redis or background location service is needed. Roll back the backend and worker together; migration rollback requires separate data review because notification rows can be lost.

## Website deployment

### Public homepage release addition

Build the static homepage from reviewed source before assembling a **new**
versioned release directory:

```powershell
python website/build.py
python -m unittest discover -s website -p 'test_*.py' -v
node website/test_interactions.js
python website/tool/check_flutter_bundle.py frontend/build/web
python website/tool/check_nginx_http.py --flutter frontend/build/web --website website/dist --report .data/nginx-http.json
```

The release must contain both complete, independently built directories:
`frontend/build/web` mounted read-only at `/usr/share/nginx/html`, and
`website/dist` mounted read-only at `/var/www/landing`. The root `/` and the
localized `/en/` and `/uz/` are exact Nginx routes; `/landing-assets/` is a
separate static namespace. Flutter stays at its existing root route structure:
`/feed`, `/map`, shared post/profile links, authentication, and Flutter legal
routes continue through its fallback. `/privacy`, `/child-safety`, and
`/delete-account` keep their existing static behavior. The new homepage does
not change the API, media, database, Google Sign-In origin, Flutter bootstrap,
or CanvasKit layout. The web manifest launches at `/feed`.

Integrate the homepage against the exact deployed source commit by
reviewing the Git diff, resolving any overlap in a new integration worktree,
and running website tests and relevant Flutter tests. Rebuild both outputs from
the integrated commit. Do not copy old Flutter `index.html`, `main.dart.js`, or
CanvasKit files into the new release; keep the validated Flutter build together.
Run Compose configuration validation and Nginx syntax validation against the
new directory, then check an isolated preview or staging instance before the
active release is switched. Unfinished notification UI work must stay outside
the release. A homepage-only release is safe when its base contains all deployed
functionality; compare the deployed source archive, image revision, and relevant
source hashes with that base. The isolated HTTP harness uses disposable Docker
containers, random localhost ports, and a generated test certificate. It needs
Python's `cryptography` package and the `nginx:1.27-alpine` and
`python:3.13-slim` images. It tests the production configuration and exact built
artifacts, including proxies, security headers, cache behavior, and deep links.

Before switching the active release, verify `/`, `/en/`, `/uz/`, `/feed`,
`/map`, shared `/posts/:id`, `/lost-pets/:id`, `/adoption-posts/:id`, and
`/users/:id` links; `/login`, `/register`, and `/verify-email`; the three public
legal/account pages; `/api/` and `/media/`; locale links, both themes, mobile
navigation, robots and sitemap, SEO metadata, and PWA launch from the installed
app. Test Google Sign-In with the real production OAuth configuration only in
an authorized release window. Confirm Cloudflare respects `no-store` on
homepage HTML and the Flutter shell and immutable caching on hashed landing
assets. Submit the sitemap in Google Search Console only after ownership is
verified there; record the actual result.

Rollback is a release-directory switch back to the previously validated
Flutter bundle, Nginx config, Compose files, and artifact mounts as one set.
Do not remove the database or media volumes. No migration is needed for the
homepage. Record the old and new release identifiers and recheck `/` and
`/feed` after rollback.

Use the existing production Compose project and Nginx/TLS setup. Preserve the
active `.env`, named PostgreSQL/media volumes, `/etc/letsencrypt`, R2 settings,
and domains. Copy only the reviewed release source, the single final
`frontend/build/web` artifact, and the final `website/dist` artifact into a new
versioned release directory, preserve its `.env`, and validate both artifacts
before switching the active Compose project to that directory. Preserve the
active notification overlays and backend/worker image pins as well. Never rebuild
or copy individual web files inside the directory currently bind-mounted by
Nginx: doing so can expose a
mixed shell, Dart bundle, and renderer asset set. Then run from the new release:

```bash
docker compose --profile notifications -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.notifications.yml -f docker-compose.notification-release.yml config --quiet
docker compose --profile notifications -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.notifications.yml -f docker-compose.notification-release.yml up -d --no-deps --no-build --force-recreate nginx
```

The example includes the currently deployed notification profile, credential
mount overlay, and private release image-pin overlay. Use the exact active
overlay set recorded from the Nginx container's Compose labels. Do not replace
the backend, worker, or database for this static homepage change. Save their
container IDs before switching and assert the IDs are identical afterwards.
Validate the staged configuration with `nginx -t` in a disposable container
using the existing Docker network and read-only TLS/config/artifact mounts,
without publishing ports. Keep the previous versioned release intact.

Run the read-only public HTTPS gate immediately after the Nginx switch:

```powershell
python website/tool/check_production_http.py --flutter frontend/build/web --website website/dist --report .data/production-http.json
```

This compares public response hashes with the complete validated artifacts,
checks locale redirects, cache/security headers, API health, and notification
API authentication. It does not log in, create data, or bypass TLS validation.
If an important check fails, switch only Nginx back from the previous directory
with the same overlay set and the same `--no-deps --no-build` command, then
verify the old bundle, health endpoints, and retained container IDs.

After deployment, inspect container health/logs and the real HTTPS site. Check
the registration and login screens, Google button initialization, email auth,
session restore/refresh/logout, feed, map, profile, observations, places,
media, likes/comments where credentials permit, and browser console/network
errors. Report uncompleted interactive OAuth or authenticated flows as
`NOT VERIFIED`, never as working.

## Website-only visual refinement

When a release changes only `website/` and documentation, preserve the complete
deployed `frontend/build/web` directory byte-for-byte. Do not rebuild Flutter or
copy individual shells, bundles, manifests, or CanvasKit files from another
revision. Record the active release commit and Nginx mount paths, hash every
Flutter file, and compare those hashes with the candidate release before and
after the Nginx switch. This is an explicit alternative to the paired rebuild
above for a verified static website-only change.

Run the static build, all website unit/interaction tests, screenshot publication
checks, the browser gate in `website/tool/check_browser.py`, and the isolated
production Nginx HTTP gate against the preserved Flutter bundle. The screenshot
privacy/rights review and repeatable processing recipe live in
`website/SCREENSHOTS.md`. Original screenshots stay in ignored local storage and
must not enter the source archive, generated site, or production release.

Assemble a new versioned release with reviewed Git source, the new complete
`website/dist`, and the complete preserved Flutter artifact. Retain private
environment, notification overlays/image pins, TLS, named volumes, and unrelated
service configurations. Compare resolved Compose configurations without logging
secrets; only Nginx artifact/config bind paths may change. Validate the staged
Nginx config with its real read-only mounts, preserve the old release and a
database backup as required above, then recreate **only Nginx** using the exact
active overlay set and `--no-deps --no-build --force-recreate nginx`.

Immediately run the public HTTPS artifact gate, production browser gate, API and
media smoke tests, and service/log review. Confirm protected containers retain
their IDs/images/start times. If an important check fails, switch Nginx back to
the retained release and verify the original artifact hashes/routes/health. No
migration, database restore, worker replacement, or backend deployment is needed
for this static refinement. Keep before/after browser captures with the release
record and mark credential-dependent or real-device scenarios NOT VERIFIED.

## Canonical production AAB build

Do not clean or rebuild web output after it has passed verification. Build the
Android target separately:

```powershell
.\frontend\tool\build_production.ps1 -Target Android
```

The script executes:

```powershell
flutter build appbundle --release `
  --dart-define=MUSHUKISTAN_API_BASE_URL=https://api.mushukistan.uz/api/v1/ `
  --dart-define=MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID=$env:MUSHUKISTAN_GOOGLE_WEB_CLIENT_ID
```

The final artifact is
`frontend/build/app/outputs/bundle/release/app-release.aab`. Inspect it with
Bundletool/Android SDK tooling for package ID, version name/code, manifest, and
signing certificate. Also inspect the AOT libraries/resources for the production
API and Google server client configuration and reject localhost/emulator URLs.

## Final acceptance record

Record the Git commit, changed files, exact commands, production URLs, database
backup and Alembic revisions, website/auth/smoke/runtime results, AAB path/size,
package/version/signing/config results, and automated tests. Mark each important
flow `VERIFIED`, `FAILED`, or `NOT VERIFIED`.


## Automatic notification release

Use an isolated integration worktree descended from the exact active web
release, preserving homepage/showcase/loading-icon changes. The completed
notification settings prerequisite is `1477900` (equivalent integrated patch
`3f0838d`), followed by `2412679` and reviewed rollout fixes. Keep main and
other worktrees intact; do not push or publish as part of a test APK release.

The automatic-default rollout uses the existing `20261007_0025` schema.
Do not run Alembic upgrades on this release. Override the backend image's
default migration/startup command in the private release overlay with
`["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]`.
Backend and worker use the same immutable new image/revision; retain old
images, environment, Firebase credential mounts, and token encryption key.
Record Alembic current/head, preserve and validate a custom-format backup,
validate Compose and staged Nginx, then replace backend/worker and the Web
release together without recreating PostgreSQL or its volumes. Drain/freeze
the old worker with no sending jobs before replacement; never run old/new
workers simultaneously. Event/device unique keys and retry state stay intact.
Physical FCM delivery remains best effort; an ambiguously acknowledged send
cannot be proven exactly once by database deduplication alone.

Run the focused notification/PostGIS tests, Flutter notification/location/
consent/routing/auth tests, and focused lint/analyze. Build complete Flutter
Web output using the canonical `-Target Web` script and production OAuth
configuration; validate local CanvasKit, startup protection and `/feed` PWA
launch. Build the unchanged static website and compare all hashes with the
active homepage; perform HTTP artifact/routing checks without a browser matrix.

For a signed physical-test APK, set the existing public production Google Web
client ID in the build session and use ignored owner signing/Firebase files:

```powershell
.\frontend\tool\build_production.ps1 -Target AndroidApk -EnableAndroidPush
```

The script passes the production API, `MUSHUKISTAN_GOOGLE_SERVER_CLIENT_ID`,
and `ENABLE_ANDROID_PUSH=true`; missing Firebase config fails the build.
Verify the generated APK package/version/certificate, merged manifest
notification and foreground location permissions, Firebase resources/project,
AOT API/OAuth values, file size and SHA-256. No background location permission
is allowed. An FCM-only Firebase project may differ from Google Sign-In's
project: this app explicitly supplies `serverClientId`, so do not replace the
production OAuth ID with an unrelated auto-generated Firebase Web ID.
Google Cloud must authorize the APK's signing SHA-1 for `uz.mushukistan.app`
in the project owning that server client; console allowlisting and actual
device Google authentication remain manual checks where access is unavailable.

Android 13+ can report denied before the first OS prompt; the app tracks its
one-time disclosure marker and does not repeatedly prompt. Failed private-point
deletion retries every 30 seconds only while foreground, without fetching GPS.
Pausing, logout and account changes cancel that retry; the next authenticated
launch/resume also retries. Existing clients' explicit save-point requests
remain compatible, while new automatic uploads require their separate consent
and expected-account guard.

After activation check HTTPS artifacts/routes/homepage, API health, inbox,
preferences, registration/unregistration and consent/radius behavior using
temporary controlled accounts; delete only those accounts afterward. Do not
send synthetic notifications to real users. Inspect worker/backend logs and
retained database identity. Keep a complete rollback directory/config and old
backend/worker image pins; rollback code and web as one set without restoring
or replacing data. Normalized category values are not undone by code rollback.
Share the new APK only after production gates pass; if the backend is rolled
back later, stop testing that new APK until its compatible API is restored.
The owner confirms real-device receipt, permission behavior, deep links and
Google authentication; backend acceptance/send success is not proof of receipt.

## Feedback and Telegram notifications

Users send feedback from Profile -> Feedback (`POST /api/v1/feedback`, see
`docs/API.md`). Each stored submission triggers a best-effort Telegram message to
the developer. Configure it in the backend `.env` (never commit real values):

| Variable | Purpose |
| --- | --- |
| `TELEGRAM_BOT_TOKEN` | Bot token from @BotFather |
| `TELEGRAM_FEEDBACK_CHAT_ID` | Destination chat id (message the bot once, then read `getUpdates`) |
| `FEEDBACK_RATE_LIMIT_PER_HOUR` | Per-user cap, default `3` |

If either Telegram value is empty, feedback is still stored and the notification
is skipped. Telegram failures are logged (exception type and status only, never
the token) and never affect the user's submission. Deploying requires the normal
`alembic upgrade head` for revision `20261013_0026`.

Test locally without real credentials:

1. Start the local stack (`docker compose -f docker-compose.yml -f docker-compose.local.yml up -d`)
   and open the app, sign in, and use Profile -> Feedback.
2. Check storage: `docker exec mushukistan-db psql -U <db user> -d <db name> -c "select category, left(message, 40), platform, created_at from feedback order by created_at desc limit 5"`.
3. Run backend tests: `pytest tests/test_feedback.py` (HTTP, validation, rate limit,
   Telegram formatting/failure tests use mocks; the repository test needs
   `RUN_DB_INTEGRATION_TESTS=1` and `TEST_DATABASE_URL`).
4. For a real Telegram check, set the two variables to a personal test bot and chat.

