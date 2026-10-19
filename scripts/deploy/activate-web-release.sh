#!/usr/bin/env bash
# Switch ONLY the Nginx container to a staged release directory (run ON the server).
# This is the "web / static release" activation from docs/DEPLOYMENT.md. It never
# touches the backend, worker, database, volumes or any .env file.
#
#   activate-web-release.sh <release-name|abs-path>                       # dry run
#   activate-web-release.sh <release> --execute --backup-file FILE.dump   # real switch
#
# Dry run is the default: every check runs, nothing changes. --execute additionally
# needs a recent verified backup and a typed confirmation on a terminal (ssh -t).
# Re-running for the already-active release is a no-op that only re-checks.
# Rollback = run the printed rollback command (or this script for the old release).
set -euo pipefail

DOCKER="${DOCKER_BIN:-docker}"
REL_ROOT="${REL_ROOT:-/opt/mushukistan-releases}"
PROJECT="mushukistan"
NGINX_CONTAINER="${NGINX_CONTAINER:-mushukistan-nginx}"
DB_CONTAINER="${DB_CONTAINER:-mushukistan-db}"
API_URL="https://api.mushukistan.uz/api/v1/"
SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
VERIFY="${VERIFY_SCRIPT:-$SELF_DIR/verify-public.sh}"
MAX_BACKUP_AGE_MIN="${MAX_BACKUP_AGE_MIN:-720}"

die() { echo "ERROR: $*" >&2; exit 1; }
ok()  { echo "ok    $*"; }

target=""; execute=0; backup=""
while [ $# -gt 0 ]; do
  case "$1" in
    --execute) execute=1; shift ;;
    --backup-file) backup="${2:?--backup-file needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    -*) die "unknown argument: $1" ;;
    *) [ -z "$target" ] || die "only one release may be given"; target="$1"; shift ;;
  esac
done
[ -n "$target" ] || die "release directory required (see --help)"
REL_ROOT="$(cd "$REL_ROOT" 2>/dev/null && pwd)" || die "release root not found: $REL_ROOT"
case "$target" in /*) REL="$target" ;; *) REL="$REL_ROOT/$target" ;; esac
REL="$(cd "$REL" 2>/dev/null && pwd)" || die "release directory not found: $target"
case "$REL" in "$REL_ROOT"/*) ;; *) die "release must live under $REL_ROOT" ;; esac
rel_name="$(basename "$REL")"

label() { $DOCKER inspect -f "{{index .Config.Labels \"$1\"}}" "$NGINX_CONTAINER"; }

echo "== 1. active deployment (read from the running Nginx container labels)"
$DOCKER inspect "$NGINX_CONTAINER" >/dev/null 2>&1 || die "$NGINX_CONTAINER not found; refusing to guess the active release"
[ "$(label com.docker.compose.project)" = "$PROJECT" ] || die "Nginx is not in Compose project '$PROJECT'"
active_dir="$(label com.docker.compose.project.working_dir)"
active_files="$(label com.docker.compose.project.config_files)"
[ -n "$active_dir" ] && [ -n "$active_files" ] || die "active release labels are empty"
ok "active release : $active_dir"
ok "active files   : $active_files"

echo "== 2. staged release contents"
for f in docker-compose.yml docker-compose.prod.yml .env infrastructure/nginx/default.conf \
         frontend/build/web/index.html frontend/build/web/main.dart.js \
         frontend/build/web/flutter_bootstrap.js website/dist/index.html; do
  [ -f "$REL/$f" ] || die "missing $REL/$f"
done
[ -d "$REL/frontend/build/web/canvaskit" ] || die "missing frontend/build/web/canvaskit (local CanvasKit)"
ok "required files present"
grep -qF "$API_URL" "$REL/frontend/build/web/main.dart.js" || die "main.dart.js lacks $API_URL"
if grep -qE 'http://(localhost|10\.0\.2\.2|127\.0\.0\.1)' "$REL/frontend/build/web/main.dart.js"; then
  die "main.dart.js contains a development API host"
fi
grep -qF '"useLocalCanvasKit":true' "$REL/frontend/build/web/flutter_bootstrap.js" || die "CanvasKit is not local"
ok "web bundle uses the production API and local CanvasKit"

# Names only; values are never read into output.
keys() { grep -E '^[A-Za-z_][A-Za-z0-9_]*=' "$1" | cut -d= -f1 | sort -u; }
if [ -f "$active_dir/.env" ]; then
  missing="$(comm -23 <(keys "$active_dir/.env") <(keys "$REL/.env") | tr '\n' ' ')"
  [ -z "$missing" ] || die "new .env lacks keys present in the active .env: $missing"
  ok ".env key names cover the active .env (values not compared or printed)"
else
  echo "WARN  cannot read $active_dir/.env; .env key comparison skipped"
fi

echo "== 3. exact active overlay set, mapped into the staged release"
dc=("$DOCKER" compose)
profile_flag=""
if [ -n "$($DOCKER ps -q --filter "label=com.docker.compose.project=$PROJECT" --filter "label=com.docker.compose.service=notification-worker")" ]; then
  dc+=(--profile notifications)
  profile_flag=" --profile notifications"
  ok "notification-worker is running: using the notifications profile"
fi
IFS=',' read -r -a files <<< "$active_files"
rollback_flags=""
for f in "${files[@]}"; do
  b="$(basename "$f")"
  [ -f "$REL/$b" ] || die "overlay $b is used by the active deployment but missing in $REL (copy the private overlay from $active_dir)"
  dc+=(-f "$REL/$b")
  rollback_flags+=" -f $f"
done
ok "compose files: $(for f in "${files[@]}"; do basename "$f"; done | tr '\n' ' ')"
(cd "$REL" && "${dc[@]}" config --quiet) || die "docker compose config failed"
ok "docker compose config is valid (output not printed: it contains secrets)"

echo "== 4. Nginx syntax check in a disposable container (no ports published)"
net="$($DOCKER inspect -f '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$NGINX_CONTAINER" | awk '{print $1}')"
image="$($DOCKER inspect -f '{{.Config.Image}}' "$NGINX_CONTAINER")"
[ -n "$net" ] && [ -n "$image" ] || die "could not determine Nginx network/image"
$DOCKER run --rm --pull=never --network "$net" \
  -v "$REL/infrastructure/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro" \
  -v "$REL/frontend/build/web:/usr/share/nginx/html:ro" \
  -v "$REL/website/dist:/var/www/landing:ro" \
  -v /etc/letsencrypt:/etc/letsencrypt:ro \
  -v "$REL/infrastructure/certbot/www:/var/www/certbot:ro" \
  "$image" nginx -t || die "nginx -t failed for the staged release"
ok "nginx -t passed on network $net"

snapshot() { $DOCKER ps -a --filter "label=com.docker.compose.project=$PROJECT" --format '{{.Names}} {{.ID}}' | sort; }
before="$(snapshot)"
echo "== 5. container IDs before"
echo "$before"

rollback_cmd="cd $active_dir && $DOCKER compose$profile_flag$rollback_flags up -d --no-deps --no-build --force-recreate nginx"
switch_cmd="cd $REL && ${dc[*]} up -d --no-deps --no-build --force-recreate nginx"

if [ "$REL" = "$active_dir" ]; then
  echo "== $rel_name is already the active release: nothing to switch (idempotent)"
  exec bash "$VERIFY" --flutter-dir "$REL/frontend/build/web"
fi

echo "== 6. plan"
echo "switch   : $switch_cmd"
echo "rollback : $rollback_cmd"

if [ "$execute" -ne 1 ]; then
  echo "DRY RUN complete: all checks passed, nothing was changed."
  echo "Next: create a backup (backup-db.sh), then re-run with --execute --backup-file <dump>."
  exit 0
fi

echo "== 7. execution gates"
[ -n "$backup" ] || die "--backup-file is required with --execute"
[ -s "$backup" ] || die "backup missing or empty: $backup"
[ -n "$(find "$backup" -mmin "-$MAX_BACKUP_AGE_MIN" 2>/dev/null)" ] || die "backup is older than ${MAX_BACKUP_AGE_MIN} minutes; take a fresh one"
entries="$($DOCKER exec -i "$DB_CONTAINER" pg_restore --list < "$backup" | wc -l)"
[ "$entries" -gt 10 ] || die "pg_restore --list on the backup shows $entries entries"
ok "backup $backup verified ($entries catalog entries)"
[ -t 0 ] || die "--execute needs an interactive terminal (ssh -t) so a human can confirm"
printf 'Type "ACTIVATE %s" to replace ONLY the production Nginx container: ' "$rel_name"
read -r answer
[ "$answer" = "ACTIVATE $rel_name" ] || die "confirmation did not match; nothing changed"

echo "== 8. switching Nginx"
(cd "$REL" && "${dc[@]}" up -d --no-deps --no-build --force-recreate nginx)
for _ in $(seq 1 30); do
  [ "$($DOCKER inspect -f '{{.State.Running}}' "$NGINX_CONTAINER" 2>/dev/null)" = "true" ] && break
  sleep 2
done

echo "== 9. post-switch checks"
after="$(snapshot)"
changed="$(diff <(echo "$before") <(echo "$after") | grep -E '^[<>]' | grep -v "$NGINX_CONTAINER" || true)"
[ -z "$changed" ] && ok "only $NGINX_CONTAINER changed container ID" || echo "WARN  unexpected container changes:"$'\n'"$changed"
if bash "$VERIFY" --flutter-dir "$REL/frontend/build/web"; then
  ok "public verification passed for $rel_name"
  echo "Done. Previous release $active_dir is untouched and kept for rollback."
else
  echo "FAILED public verification. Roll back ONLY Nginx with:" >&2
  echo "  $rollback_cmd" >&2
  exit 1
fi
