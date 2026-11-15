#!/usr/bin/env bash
# Self-test for tools/guard.sh (no Docker, no load): bash tools/test_guard.sh
set -u
cd "$(dirname "$0")/.."
tmp=$(mktemp -d); export GUARD_RUNTIME=$tmp/rt; fail=0
check() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (got $2, want $3)"; fail=1; fi; }

( . tools/guard.sh; guard_acquire t; sleep 4 ) & holder=$!
sleep 1
( . tools/guard.sh; guard_acquire t ) 2>/dev/null; check "second holder refused" $? 3
wait $holder
check "lock released on exit" "$([ -d "$GUARD_RUNTIME/t.lock" ] && echo held || echo free)" free

mkdir -p "$GUARD_RUNTIME/t.lock"; echo 999999 > "$GUARD_RUNTIME/t.lock/pid"
( . tools/guard.sh; guard_acquire t ) 2>/dev/null; check "stale lock taken over" $? 0

( . tools/guard.sh; LT_MIN_FREE_MB=99999999 guard_memory ) >/dev/null 2>&1; check "low memory refused" $? 4
( . tools/guard.sh; LT_MIN_FREE_MB=1 guard_memory ) >/dev/null 2>&1; check "enough memory accepted" $? 0

sleep 60 & victim=$!
( . tools/guard.sh; LT_ABORT_FREE_MB=99999999 guard_watchdog $victim "$tmp" )
sleep 1
check "watchdog stopped the run" "$(kill -0 $victim 2>/dev/null && echo alive || echo stopped)" stopped
check "watchdog wrote MEMORY_STOP" "$([ -f "$tmp/MEMORY_STOP" ] && echo yes || echo no)" yes

sleep 60 & victim=$!
bash -c 'sleep 2' & parent=$!
( . tools/guard.sh; guard_watchdog $victim "$tmp" $parent )
sleep 1
check "watchdog stopped an orphaned run" "$(kill -0 $victim 2>/dev/null && echo alive || echo stopped)" stopped
check "watchdog wrote ORPHAN_STOP" "$([ -f "$tmp/ORPHAN_STOP" ] && echo yes || echo no)" yes

PYV=.venv/Scripts/python.exe
if [ -x "$PYV" ]; then  # Windows: the venv python is a launcher with the real interpreter as a child
  "$PYV" -c "import time; time.sleep(60)  # guard-tree-test" & victim=$!
  sleep 2
  ( . tools/guard.sh; LT_ABORT_FREE_MB=99999999 guard_watchdog $victim "$tmp" )
  sleep 2
  left=$(powershell.exe -NoProfile -Command "(Get-CimInstance Win32_Process -Filter \"Name like 'python%'\" | Where-Object { \$_.CommandLine -match 'guard-tree-test' }).Count" | tr -d '\r')
  check "watchdog stopped the whole python process tree" "${left:-0}" 0
fi

check "run.sh starts the watchdog for Locust" "$(grep -c 'guard_watchdog "$loc" "$out" "$PPID" &' run.sh)" 1

( . tools/guard.sh; guard_no_active_load ) >/dev/null 2>&1; check "no load process running" $? 0
rm -rf "$tmp"; exit $fail
