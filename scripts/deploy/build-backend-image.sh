#!/usr/bin/env bash
# Build the backend image LOCALLY (never on the production VPS, which has 2 GB RAM and no
# swap) and save it as a tarball for `docker load` on the server. Local only: it never
# contacts the server and uploads nothing.
#
#   scripts/deploy/build-backend-image.sh [--sha REV] [--allow-dirty]
#
# Builds linux/amd64 (the VPS is x86_64) from `git archive REV backend`, so the image
# contains exactly the committed source. Tag: mushukistan-backend:<sha7>, the same
# convention as the private overlay's image pin. Output: release/mushukistan-backend-<sha7>.tar.gz
# and a .sha256 (the release/ directory is gitignored). The image carries no secrets: .env
# is never copied (the build context is the committed backend/ tree).
set -euo pipefail

ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/../.." && pwd)}"
DOCKER="${DOCKER_BIN:-docker}"
rev="HEAD"; allow_dirty=0
die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --sha) rev="${2:?--sha needs a value}"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
cd "$ROOT"
sha="$(git rev-parse --verify "$rev^{commit}")" || die "unknown revision $rev"
short="${sha:0:7}"
tag="mushukistan-backend:$short"

dirty="$(git status --porcelain --untracked-files=no -- backend)"
if [ -n "$dirty" ] && [ "$allow_dirty" -ne 1 ]; then
  die "backend/ has uncommitted changes; the image must match commit $short:
$dirty"
fi
git merge-base --is-ancestor "$sha" origin/main 2>/dev/null \
  || echo "WARN: $short is not contained in origin/main (release branch). Production releases come from a pushed main commit." >&2

# Context inside the (gitignored) .data/ with a relative path: a native Windows docker.exe cannot
# read an MSYS /tmp directory.
mkdir -p .data
ctx=".data/build-ctx-$short-$$"; rm -rf "$ctx"; mkdir -p "$ctx"; trap 'rm -rf "$ctx"' EXIT
git archive "$sha" backend | tar -x -C "$ctx"
$DOCKER build --platform linux/amd64 -t "$tag" "$ctx/backend"

heads="$($DOCKER run --rm --entrypoint alembic "$tag" heads 2>/dev/null | grep -c '(head)' || true)"
[ "$heads" = "1" ] || die "expected exactly one Alembic head in the image, found $heads"
echo "Alembic head in image: $($DOCKER run --rm --entrypoint alembic "$tag" heads 2>/dev/null | head -1)"

echo "Key dependency versions in this image (compare with production before shipping):"
$DOCKER run --rm --entrypoint pip "$tag" list 2>/dev/null | grep -iE '^(fastapi|starlette|pydantic|python-multipart|uvicorn|sqlalchemy|alembic) ' || true

mkdir -p release
out="release/mushukistan-backend-$short.tar.gz"
[ ! -e "$out" ] || die "$out already exists"
$DOCKER save "$tag" | gzip -9 > "$out"
(cd release && sha256sum "mushukistan-backend-$short.tar.gz" | tee "mushukistan-backend-$short.tar.gz.sha256")
echo "Saved $out ($(wc -c < "$out") bytes) as $tag"
cat <<EOF

NOT UPLOADED. After the user approves, one way to load it (loading adds a new tag; it does
not touch running containers):
  scp $out $out.sha256 <server>:/opt/mushukistan-releases/
  ssh <server> 'cd /opt/mushukistan-releases && sha256sum -c mushukistan-backend-$short.tar.gz.sha256 && gunzip -c mushukistan-backend-$short.tar.gz | docker load'
Then set both image pins in the new release's overlay to $tag (see docs/DEPLOYMENT.md, procedure B).
EOF
