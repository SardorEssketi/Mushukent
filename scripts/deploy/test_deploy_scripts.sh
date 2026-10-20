#!/usr/bin/env bash
# Offline tests for scripts/deploy/*. Uses stub `docker` and `curl` executables and
# throwaway directories: it never contacts a server, Docker daemon, or the network.
#   bash scripts/deploy/test_deploy_scripts.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0; total=0

check() { # description, expected_exit(0|nonzero), output_must_contain(optional), command...
  local desc="$1" want="$2" needle="$3"; shift 3
  local out rc
  out="$("$@" 2>&1 </dev/null)"; rc=$?
  total=$((total+1))
  local good=1
  if [ "$want" = "0" ]; then [ $rc -eq 0 ] || good=0; else [ $rc -ne 0 ] || good=0; fi
  if [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$out"; then good=0; fi
  if [ $good -eq 1 ]; then echo "PASS  $desc"; else echo "FAIL  $desc (exit $rc)"; echo "$out" | tail -8 | sed 's/^/        /'; fails=$((fails+1)); fi
}

for s in remote-inspect backup-db activate-web-release verify-public package-release build-backend-image e2e_disposable; do
  check "syntax: $s.sh" 0 "" bash -n "$HERE/$s.sh"
done

# ---------- package-release.sh in a throwaway git repo ----------
R="$T/repo"; mkdir -p "$R/backend" "$R/frontend/build/web/canvaskit" "$R/website/dist"
( cd "$R" && git init -q && git config user.email t@t && git config user.name t \
  && echo x > backend/a.py && echo "KEY=1" > .env.example && git add -A && git commit -qm init )
printf 'const a="https://api.mushukistan.uz/api/v1/";' > "$R/frontend/build/web/main.dart.js"
printf '{"useLocalCanvasKit":true}' > "$R/frontend/build/web/flutter_bootstrap.js"
echo hi > "$R/website/dist/index.html"
export REPO_ROOT="$R"
P="$HERE/package-release.sh"
check "package: bad label rejected" nonzero "--label" bash "$P" --label 'bad label!'
check "package: ok" 0 "NOT UPLOADED" bash "$P" --label test
tarball="$(ls "$R"/release/*.tar.gz 2>/dev/null | head -1)"
check "package: tarball has manifest and no .env" 0 "RELEASE_MANIFEST.txt" bash -c "tar -tzf '$tarball'"
check "package: tarball contains no secret-like file" nonzero "" bash -c "tar -tzf '$tarball' | grep -E '(^|/)\.env$|key.properties|google-services'"
check "package: duplicate refused" nonzero "already exists" bash "$P" --label test
printf 'x="http://localhost:8000";"https://api.mushukistan.uz/api/v1/"' > "$R/frontend/build/web/main.dart.js"
check "package: dev host in bundle rejected" nonzero "development API host" bash "$P" --label dev
printf 'const a="https://api.mushukistan.uz/api/v1/";' > "$R/frontend/build/web/main.dart.js"
echo changed >> "$R/backend/a.py"
check "package: dirty tree refused" nonzero "uncommitted" bash "$P" --label dirty
check "package: dirty tree allowed explicitly" 0 "NOT UPLOADED" bash "$P" --label dirty --allow-dirty
# --source-only: no web artifacts needed or shipped (for releases that keep the live web files)
rm -rf "$R/frontend/build" "$R/website/dist"
check "package: normal mode needs the built web artifacts" nonzero "is missing" bash "$P" --label nosrc --allow-dirty
check "package: --source-only works without artifacts" 0 "SOURCE-ONLY release" bash "$P" --label srconly --allow-dirty --source-only
tb2="$(ls "$R"/release/*srconly.tar.gz | head -1)"
check "package: source-only archive contains no web artifacts" nonzero "" bash -c "tar -tzf '$tb2' | grep -E 'frontend/build/web|website/dist'"
check "package: source-only manifest says so" 0 "source_only=yes" bash -c "tar -xzOf '$tb2' --wildcards '*/RELEASE_MANIFEST.txt'"
unset REPO_ROOT

# ---------- stub binaries ----------
BIN="$T/bin"; mkdir -p "$BIN"
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
a="$*"
case "$a" in
  *'"/usr/share/nginx/html"'*) echo "$(cat "$STUB_STATE" 2>/dev/null || echo "$STUB_ACTIVE")/frontend/build/web" ;;
  *'"/var/www/landing"'*) echo "$(cat "$STUB_STATE" 2>/dev/null || echo "$STUB_ACTIVE")/website/dist" ;;
  *'"/etc/nginx/conf.d/default.conf"'*) echo "$(cat "$STUB_STATE" 2>/dev/null || echo "$STUB_ACTIVE")/infrastructure/nginx/default.conf" ;;
  compose*' up '*) [ -n "${STUB_UP_FAIL:-}" ] && exit 1; pwd > "$STUB_STATE" ;;
  *'Labels "com.docker.compose.project"}}'*) echo "${STUB_PROJECT:-mushukistan}" ;;
  *project.working_dir*) echo "$STUB_ACTIVE" ;;
  *config_files*) echo "$STUB_FILES" ;;
  *Networks*) echo "mushukistan_default " ;;
  *'.Config.Image'*) echo "nginx:1.27-alpine" ;;
  *'.State.Running'*) [ -n "${STUB_NGINX_DOWN:-}" ] && echo false || echo true ;;
  "ps -q"*) [ -n "${STUB_WORKER:-}" ] && echo c5c4aca7cade ;;
  "ps -a"*) printf 'mushukistan-nginx aaa111\nmushukistan-db bbb222\n' ;;
  "exec -i"*pg_restore*) seq 1 40 ;;
  *psql*) echo 123456 ;;
  *) : ;;
esac
exit 0
EOF
cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
# args include -o BODY -D HEADERS -w FORMAT URL
url="${@: -1}"; body=""; hdr=""
while [ $# -gt 0 ]; do case "$1" in -o) body="$2"; shift 2;; -D) hdr="$2"; shift 2;; *) shift;; esac; done
echo "curl $url" >> "$STUB_LOG"
code=200
case "$url" in
  http://*) code=301 ;;
  */docs) code=404 ;;
esac
[ -n "${STUB_FAIL_URL:-}" ] && [[ "$url" == *"$STUB_FAIL_URL" ]] && code=502
[ -n "$body" ] && printf 'bundle' > "$body"
[ -n "$hdr" ] && printf 'HTTP/2 %s\r\ncache-control: no-store, max-age=0\r\n' "$code" > "$hdr"
printf '%s' "$code"
EOF
chmod +x "$BIN/docker" "$BIN/curl"
export PATH="$BIN:$PATH" STUB_LOG="$T/stub.log" STUB_STATE="$T/stub.state"

# ---------- verify-public.sh ----------
: > "$STUB_LOG"
check "verify-public: all pass" 0 "ALL CHECKS PASSED" bash "$HERE/verify-public.sh"
STUB_FAIL_URL="/api/v1/health" check "verify-public: failing health detected" nonzero "SOME CHECKS FAILED" bash "$HERE/verify-public.sh"
mkdir -p "$T/fl"; printf 'other' > "$T/fl/main.dart.js"
check "verify-public: bundle hash mismatch detected" nonzero "SHA-256 differs" bash "$HERE/verify-public.sh" --flutter-dir "$T/fl"
printf 'bundle' > "$T/fl/main.dart.js"
check "verify-public: bundle hash match" 0 "matches local build" bash "$HERE/verify-public.sh" --flutter-dir "$T/fl"

# ---------- activate-web-release.sh ----------
ROOT="$T/rel"; ACT="$ROOT/20260101-aaaaaaa-active"; NEW="$ROOT/20260202-bbbbbbb-new"
mk() { # dir
  mkdir -p "$1/infrastructure/nginx" "$1/infrastructure/certbot/www" "$1/frontend/build/web/canvaskit" "$1/website/dist"
  : > "$1/docker-compose.yml"; : > "$1/docker-compose.prod.yml"; : > "$1/docker-compose.notification-release.yml"
  : > "$1/infrastructure/nginx/default.conf"; echo hi > "$1/website/dist/index.html"; echo i > "$1/frontend/build/web/index.html"
  printf 'x="https://api.mushukistan.uz/api/v1/"' > "$1/frontend/build/web/main.dart.js"
  printf '{"useLocalCanvasKit":true}' > "$1/frontend/build/web/flutter_bootstrap.js"
  printf 'A=1\nB=2\n' > "$1/.env"
}
mk "$ACT"; mk "$NEW"
export REL_ROOT="$ROOT" STUB_ACTIVE="$ACT"
export STUB_FILES="$ACT/docker-compose.yml,$ACT/docker-compose.prod.yml,$ACT/docker-compose.notification-release.yml"
export VERIFY_SCRIPT="$T/verify-ok.sh"; printf '#!/usr/bin/env bash\necho VERIFY-CALLED "$@"\n' > "$VERIFY_SCRIPT"
A="$HERE/activate-web-release.sh"

: > "$STUB_LOG"
check "activate: dry run passes" 0 "DRY RUN complete" bash "$A" 20260202-bbbbbbb-new
check "activate: dry run printed rollback to active release" 0 "rollback : cd $ACT" bash "$A" 20260202-bbbbbbb-new
check "activate: dry run never recreates anything" nonzero "" grep -E 'force-recreate|compose .* up ' "$STUB_LOG"
# --- TLS renewal webroot consistency (step 4b): warning only, never blocks ---
LEC="$T/le.conf"
printf '[renewalparams]\nauthenticator = webroot\nwebroot_path = %s,\n[[webroot_map]]\nmushukistan.uz = %s\n' "$NEW/infrastructure/certbot/www" "$NEW/infrastructure/certbot/www" > "$LEC"
LE_RENEWAL_CONF="$LEC" check "activate: renewal webroot == release ACME mount -> ok" 0 "renewal webroot equals the ACME directory" bash "$A" 20260202-bbbbbbb-new
printf '[renewalparams]\nauthenticator = webroot\nwebroot_path = /elsewhere,\n[[webroot_map]]\nmushukistan.uz = /elsewhere\n' > "$LEC"
LE_RENEWAL_CONF="$LEC" check "activate: webroot drift -> WARN with the exact remedy, dry run still succeeds" 0 "set-webroot.sh $NEW/infrastructure/certbot/www --execute" bash "$A" 20260202-bbbbbbb-new
printf '[renewalparams]\nauthenticator = standalone\n' > "$LEC"
LE_RENEWAL_CONF="$LEC" check "activate: standalone authenticator -> WARN, dry run still succeeds" 0 "not webroot: renewal will fail" bash "$A" 20260202-bbbbbbb-new
printf '      - /var/www/certbot:/var/www/certbot:ro\n' > "$NEW/docker-compose.prod.yml"
printf '[renewalparams]\nauthenticator = webroot\nwebroot_path = /var/www/certbot,\n[[webroot_map]]\nmushukistan.uz = /var/www/certbot\n' > "$LEC"
LE_RENEWAL_CONF="$LEC" check "activate: release mounting the stable /var/www/certbot matches a stable renewal webroot" 0 "renewal webroot equals the ACME directory this release mounts (/var/www/certbot)" bash "$A" 20260202-bbbbbbb-new
: > "$NEW/docker-compose.prod.yml"
check "activate: unknown release" nonzero "not found" bash "$A" nope
check "activate: release outside root refused" nonzero "must live under" bash "$A" "$T"
check "activate: no --backup-file refused" nonzero "--backup-file is required" bash "$A" 20260202-bbbbbbb-new --execute
echo dump > "$T/b.dump"
check "activate: execute without a terminal refused" nonzero "interactive terminal" bash "$A" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
check "activate: execute never recreated without confirmation" nonzero "" grep -E 'force-recreate' "$STUB_LOG"
: > "$T/empty.dump"
check "activate: empty backup refused" nonzero "missing or empty" bash "$A" 20260202-bbbbbbb-new --execute --backup-file "$T/empty.dump"
check "activate: already-active is idempotent" 0 "VERIFY-CALLED" bash "$A" 20260101-aaaaaaa-active
STUB_WORKER=1 check "activate: worker running -> notifications profile in switch and rollback" 0 "--profile notifications" bash "$A" 20260202-bbbbbbb-new
# Backend-only release layout seen in production: web/dist are symlinks to another release.
SYM="$ROOT/20260303-ccccccc-backend"; mk "$SYM"; rm -rf "$SYM/frontend/build/web" "$SYM/website/dist"
ln -s "$ACT/frontend/build/web" "$SYM/frontend/build/web"; ln -s "$ACT/website/dist" "$SYM/website/dist"
cp "$ACT/infrastructure/nginx/default.conf" "$SYM/infrastructure/nginx/default.conf"
if [ "$(readlink -f "$SYM/frontend/build/web")" = "$ACT/frontend/build/web" ]; then
  check "activate: symlinked release resolving to the served web is a no-op" nonzero "" grep -q force-recreate "$STUB_LOG"
  check "activate: dry run reports resolved web paths" 0 "web currently served from  : $ACT/frontend/build/web" bash "$A" 20260303-ccccccc-backend
fi
rm "$NEW/docker-compose.notification-release.yml"
check "activate: missing private overlay refused" nonzero "missing in" bash "$A" 20260202-bbbbbbb-new
: > "$NEW/docker-compose.notification-release.yml"; printf 'A=1\n' > "$NEW/.env"
check "activate: dropped .env key refused" nonzero "lacks keys" bash "$A" 20260202-bbbbbbb-new
printf 'A=1\nB=2\n' > "$NEW/.env"; printf 'x="http://localhost:8000/api/v1/https://api.mushukistan.uz/api/v1/"' > "$NEW/frontend/build/web/main.dart.js"
check "activate: dev API host in bundle refused" nonzero "development API host" bash "$A" 20260202-bbbbbbb-new
printf 'x="https://api.mushukistan.uz/api/v1/"' > "$NEW/frontend/build/web/main.dart.js"
STUB_PROJECT=other check "activate: wrong compose project refused" nonzero "not in Compose project" bash "$A" 20260202-bbbbbbb-new


# ---------- activate-web-release.sh --execute through a real pty ----------
if command -v script >/dev/null 2>&1 && script -qec true /dev/null >/dev/null 2>&1; then
  export NGINX_WAIT_TRIES=1
  rm -f "$STUB_STATE"; : > "$STUB_LOG"
  pty() { # phrase, then script args
    local phrase="$1"; shift
    printf '%s\n' "$phrase" | script -qec "bash $A $*" /dev/null
  }
  fresh() { printf 'dump' > "$T/b.dump"; rm -f "$STUB_STATE" "$NEW/PREVIOUS_STATE.txt"; : > "$STUB_LOG"; }
  fresh
  check "execute: wrong phrase aborts" nonzero "confirmation did not match" pty "nope" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
  check "execute: wrong phrase recreated nothing" nonzero "" grep -q force-recreate "$STUB_LOG"
  check "execute: no PREVIOUS_STATE before confirmation" nonzero "" test -f "$NEW/PREVIOUS_STATE.txt"
  fresh; touch -d '3 days ago' "$T/b.dump"
  check "execute: stale backup refused" nonzero "older than" pty "ACTIVATE 20260202-bbbbbbb-new" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
  fresh
  check "execute: success path" 0 "public verification passed" pty "ACTIVATE 20260202-bbbbbbb-new" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
  check "execute: recreated exactly nginx, no deps, no build" 0 "up -d --no-deps --no-build --force-recreate nginx" grep "force-recreate" "$STUB_LOG"
  check "execute: nothing else was recreated" nonzero "" grep -E "force-recreate (backend|db|notification)" "$STUB_LOG"
  check "execute: PREVIOUS_STATE records the rollback" 0 "previous_working_dir=$ACT" cat "$NEW/PREVIOUS_STATE.txt"
  check "execute: PREVIOUS_STATE has rollback command" 0 "rollback=cd $ACT" cat "$NEW/PREVIOUS_STATE.txt"
  check "execute: rerun is an idempotent no-op" 0 "VERIFY-CALLED" pty "x" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
  fresh
  STUB_UP_FAIL=1 check "execute: compose failure prints rollback" nonzero "Roll back ONLY Nginx" pty "ACTIVATE 20260202-bbbbbbb-new" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
  fresh
  STUB_NGINX_DOWN=1 check "execute: nginx not running prints rollback" nonzero "not running after the switch" pty "ACTIVATE 20260202-bbbbbbb-new" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
  fresh; printf '#!/usr/bin/env bash\necho VERIFY-FAILED; exit 1\n' > "$T/verify-bad.sh"
  VERIFY_SCRIPT="$T/verify-bad.sh" check "execute: failed public verification prints rollback" nonzero "Roll back ONLY Nginx" pty "ACTIVATE 20260202-bbbbbbb-new" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
  fresh
  check "execute: rollback command points at the previous directory" 0 "cd $ACT" bash "$A" 20260202-bbbbbbb-new
  unset NGINX_WAIT_TRIES
else
  echo "SKIP  pty execute tests (no usable 'script' command)"
fi
rm -f "$STUB_STATE"

# ---------- backup-db.sh ----------
export BACKUP_DIR="$T/backups"
check "backup: label required" nonzero "--label is required" bash "$HERE/backup-db.sh"
check "backup: dry run writes nothing" 0 "DRY RUN" bash "$HERE/backup-db.sh" --label t
check "backup: no dump created in dry run" nonzero "" bash -c "ls '$BACKUP_DIR'/*.dump"
check "backup: execute without a terminal refused" nonzero "interactive terminal" bash "$HERE/backup-db.sh" --label t --execute

echo; echo "$((total-fails))/$total passed"
exit "$fails"
