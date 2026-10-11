# Production release procedure

This is the canonical release procedure for the Mushukistan website and Google
Play Android App Bundle. Run commands from the repository root unless a step
says otherwise. Never commit `.env`, `frontend/android/key.properties`, a
keystore, or any service-account credentials.

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
accept the same Web OAuth client ID embedded in both Flutter targets.

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
localized `/ru/` and `/uz/` are exact Nginx routes; `/landing-assets/` is a
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

Before switching the active release, verify `/`, `/ru/`, `/uz/`, `/feed`,
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
