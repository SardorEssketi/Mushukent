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

for s in remote-inspect backup-db activate-web-release verify-public package-release; do
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
unset REPO_ROOT

# ---------- stub binaries ----------
BIN="$T/bin"; mkdir -p "$BIN"
cat > "$BIN/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
a="$*"
case "$a" in
  *'Labels "com.docker.compose.project"}}'*) echo "${STUB_PROJECT:-mushukistan}" ;;
  *project.working_dir*) echo "$STUB_ACTIVE" ;;
  *config_files*) echo "$STUB_FILES" ;;
  *Networks*) echo "mushukistan_default " ;;
  *'.Config.Image'*) echo "nginx:1.27-alpine" ;;
  *'.State.Running'*) echo true ;;
  "ps -q"*) : ;;
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
export PATH="$BIN:$PATH" STUB_LOG="$T/stub.log"

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
check "activate: unknown release" nonzero "not found" bash "$A" nope
check "activate: release outside root refused" nonzero "must live under" bash "$A" "$T"
check "activate: no --backup-file refused" nonzero "--backup-file is required" bash "$A" 20260202-bbbbbbb-new --execute
echo dump > "$T/b.dump"
check "activate: execute without a terminal refused" nonzero "interactive terminal" bash "$A" 20260202-bbbbbbb-new --execute --backup-file "$T/b.dump"
check "activate: execute never recreated without confirmation" nonzero "" grep -E 'force-recreate' "$STUB_LOG"
: > "$T/empty.dump"
check "activate: empty backup refused" nonzero "missing or empty" bash "$A" 20260202-bbbbbbb-new --execute --backup-file "$T/empty.dump"
check "activate: already-active is idempotent" 0 "VERIFY-CALLED" bash "$A" 20260101-aaaaaaa-active
rm "$NEW/docker-compose.notification-release.yml"
check "activate: missing private overlay refused" nonzero "missing in" bash "$A" 20260202-bbbbbbb-new
: > "$NEW/docker-compose.notification-release.yml"; printf 'A=1\n' > "$NEW/.env"
check "activate: dropped .env key refused" nonzero "lacks keys" bash "$A" 20260202-bbbbbbb-new
printf 'A=1\nB=2\n' > "$NEW/.env"; printf 'x="http://localhost:8000/api/v1/https://api.mushukistan.uz/api/v1/"' > "$NEW/frontend/build/web/main.dart.js"
check "activate: dev API host in bundle refused" nonzero "development API host" bash "$A" 20260202-bbbbbbb-new
printf 'x="https://api.mushukistan.uz/api/v1/"' > "$NEW/frontend/build/web/main.dart.js"
STUB_PROJECT=other check "activate: wrong compose project refused" nonzero "not in Compose project" bash "$A" 20260202-bbbbbbb-new

# ---------- backup-db.sh ----------
export BACKUP_DIR="$T/backups"
check "backup: label required" nonzero "--label is required" bash "$HERE/backup-db.sh"
check "backup: dry run writes nothing" 0 "DRY RUN" bash "$HERE/backup-db.sh" --label t
check "backup: no dump created in dry run" nonzero "" bash -c "ls '$BACKUP_DIR'/*.dump"
check "backup: execute without a terminal refused" nonzero "interactive terminal" bash "$HERE/backup-db.sh" --label t --execute

echo; echo "$((total-fails))/$total passed"
exit "$fails"
