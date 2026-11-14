#!/usr/bin/env bash
# Re-measurement driver (FIXES_RESULTS.md). Disposable local stack only. One heavy run at a time:
# the driver takes a lock (tools/guard.sh), refuses to start next to a running Locust, checks host
# free memory before every step and stops the sequence if a run was stopped for memory.
#
#   bash tools/remeasure.sh slope <variant> [users...]   per-container CPU vs users (default 0 5 10 15 20)
#        variant: before | after | <any image tag>      (before migrates down to 0031, others to head)
#   bash tools/remeasure.sh after-1x                     the after-fix scenario set
#   bash tools/remeasure.sh soak                         LT_USERS=<n> required
#   bash tools/remeasure.sh switch <image> [max_in_flight]
#
# Steps run inside main(): bash has parsed the whole file before running any of it, so editing this
# script while it runs cannot re-execute part of it (that is how two runs overlapped on 2026-11-14).
set -uo pipefail
cd "$(dirname "$0")/.."
. tools/guard.sh
DC=(docker compose --env-file .secrets/secrets.env -f compose.yml)
PY=.venv/Scripts/python
[ -x "$PY" ] || PY=.venv/bin/python
BEFORE=${BEFORE_TAG:-8939818}
AFTER=${AFTER_TAG:-fixes-6a5a3db}
WARMUP_S=${SLOPE_WARMUP_S:-90}
WINDOW_S=${SLOPE_WINDOW_S:-300}

switch() {  # switch <image> <pg_parallel> [max_in_flight]
  export BACKEND_TAG=$1 PG_PARALLEL_PER_GATHER=$2 MAX_IN_FLIGHT_REQUESTS=${3:-48}
  "${DC[@]}" up -d db >/dev/null 2>&1
  sleep 8
  "${DC[@]}" up -d backend notification-worker >/dev/null 2>&1
  for _ in $(seq 1 60); do
    docker inspect -f '{{.State.Health.Status}}' mushukistan-load-backend-1 | grep -q healthy && break
    sleep 3
  done
  docker exec mushukistan-load-nginx-1 nginx -s reload >/dev/null 2>&1
  sleep 3
  echo "== image $(docker inspect -f '{{.Config.Image}}' mushukistan-load-backend-1)" \
       "parallel=$2 max_in_flight=${3:-48}"
}

clear_stuck() {
  docker exec mushukistan-load-db-1 psql -U mushukistan -d mushukistan_load -qAt -c \
    "select count(pg_cancel_backend(pid)) from pg_stat_activity where datname=current_database() and state='active' and pid<>pg_backend_pid()" >/dev/null
}

stop_if_memory_stopped() {  # never continue a sequence after a run was stopped for memory
  local m
  m=$(ls -t results/*/MEMORY_STOP 2>/dev/null | head -1)
  if [ -n "$m" ] && [ "$m" -nt "$GUARD_RUNTIME/remeasure.lock/since" ]; then
    echo "remeasure: $(dirname "$m") was stopped for memory: $(cat "$m"). Stopping the sequence." >&2
    exit 4
  fi
}

run() {  # run.sh run ... with the checks between steps
  stop_if_memory_stopped
  guard_memory >/dev/null
  bash run.sh run "$@"
  stop_if_memory_stopped
}

cgroup_cpu() {  # "<container-name> <usage_usec>" per box container, then "total <usec>"
  local map
  map=$(docker ps --no-trunc --filter name=mushukistan-load- --format '{{.ID}} {{.Names}}' | tr '\n' ';')
  MSYS_NO_PATHCONV=1 docker run --rm --privileged --cgroupns=host \
    -v /sys/fs/cgroup:/sys/fs/cgroup:ro alpine:3.20 sh -c "
      echo \"$map\" | tr ';' '\n' | while read id name; do
        [ -f /sys/fs/cgroup/loadbox/\$id/cpu.stat ] || continue
        echo \"\${name#mushukistan-load-} \$(grep usage_usec /sys/fs/cgroup/loadbox/\$id/cpu.stat | cut -d' ' -f2)\"
      done
      echo \"total \$(grep usage_usec /sys/fs/cgroup/loadbox/cpu.stat | cut -d' ' -f2)\""
}

slope_step() {  # slope_step <variant> <users>: one clean steady window, appended to slope.csv
  local variant=$1 users=$2 csv=results/cpu-slope/slope.csv a b t0 t1 pid="" dir=""
  mkdir -p results/cpu-slope
  [ -f "$csv" ] || echo "variant,users,seconds,container,usage_us,run_dir,step" > "$csv"
  stop_if_memory_stopped
  guard_memory >/dev/null
  if [ "$users" -gt 0 ]; then
    bash run.sh run short LT_USERS="$users" LT_HOLD_S=$((WARMUP_S + WINDOW_S)) \
      LT_TAG="slope-$variant-u$users" > "results/cpu-slope/_$variant-u$users.out" 2>&1 &
    pid=$!
    sleep "$WARMUP_S"
  else
    sleep 60  # idle: let the previous step's tail settle
  fi
  a=$(cgroup_cpu); t0=$(date +%s)
  sleep "$WINDOW_S"
  b=$(cgroup_cpu); t1=$(date +%s)
  if [ -n "$pid" ]; then
    wait "$pid"
    dir=$(ls -dt results/*-short-slope-"$variant"-u"$users" 2>/dev/null | head -1)
    [ -f "$dir/MEMORY_STOP" ] && { echo "slope: $dir stopped for memory; step discarded" >&2; exit 4; }
  fi
  join <(echo "$a" | sort) <(echo "$b" | sort) | while read -r name ua ub; do
    echo "$variant,$users,$((t1 - t0)),$name,$((ub - ua)),$dir,$t0" >> "$csv"
  done
  echo "slope: $variant u=$users done ($dir)"
  sleep 20
}

main() {
  guard_acquire remeasure "$@"
  guard_no_active_load
  guard_memory
  case "${1:?mode}" in
    switch) switch "${2:?image}" 0 "${3:-48}" ;;
    slope)
      local variant=${2:?variant} image
      shift 2
      case "$variant" in
        before)
          BACKEND_TAG=$AFTER "${DC[@]}" --profile tools run --rm migrate alembic downgrade 20261110_0031 2>&1 | tail -1
          switch "$BEFORE" 2 ;;
        after) image=$AFTER ;;&
        *) image=${image:-$variant}
          BACKEND_TAG=$image "${DC[@]}" --profile tools run --rm migrate 2>&1 | tail -1
          switch "$image" 0 ;;
      esac
      for u in ${*:-0 5 10 15 20}; do slope_step "$variant" "$u"; done
      "$PY" tools/slope_fit.py results/cpu-slope/slope.csv ;;
    after-1x)
      switch "$AFTER" 0
      run baseline LT_TAG=after
      run stress LT_STEP_USERS=5 LT_STEPS=8 LT_TAG=after; clear_stuck; sleep 30
      run target LT_RECOVERY=1 LT_TAG=after; clear_stuck; sleep 30
      run spike LT_EXPIRED_TOKENS=1 LT_TAG=after; clear_stuck; sleep 30
      run short LT_USERS=40 LT_USERS_PER_IP=40 LT_HOLD_S=240 LT_TAG=cgnat40-after
      run short LT_USERS=40 LT_USERS_PER_IP=40 LT_HOLD_S=240 LT_EXPIRED_TOKENS=1 \
        LT_TAG=cgnat40-expired-after
      "$PY" tools/upload_stress.py results/upload-cap8-10-after --concurrent 10 \
        --files 5 --size max --monitor > /dev/null 2>&1
      switch "$AFTER" 0 16
      run short LT_USERS=300 LT_HOLD_S=240 LT_RECOVERY=1 LT_TAG=cap16-after
      clear_stuck; switch "$AFTER" 0 48 ;;
    soak)
      switch "$AFTER" 0 "${MAX_IN_FLIGHT_REQUESTS:-48}"
      run soak LT_USERS="${LT_USERS:?users}" LT_SOAK_S=3600 LT_TAG=after ;;
    *) echo "unknown mode"; exit 2 ;;
  esac
}
main "$@"; exit $?
