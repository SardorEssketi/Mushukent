#!/usr/bin/env bash
# Guards for the load harness (sourced by run.sh and remeasure.sh): one heavy run at a time, and
# never on a starved workstation.
#
#   guard_acquire <name>     take results/_runtime/<name>.lock (atomic mkdir) or exit 3. A lock
#                            whose owner pid is gone is stale and is taken over. Released on exit.
#   guard_no_active_load     exit 3 if a Locust or upload-stress process is already running.
#   guard_memory             exit 4 if host free memory is below LT_MIN_FREE_MB (default 1536).
#   guard_watchdog <pid> <out> [parent]  background: if free memory falls below LT_ABORT_FREE_MB
#                            (default 1200), kill <pid>, write <out>/MEMORY_STOP and stop. Drivers
#                            must not restart a run that has MEMORY_STOP (remeasure.sh checks it).
#                            If <parent> (the driver's own parent) dies, kill <pid> and write
#                            <out>/ORPHAN_STOP: on Windows killing a shell leaves its children running.
#   guard_exit_with_parent   background: end this driver when the shell that started it is gone.
#
# Why: on 2026-11-14 two 10-user CPU runs overlapped for 466 s. remeasure.sh was edited while it
# ran; bash reads a script by byte offset, so it re-executed part of the file and started a second
# run. Its runs were also detached with `( ... & )`, so killing the driver left Locust running.

GUARD_RUNTIME="${GUARD_RUNTIME:-results/_runtime}"

host_free_mb() {  # Git Bash and Linux both expose host memory in /proc/meminfo
  awk '/^MemAvailable:/ {a=$2} /^MemFree:/ {f=$2} END {print int((a ? a : f) / 1024)}' /proc/meminfo
}

guard_acquire() {
  local name=$1 dir pid
  mkdir -p "$GUARD_RUNTIME"
  dir="$GUARD_RUNTIME/$name.lock"
  if ! mkdir "$dir" 2>/dev/null; then
    pid=$(cat "$dir/pid" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      echo "guard: '$name' is already running (pid $pid, since $(cat "$dir/since" 2>/dev/null))." >&2
      echo "guard: $(cat "$dir/cmd" 2>/dev/null)" >&2
      exit 3
    fi
    echo "guard: removing stale '$name' lock (pid ${pid:-?} is gone)" >&2
    rm -rf "$dir"
    mkdir "$dir" || { echo "guard: could not take '$name' lock" >&2; exit 3; }
  fi
  echo $$ > "$dir/pid"
  date '+%F %T' > "$dir/since"
  echo "$0 $*" > "$dir/cmd"
  # shellcheck disable=SC2064
  trap "rm -rf '$dir'" EXIT
}

active_load_processes() {  # prints one line per running Locust / upload-stress process
  if command -v powershell >/dev/null 2>&1; then
    powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name like 'python%'\" |
      Where-Object { \$_.CommandLine -match 'locust -f|locustfile|upload_stress\.py' } | ForEach-Object { \"\$(\$_.ProcessId) \$(\$_.CommandLine)\" }" \
      | tr -d '\r'
  else
    pgrep -af 'python.*(locust -f|locustfile|upload_stress\.py)' || true
  fi
}

guard_no_active_load() {
  local procs
  procs=$(active_load_processes)
  if [ -n "$procs" ]; then
    echo "guard: a load process is already running; refusing to start another:" >&2
    echo "$procs" >&2
    exit 3
  fi
}

guard_memory() {
  local free min=${LT_MIN_FREE_MB:-1536}
  free=$(host_free_mb)
  if [ "$free" -lt "$min" ]; then
    echo "guard: host free memory ${free} MB < ${min} MB; not starting (free memory, then retry by hand)." >&2
    exit 4
  fi
  echo "guard: host free memory ${free} MB"
}

kill_tree() {  # kill_tree <pid>: the process and its children (Windows: the venv python.exe is a
  # launcher that starts the real interpreter as a child, so a plain kill can leave Locust running)
  local win
  win=$(cat "/proc/$1/winpid" 2>/dev/null)
  if [ -n "$win" ] && command -v taskkill >/dev/null 2>&1; then
    MSYS_NO_PATHCONV=1 taskkill /F /T /PID "$win" >/dev/null 2>&1
  fi
  kill "$1" 2>/dev/null; sleep 2; kill -9 "$1" 2>/dev/null
  return 0
}

guard_watchdog() {  # guard_watchdog <pid> <out> [parent]   (run in the background)
  local pid=$1 out=$2 parent=${3:-} floor=${LT_ABORT_FREE_MB:-1200} free low=$((1 << 30))
  while kill -0 "$pid" 2>/dev/null; do
    if [ -n "$parent" ] && ! kill -0 "$parent" 2>/dev/null; then
      echo "driver (pid $parent) is gone at $(date '+%F %T'); run stopped" > "$out/ORPHAN_STOP"
      kill_tree "$pid"
      return
    fi
    free=$(host_free_mb)
    [ "$free" -lt "$low" ] && low=$free && echo "$low" > "$out/host_free_min_mb.txt"
    if [ "$free" -lt "$floor" ]; then
      echo "host free memory ${free} MB < ${floor} MB at $(date '+%F %T'); run stopped" > "$out/MEMORY_STOP"
      kill_tree "$pid"
      return
    fi
    sleep 5
  done
}

guard_exit_with_parent() {  # run as: guard_exit_with_parent &   (from the driver's main shell)
  local me=$$ parent=$PPID
  while kill -0 "$parent" 2>/dev/null && kill -0 "$me" 2>/dev/null; do sleep 5; done
  kill "$me" 2>/dev/null
}
