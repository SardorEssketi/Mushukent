#!/usr/bin/env bash
# Encrypted nightly PostgreSQL backup. Runs ON the production server.
# STATUS: prepared, NOT installed or scheduled (see docs/BACKUP.md). Nothing here uploads data.
#
#   backup-nightly.sh              # dump -> age-encrypt -> verify header -> checksum -> prune
#   backup-nightly.sh --dry-run    # checks only, writes nothing
#   backup-nightly.sh --prune-only # apply the retention policy only
#
# The dump is piped straight into `age`: no plaintext dump ever touches the disk. Only the
# PUBLIC recipient key(s) live on the server; the private key stays with the owner, so a server
# compromise cannot decrypt old backups. Files are new, never overwritten, mode 0600.
#
# Environment (all optional):
#   BACKUP_DIR            default /root/mushukistan-backups/nightly
#   AGE_RECIPIENTS_FILE   default /etc/mushukistan/backup/age-recipients.txt (lines starting "age1")
#   DB_CONTAINER          default mushukistan-db
#   KEEP_DAILY            default 14   (keep every backup younger than this many days)
#   KEEP_WEEKLY           default 8    (also keep Sunday backups younger than this many weeks)
#   OFFSITE_HOOK          default empty = disabled. If set, run as: $OFFSITE_HOOK <encrypted-file>
#                         (only ever receives ciphertext; configured by the owner after approval)
#   NOW_EPOCH             testing only: pretend "now" for retention
set -euo pipefail
umask 077

DOCKER="${DOCKER_BIN:-docker}"
DB_CONTAINER="${DB_CONTAINER:-mushukistan-db}"
BACKUP_DIR="${BACKUP_DIR:-/root/mushukistan-backups/nightly}"
AGE_RECIPIENTS_FILE="${AGE_RECIPIENTS_FILE:-/etc/mushukistan/backup/age-recipients.txt}"
KEEP_DAILY="${KEEP_DAILY:-14}"
KEEP_WEEKLY="${KEEP_WEEKLY:-8}"
OFFSITE_HOOK="${OFFSITE_HOOK:-}"
PREFIX="mushukistan-nightly-"
mode="run"

die() { echo "ERROR: $*" >&2; exit 1; }
log() { echo "$(date -u +%FT%TZ) $*"; }

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) mode="dry"; shift ;;
    --prune-only) mode="prune"; shift ;;
    -h|--help) sed -n '2,24p' "$0"; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done
[[ "$KEEP_DAILY" =~ ^[0-9]+$ && "$KEEP_WEEKLY" =~ ^[0-9]+$ ]] || die "KEEP_DAILY/KEEP_WEEKLY must be integers"

prune() {
  local now="${NOW_EPOCH:-$(date -u +%s)}" newest f name ts epoch age_days dow keep
  newest="$(ls -1 "$BACKUP_DIR"/${PREFIX}*.dump.age 2>/dev/null | sort | tail -1 || true)"
  for f in "$BACKUP_DIR"/${PREFIX}*.dump.age; do
    [ -e "$f" ] || continue
    name="$(basename "$f")"
    [[ "$name" =~ ^${PREFIX}([0-9]{8})T([0-9]{6})Z\.dump\.age$ ]] || continue
    ts="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
    epoch="$(date -u -d "${ts:0:4}-${ts:4:2}-${ts:6:2} ${ts:8:2}:${ts:10:2}:${ts:12:2}" +%s)"
    age_days=$(( (now - epoch) / 86400 ))
    dow="$(date -u -d "@$epoch" +%u)"   # 7 = Sunday
    keep=0
    [ "$age_days" -lt "$KEEP_DAILY" ] && keep=1
    [ "$dow" = "7" ] && [ "$age_days" -lt $(( KEEP_WEEKLY * 7 )) ] && keep=1
    [ "$f" = "$newest" ] && keep=1          # never delete the newest backup
    if [ "$keep" -eq 0 ]; then
      if [ "$mode" = "dry" ]; then log "would delete $name (age ${age_days}d)"; else rm -f -- "$f" "$f.sha256"; log "deleted $name (age ${age_days}d)"; fi
    fi
  done
}

if [ "$mode" = "prune" ]; then
  [ -d "$BACKUP_DIR" ] || die "$BACKUP_DIR does not exist"
  prune; exit 0
fi

command -v age >/dev/null || die "age is not installed"
[ -r "$AGE_RECIPIENTS_FILE" ] || die "recipients file not readable: $AGE_RECIPIENTS_FILE (owner must provide the PUBLIC key)"
grep -q '^age1' "$AGE_RECIPIENTS_FILE" || die "recipients file has no 'age1...' public key"
if grep -qiE 'AGE-SECRET-KEY' "$AGE_RECIPIENTS_FILE"; then die "recipients file contains a PRIVATE key; remove it from the server"; fi
[ "$($DOCKER inspect -f '{{.State.Running}}' "$DB_CONTAINER" 2>/dev/null)" = "true" ] || die "container $DB_CONTAINER is not running"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"
exec 9>"$BACKUP_DIR/.lock"
command -v flock >/dev/null && { flock -n 9 || die "another backup is running"; }

db_bytes="$($DOCKER exec "$DB_CONTAINER" sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "select pg_database_size(current_database())"')"
[[ "$db_bytes" =~ ^[0-9]+$ ]] || die "could not read the database size"
free_kb="$(df -Pk "$BACKUP_DIR" | awk 'NR==2{print $4}')"
need_kb=$(( db_bytes * 3 / 1024 + 1 ))
[ "$free_kb" -ge "$need_kb" ] || die "free space ${free_kb}KB < required ${need_kb}KB"

out="$BACKUP_DIR/${PREFIX}$(date -u +%Y%m%dT%H%M%SZ).dump.age"
[ ! -e "$out" ] || die "$out already exists"
log "database ${db_bytes} bytes; target $(basename "$out")"
if [ "$mode" = "dry" ]; then
  log "DRY RUN: checks passed; nothing written"; prune; exit 0
fi

cleanup() { rm -f -- "$out.partial"; }
trap cleanup ERR
$DOCKER exec "$DB_CONTAINER" sh -c 'pg_dump -Fc -U "$POSTGRES_USER" "$POSTGRES_DB"' \
  | age -R "$AGE_RECIPIENTS_FILE" -o "$out.partial"
size="$(wc -c < "$out.partial")"
[ "$size" -gt 200 ] || die "encrypted file is only $size bytes"
[ "$(head -c 21 "$out.partial")" = "age-encryption.org/v1" ] || die "output is not an age file"
mv -- "$out.partial" "$out"
trap - ERR
(cd "$BACKUP_DIR" && sha256sum "$(basename "$out")" > "$(basename "$out").sha256")
log "created $(basename "$out") (${size} bytes, encrypted)"

if [ -n "$OFFSITE_HOOK" ]; then
  log "running off-site hook on the ciphertext"
  $OFFSITE_HOOK "$out" || log "WARNING: off-site hook failed; the local backup is intact"
else
  log "off-site upload: disabled (OFFSITE_HOOK unset)"
fi
prune
log "done"
