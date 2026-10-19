#!/usr/bin/env bash
# Build a versioned release tarball on the operator machine. Local only: it never
# contacts the server and never uploads anything.
#
#   scripts/deploy/package-release.sh --label NAME [--sha REV] [--allow-dirty]
#
# Contents: `git archive` of the committed source at REV (default HEAD), plus the
# already-built frontend/build/web and website/dist. Secrets are never included
# (.env, key.properties, keystores and Firebase files are untracked/ignored; the
# archive is also scanned for them). The release name is YYYYMMDD-<sha7>-<label>,
# the same convention as /opt/mushukistan-releases on the server.
# Output: release/<name>.tar.gz and a .sha256 (the release/ directory is gitignored).
set -euo pipefail

ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
API_URL="https://api.mushukistan.uz/api/v1/"
label=""; rev="HEAD"; allow_dirty=0

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="${2:?--label needs a value}"; shift 2 ;;
    --sha) rev="${2:?--sha needs a value}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$label" =~ ^[A-Za-z0-9._-]{1,40}$ ]] || die "--label is required (letters, digits, . _ - only, max 40)"
cd "$ROOT"

sha="$(git rev-parse --verify "$rev^{commit}")" || die "unknown revision $rev"
short="${sha:0:7}"
name="$(date +%Y%m%d)-$short-$label"

dirty="$(git status --porcelain --untracked-files=no)"
if [ -n "$dirty" ]; then
  [ "$allow_dirty" -eq 1 ] || die "tracked files have uncommitted changes, so the built artifacts may not match $short. Commit them or pass --allow-dirty (recorded in the manifest):
$dirty"
  echo "WARN: packaging with uncommitted tracked changes (recorded in the manifest)" >&2
fi
if [ "$rev" = "HEAD" ] || [ "$sha" = "$(git rev-parse HEAD)" ]; then :; else
  echo "WARN: $short is not HEAD; the built artifacts must come from $short" >&2
fi

web=frontend/build/web
[ -f "$web/main.dart.js" ] && [ -f "$web/flutter_bootstrap.js" ] || die "$web is missing: run .\\frontend\\tool\\build_production.ps1 -Target Web"
[ -f website/dist/index.html ] || die "website/dist is missing: run python website/build.py"
[ -d "$web/canvaskit" ] || die "$web/canvaskit is missing (CanvasKit must be local)"
grep -qF "$API_URL" "$web/main.dart.js" || die "main.dart.js lacks the production API URL"
grep -qE 'http://(localhost|10\.0\.2\.2|127\.0\.0\.1)' "$web/main.dart.js" && die "main.dart.js contains a development API host"
grep -qF '"useLocalCanvasKit":true' "$web/flutter_bootstrap.js" || die "flutter_bootstrap.js does not use local CanvasKit"

stage="$(mktemp -d)"; trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/$name"
git archive "$sha" | tar -x -C "$stage/$name"
mkdir -p "$stage/$name/frontend/build" "$stage/$name/website"
cp -R "$web" "$stage/$name/frontend/build/web"
cp -R website/dist "$stage/$name/website/dist"

js_sha="$(sha256sum "$web/main.dart.js" | cut -d' ' -f1)"
cat > "$stage/$name/RELEASE_MANIFEST.txt" <<EOF
name=$name
git_sha=$sha
packaged_at_utc=$(date -u +%FT%TZ)
uncommitted_tracked_changes=$([ -n "$dirty" ] && echo yes || echo no)
main_dart_js_sha256=$js_sha
EOF

forbidden="$(cd "$stage" && find "$name" \( -name '.env' -o -name '.env.*' -o -name 'key.properties' -o -name '*.jks' -o -name '*.keystore' -o -name 'google-services.json' -o -name 'firebase-admin*.json' -o -name 'service-account*.json' \) ! -name '.env.example' -print)"
[ -z "$forbidden" ] || die "secret-like files in the release:
$forbidden"

mkdir -p release
out="release/$name.tar.gz"
[ ! -e "$out" ] || die "$out already exists; choose another label"
tar -C "$stage" -czf "$out" "$name"
(cd release && sha256sum "$name.tar.gz" | tee "$name.tar.gz.sha256")
echo "Packaged $out ($(wc -c < "$out") bytes), main.dart.js sha256 $js_sha"
cat <<EOF

NOT UPLOADED. After the user approves, stage it (replace <server> with the SSH target
documented in docs/DEPLOYMENT.md):
  scp $out $out.sha256 <server>:/opt/mushukistan-releases/
  ssh <server> 'cd /opt/mushukistan-releases && sha256sum -c $name.tar.gz.sha256 && tar -xzf $name.tar.gz'
Then, on the server, copy the private files from the ACTIVE release into the new directory
(cp without overwriting anything in the active one): .env and docker-compose.notification-release.yml.
EOF
