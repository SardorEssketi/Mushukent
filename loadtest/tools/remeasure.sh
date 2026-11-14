#!/usr/bin/env bash
# Re-measurement driver (FIXES_RESULTS.md). Disposable local stack only.
#   bash tools/remeasure.sh cpu-before | cpu-after | after-1x | x10
set -uo pipefail
cd "$(dirname "$0")/.."
DC=(docker compose --env-file .secrets/secrets.env -f compose.yml)
BEFORE=${BEFORE_TAG:-8939818}
AFTER=${AFTER_TAG:-fixes-6a5a3db}

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

cpu_per_user() {  # cpu_per_user <tag>: 10 users; CPU of the whole box over a 300 s steady window
  ( bash run.sh run short LT_USERS=10 LT_HOLD_S=420 LT_TAG="cpu-$1" > "results/_cpu_$1.out" 2>&1 & )
  sleep 100
  local a t0 b t1
  a=$(bash tools/box_cpu.sh); t0=$(date +%s)
  sleep 300
  b=$(bash tools/box_cpu.sh); t1=$(date +%s)
  python - "$a" "$b" "$t0" "$t1" "$1" <<'EOF'
import sys
a, b, t0, t1, tag = int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
seconds = t1 - t0
ws_core = (b - a) / 1e6 / seconds          # workstation cores busy on average
prod_core = ws_core / 0.28                  # the box budget (0.28 ws core) = one production core
print(f"CPU {tag}: box used {ws_core:.3f} workstation cores = {prod_core:.3f} production cores "
      f"for 10 users -> {prod_core / 10 * 1000:.1f} ms of a production core per user-second")
EOF
  sleep 150
}

case "${1:?mode}" in
  cpu-before)
    BACKEND_TAG=$AFTER "${DC[@]}" --profile tools run --rm migrate alembic downgrade 20261110_0031 2>&1 | tail -1
    switch "$BEFORE" 2
    cpu_per_user before ;;
  cpu-after)
    BACKEND_TAG=$AFTER "${DC[@]}" --profile tools run --rm migrate 2>&1 | tail -1
    switch "$AFTER" 0
    cpu_per_user after ;;
  after-1x)
    switch "$AFTER" 0
    bash run.sh run baseline LT_TAG=after
    bash run.sh run stress LT_STEP_USERS=5 LT_STEPS=8 LT_TAG=after; clear_stuck; sleep 30
    bash run.sh run target LT_RECOVERY=1 LT_TAG=after; clear_stuck; sleep 30
    bash run.sh run spike LT_EXPIRED_TOKENS=1 LT_TAG=after; clear_stuck; sleep 30
    bash run.sh run short LT_USERS=40 LT_USERS_PER_IP=40 LT_HOLD_S=240 LT_TAG=cgnat40-after
    bash run.sh run short LT_USERS=40 LT_USERS_PER_IP=40 LT_HOLD_S=240 LT_EXPIRED_TOKENS=1 \
      LT_TAG=cgnat40-expired-after
    .venv/Scripts/python tools/upload_stress.py results/upload-cap8-10-after --concurrent 10 \
      --files 5 --size max --monitor > /dev/null 2>&1
    switch "$AFTER" 0 16
    bash run.sh run short LT_USERS=300 LT_HOLD_S=240 LT_RECOVERY=1 LT_TAG=cap16-after
    clear_stuck; switch "$AFTER" 0 48 ;;
  soak)
    switch "$AFTER" 0 "${MAX_IN_FLIGHT_REQUESTS:-48}"
    bash run.sh run soak LT_USERS="${LT_USERS:?users}" LT_SOAK_S=3600 LT_TAG=after ;;
  *) echo "unknown mode"; exit 2 ;;
esac
