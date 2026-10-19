#!/usr/bin/env bash
# Custom-format logical backup of the production database (run ON the server).
#
#   backup-db.sh --label NAME            # dry run: checks only, writes nothing
#   backup-db.sh --label NAME --execute  # asks for a typed confirmation, then dumps
#
# Writes only a NEW file under $BACKUP_DIR (never overwrites) and never touches the
# database or its volume. Verifies the dump with pg_restore --list and records a SHA-256.
# Documented in docs/DEPLOYMENT.md ("Database backup and migration gate").
set -euo pipefail

DOCKER="${DOCKER_BIN:-docker}"
DB_CONTAINER="${DB_CONTAINER:-mushukistan-db}"
BACKUP_DIR="${BACKUP_DIR:-/root/mushukistan-backups}"
label=""; execute=0

die() { echo "ERROR: $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
  case "$1" in
    --label) label="${2:?--label needs a value}"; shift 2 ;;
    --execute) execute=1; shift ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$label" =~ ^[A-Za-z0-9._-]{1,40}$ ]] || die "--label is required (letters, digits, . _ - only, max 40)"

[ "$($DOCKER inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" = "true" ] \
  || die "container $DB_CONTAINER is not running"

db_bytes="$($DOCKER exec "$DB_CONTAINER" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select pg_database_size(current_database())"')"
[[ "$db_bytes" =~ ^[0-9]+$ ]] || die "could not read database size"
mkdir -p "$BACKUP_DIR"
free_kb="$(df -Pk "$BACKUP_DIR" | awk 'NR==2{print $4}')"
need_kb=$(( db_bytes * 3 / 1024 + 1 ))
[ "$free_kb" -ge "$need_kb" ] || die "free space ${free_kb}KB < required ${need_kb}KB (3x database size)"

out="$BACKUP_DIR/mushukistan-$(date +%Y%m%d-%H%M%S)-$label.dump"
[ ! -e "$out" ] || die "$out already exists"
echo "database size : $db_bytes bytes"
echo "free space    : ${free_kb}KB (need ${need_kb}KB)"
echo "target file   : $out"

if [ "$execute" -ne 1 ]; then
  echo "DRY RUN: nothing written. Re-run with --execute to create the backup."
  exit 0
fi

[ -t 0 ] || die "--execute needs an interactive terminal (ssh -t) so a human can confirm"
printf 'Type "BACKUP %s" to create this production backup: ' "$label"
read -r answer
[ "$answer" = "BACKUP $label" ] || die "confirmation did not match; nothing written"

umask 077
$DOCKER exec "$DB_CONTAINER" sh -c 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' > "$out.partial" \
  || { rm -f "$out.partial"; die "pg_dump failed; partial file removed"; }
[ -s "$out.partial" ] || { rm -f "$out.partial"; die "dump is empty; removed"; }
entries="$($DOCKER exec -i "$DB_CONTAINER" pg_restore --list < "$out.partial" | wc -l)"
[ "$entries" -gt 10 ] || { rm -f "$out.partial"; die "pg_restore --list shows only $entries entries; removed"; }
mv "$out.partial" "$out"
sha256sum "$out" | tee "$out.sha256"
ls -l "$out"
echo "pg_restore --list entries: $entries"
echo "NEXT: copy the dump and .sha256 off the server, e.g. from the operator machine:"
echo "      scp root@<server>:$out* ."
echo "Restore rehearsal (scratch database only, never production) is still recommended."
