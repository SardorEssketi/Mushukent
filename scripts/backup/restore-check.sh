#!/usr/bin/env bash
# Restore an encrypted backup into a DISPOSABLE scratch PostGIS container and report what is in
# it. It can never touch production: it always starts its own container (no published ports,
# random password, removed afterwards) and has no option to target another database.
#
#   restore-check.sh --file mushukistan-nightly-...dump.age --identity /path/to/age-identity.txt [--keep]
#
# The private age identity is owned by the operator and is NEVER stored on the server.
# Run this on the operator workstation (or any scratch machine with Docker and age).
set -euo pipefail

DOCKER="${DOCKER_BIN:-docker}"
IMAGE="${POSTGIS_IMAGE:-postgis/postgis:15-3.4}"
file=""; identity=""; keep=0
die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --file) file="${2:?--file needs a path}"; shift 2 ;;
    --identity) identity="${2:?--identity needs a path}"; shift 2 ;;
    --keep) keep=1; shift ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[ -f "$file" ] || die "--file is required and must exist"
[ -f "$identity" ] || die "--identity is required and must exist"
command -v age >/dev/null || die "age is not installed"
[ "$(head -c 21 "$file")" = "age-encryption.org/v1" ] || die "$file is not an age-encrypted file"
if [ -f "$file.sha256" ]; then (cd "$(dirname "$file")" && sha256sum -c "$(basename "$file").sha256") || die "checksum mismatch"; fi

name="mushukistan-restore-check-$(date -u +%Y%m%dT%H%M%SZ)-$$"
pass="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 24)"
cleanup() { [ "$keep" -eq 1 ] || $DOCKER rm -f "$name" >/dev/null 2>&1 || true; }
trap cleanup EXIT

$DOCKER run -d --rm --name "$name" -e POSTGRES_PASSWORD="$pass" -e POSTGRES_USER=restore -e POSTGRES_DB=restore "$IMAGE" >/dev/null
for _ in $(seq 1 60); do
  $DOCKER exec "$name" pg_isready -U restore -d restore >/dev/null 2>&1 && break
  sleep 2
done
sleep 3
$DOCKER exec "$name" psql -U restore -d restore -qc 'create database restore_test' >/dev/null
$DOCKER exec "$name" psql -U restore -d restore_test -qc 'create extension if not exists postgis' >/dev/null
age -d -i "$identity" "$file" \
  | $DOCKER exec -i "$name" pg_restore -U restore -d restore_test --no-owner --no-privileges --exit-on-error
echo "restore completed without errors"
$DOCKER exec "$name" psql -U restore -d restore_test -Atc "select 'alembic_version', version_num from alembic_version"
for t in users posts lost_pets adoption_posts comments; do
  $DOCKER exec "$name" psql -U restore -d restore_test -Atc "select '$t', count(*) from $t"
done
[ "$keep" -eq 1 ] && echo "scratch container kept: $name (remove with: $DOCKER rm -f $name)"
echo "RESTORE CHECK OK"
