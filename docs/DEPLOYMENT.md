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

## Website deployment

Use the existing production Compose project and Nginx/TLS setup. Preserve the
active `.env`, named PostgreSQL/media volumes, `/etc/letsencrypt`, R2 settings,
and domains. Copy only the reviewed release source and the single final
`frontend/build/web` artifact into a new versioned release directory, preserve
its `.env`, and validate the complete artifact before switching the active
Compose project to that directory. Never rebuild or copy individual web files
inside the directory currently bind-mounted by Nginx: doing so can expose a
mixed shell, Dart bundle, and renderer asset set. Then run from the new release:

```bash
docker compose -f docker-compose.yml -f docker-compose.prod.yml config --quiet
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d --build
```

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
