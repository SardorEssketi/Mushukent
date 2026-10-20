#!/usr/bin/env bash
# Tests for scripts/backup/*. Needs bash, GNU coreutils, and `age`/`age-keygen`.
# The integration part (real PostGIS dump -> age -> restore) runs when a Docker daemon is
# reachable; it uses only throwaway containers and a throwaway key. Never touches production.
#   bash scripts/backup/test_backup_scripts.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
B="$HERE/backup-nightly.sh"; R="$HERE/restore-check.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0; total=0

check() { # description, expected(0|nonzero), needle, command...
  local desc="$1" want="$2" needle="$3"; shift 3
  local out rc good=1
  out="$("$@" 2>&1 </dev/null)"; rc=$?
  total=$((total+1))
  if [ "$want" = "0" ]; then [ $rc -eq 0 ] || good=0; else [ $rc -ne 0 ] || good=0; fi
  if [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$out"; then good=0; fi
  if [ $good -eq 1 ]; then echo "PASS  $desc"; else echo "FAIL  $desc (exit $rc)"; echo "$out" | tail -8 | sed 's/^/        /'; fails=$((fails+1)); fi
}

command -v age >/dev/null && command -v age-keygen >/dev/null || { echo "age/age-keygen required"; exit 2; }
check "syntax: backup-nightly.sh" 0 "" bash -n "$B"
check "syntax: restore-check.sh" 0 "" bash -n "$R"

age-keygen -o "$T/id.txt" >/dev/null 2>&1
age-keygen -y "$T/id.txt" > "$T/recipients.txt"
age-keygen -o "$T/other-id.txt" >/dev/null 2>&1

# ---- stub docker for unit tests ----
cat > "$T/docker" <<'EOF'
#!/usr/bin/env bash
a="$*"
case "$a" in
  *State.Running*) [ -n "${STUB_DOWN:-}" ] && echo false || echo true ;;
  *pg_database_size*) echo 1000 ;;
  *pg_dump*) [ -n "${STUB_DUMP_FAIL:-}" ] && { echo partial-output; exit 1; }
             printf 'PLAINTEXT-MARKER\n'; head -c 3000 /dev/urandom | base64 ;;
esac
EOF
chmod +x "$T/docker"
export DOCKER_BIN="$T/docker" BACKUP_DIR="$T/out" AGE_RECIPIENTS_FILE="$T/recipients.txt"

check "refuses without a recipients file" nonzero "recipients file not readable" env AGE_RECIPIENTS_FILE="$T/none" bash "$B"
printf 'AGE-SECRET-KEY-1ABC\nage1xyz\n' > "$T/bad.txt"
check "refuses a private key on the server" nonzero "PRIVATE key" env AGE_RECIPIENTS_FILE="$T/bad.txt" bash "$B"
check "refuses when the container is down" nonzero "is not running" env STUB_DOWN=1 bash "$B"
check "dry run writes nothing" 0 "DRY RUN" bash "$B" --dry-run
check "dry run created no backup file" nonzero "" bash -c "ls '$T/out'/*.age"

check "backup succeeds" 0 "created mushukistan-nightly-" bash "$B"
f="$(ls "$T"/out/mushukistan-nightly-*.dump.age | head -1)"
check "file name matches the convention" 0 "" bash -c "[[ '$(basename "$f")' =~ ^mushukistan-nightly-[0-9]{8}T[0-9]{6}Z\.dump\.age$ ]]"
check "file is an age file" 0 "age-encryption.org/v1" head -c 21 "$f"
check "ciphertext contains no plaintext" nonzero "" grep -aq PLAINTEXT-MARKER "$f"
check "owner key decrypts the backup" 0 "PLAINTEXT-MARKER" age -d -i "$T/id.txt" "$f"
check "another key cannot decrypt" nonzero "" age -d -i "$T/other-id.txt" "$f"
check "checksum file verifies" 0 "OK" bash -c "cd '$T/out' && sha256sum -c '$(basename "$f").sha256'"
check "file mode is 600" 0 "600" stat -c %a "$f"
sleep 1
check "off-site is disabled by default" 0 "off-site upload: disabled" bash "$B"
sleep 1
check "second backup does not overwrite" 0 "created" bash "$B"
check "distinct backups exist" 0 "3" bash -c "ls '$T'/out/*.dump.age | wc -l"

: > "$T/hook.log"; printf '#!/usr/bin/env bash\necho "$1" >> "%s"\n' "$T/hook.log" > "$T/hook.sh"; chmod +x "$T/hook.sh"
sleep 1
check "off-site hook receives only the encrypted file" 0 "running off-site hook" env OFFSITE_HOOK="$T/hook.sh" bash "$B"
check "hook was given a .age path" 0 ".dump.age" cat "$T/hook.log"
sleep 1
check "failing hook does not fail the backup" 0 "hook failed" env OFFSITE_HOOK=false bash "$B"

before="$(ls "$T/out" | wc -l)"; sleep 1
check "pg_dump failure fails the run" nonzero "" env STUB_DUMP_FAIL=1 bash "$B"
check "pg_dump failure leaves no partial or new file" 0 "$before" bash -c "ls '$T/out' | wc -l"
check "no .partial files remain" nonzero "" bash -c "ls '$T'/out/*.partial"

# ---- retention ----
export BACKUP_DIR="$T/ret"; mkdir -p "$BACKUP_DIR"
NOW="$(date -u -d '2026-10-20 12:00:00' +%s)"; export NOW_EPOCH="$NOW"
stamp() { date -u -d "@$((NOW - $1 * 86400))" +%Y%m%dT030000Z; }
sunday=""; weekday=""
for k in $(seq 20 30); do
  d="$(date -u -d "@$((NOW - k * 86400))" +%u)"
  [ "$d" = 7 ] && [ -z "$sunday" ] && sunday=$k
  [ "$d" != 7 ] && [ -z "$weekday" ] && weekday=$k
done
old_sunday=""; for k in $(seq 60 80); do [ "$(date -u -d "@$((NOW - k * 86400))" +%u)" = 7 ] && { old_sunday=$k; break; }; done
mk() { : > "$BACKUP_DIR/mushukistan-nightly-$(stamp "$1").dump.age"; : > "$BACKUP_DIR/mushukistan-nightly-$(stamp "$1").dump.age.sha256"; }
mk 1; mk 10; mk "$weekday"; mk "$sunday"; mk "$old_sunday"
: > "$BACKUP_DIR/mushukistan-20261003-manual.dump"; echo keep > "$BACKUP_DIR/README"
check "prune-only runs" 0 "deleted" bash "$B" --prune-only
exists() { [ -e "$BACKUP_DIR/mushukistan-nightly-$(stamp "$1").dump.age" ]; }
check "keeps a 1-day-old backup" 0 "" exists 1
check "keeps a 10-day-old backup" 0 "" exists 10
check "deletes a ${weekday}-day-old non-Sunday backup" nonzero "" exists "$weekday"
check "keeps a ${sunday}-day-old Sunday backup (weekly)" 0 "" exists "$sunday"
check "deletes a ${old_sunday}-day-old Sunday backup (beyond 8 weeks)" nonzero "" exists "$old_sunday"
check "removes the .sha256 of a deleted backup" nonzero "" test -e "$BACKUP_DIR/mushukistan-nightly-$(stamp "$weekday").dump.age.sha256"
check "leaves manual dumps and other files alone" 0 "" bash -c "test -e '$BACKUP_DIR/mushukistan-20261003-manual.dump' && test -e '$BACKUP_DIR/README'"
rm -f "$BACKUP_DIR"/mushukistan-nightly-*; mk 100
check "never deletes the newest backup even if old" 0 "" bash -c "KEEP_DAILY=1 KEEP_WEEKLY=0 bash '$B' --prune-only; ls '$BACKUP_DIR'/*.dump.age"
unset NOW_EPOCH

# ---- restore-check argument handling (no Docker needed) ----
echo "not age" > "$T/plain.dump.age"
check "restore-check refuses a non-age file" nonzero "not an age-encrypted file" bash "$R" --file "$T/plain.dump.age" --identity "$T/id.txt"
check "restore-check needs an identity" nonzero "--identity is required" bash "$R" --file "$f"

# ---- integration: real PostGIS -> backup -> age -> restore-check ----
if docker info >/dev/null 2>&1; then
  unset DOCKER_BIN; export BACKUP_DIR="$T/itest"
  N="mushukistan-backup-itest-$$"
  docker run -d --rm --name "$N" -e POSTGRES_USER=app -e POSTGRES_PASSWORD=itest -e POSTGRES_DB=app postgis/postgis:15-3.4 >/dev/null
  for _ in $(seq 1 60); do docker exec "$N" pg_isready -U app -d app >/dev/null 2>&1 && break; sleep 2; done; sleep 3
  docker exec "$N" psql -U app -d app -qc "
    create table alembic_version(version_num text); insert into alembic_version values ('20261015_0027');
    create table users(id int); insert into users select generate_series(1,37);
    create table posts(id int); insert into posts select generate_series(1,21);
    create table lost_pets(id int); insert into lost_pets values (1),(2);
    create table adoption_posts(id int); insert into adoption_posts select generate_series(1,3);
    create table comments(id int); insert into comments select generate_series(1,34);" >/dev/null
  check "integration: real backup runs" 0 "created mushukistan-nightly-" env DB_CONTAINER="$N" bash "$B"
  g="$(ls "$T"/itest/mushukistan-nightly-*.dump.age | head -1)"
  check "integration: real dump is encrypted" 0 "age-encryption.org/v1" head -c 21 "$g"
  check "integration: restore-check round trip" 0 "RESTORE CHECK OK" bash "$R" --file "$g" --identity "$T/id.txt"
  bash "$R" --file "$g" --identity "$T/id.txt" > "$T/restore.out" 2>&1
  check "integration: alembic revision restored" 0 "20261015_0027" grep -F "alembic_version|20261015_0027" "$T/restore.out"
  check "integration: users row count restored" 0 "users|37" grep -F "users|37" "$T/restore.out"
  check "integration: comments row count restored" 0 "comments|34" grep -F "comments|34" "$T/restore.out"
  check "integration: wrong identity cannot restore" nonzero "" bash "$R" --file "$g" --identity "$T/other-id.txt"
  docker rm -f "$N" >/dev/null 2>&1
else
  echo "SKIP  integration tests (no Docker daemon)"
fi

echo; echo "$((total-fails))/$total passed"
exit "$fails"
