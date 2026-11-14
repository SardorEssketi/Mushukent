#!/usr/bin/env bash
# One-command driver for the Mushukistan load tests (local, emulated production box only).
#
#   bash loadtest/run.sh all                 # secrets, stack, seed x1, baseline+target+spike
#   bash loadtest/run.sh secrets             # throwaway secrets + self-signed cert
#   bash loadtest/run.sh up                  # start the emulated box (+ migrate)
#   bash loadtest/run.sh seed 1|10           # seed realistic (1) or 10x data, mint tokens
#   bash loadtest/run.sh run <name> [VAR=value ...]
#        <name>: baseline | target | spike | stress | soak | short
#        e.g.  run short LT_USERS=40 LT_USERS_PER_IP=40 LT_TAG=cgnat40
#   bash loadtest/run.sh down                # stop the stack (keeps the data volume)
#   bash loadtest/run.sh destroy             # stop and delete the disposable data volume
#
# Results land in loadtest/results/<timestamp>-<name>[-tag]/ (gitignored).
# Never point any of this at production: the compose file has no remote hosts.
set -euo pipefail
cd "$(dirname "$0")"
DC=(docker compose --env-file .secrets/secrets.env -f compose.yml)
PY=.venv/Scripts/python
[ -x "$PY" ] || PY=.venv/bin/python

need_venv() {
  if [ ! -x "$PY" ]; then
    python -m venv .venv
    PY=.venv/Scripts/python; [ -x "$PY" ] || PY=.venv/bin/python
    "$PY" -m pip install -q "locust==2.32.4" "pillow==11.0.0"
  fi
}

psql_load() { docker exec mushukistan-load-db-1 psql -U mushukistan -d mushukistan_load "$@"; }

cmd=${1:-help}; shift || true
case "$cmd" in
  secrets)
    mkdir -p .secrets nginx/empty results/_runtime
    MSYS_NO_PATHCONV=1 docker run --rm -v "$(pwd -W 2>/dev/null || pwd)/tools:/tools:ro" \
      -v "$(pwd -W 2>/dev/null || pwd)/.secrets:/out" --entrypoint python \
      "mushukistan-backend:${BACKEND_TAG:-8939818}" /tools/gen_secrets.py /out ;;
  up)
    [ -f .secrets/secrets.env ] || "$0" secrets
    bash tools/loadbox.sh
    mkdir -p results/_runtime
    "${DC[@]}" up -d db mocks
    "${DC[@]}" --profile tools run --rm migrate
    "${DC[@]}" up -d
    psql_load -qc "create extension if not exists pg_stat_statements" ;;
  seed)
    "${DC[@]}" --profile tools run --rm seed --scale "${1:-1}" ;;
  run)
    need_venv
    name=${1:?scenario}; shift
    for kv in "$@"; do export "$kv"; done
    out="results/$(date +%Y%m%d-%H%M%S)-${name}${LT_TAG:+-$LT_TAG}"
    mkdir -p "$out"
    : > results/_runtime/pool.jsonl
    psql_load -qc "select pg_stat_statements_reset()" >/dev/null
    psql_load -qc "select pg_stat_reset()" >/dev/null
    curl -s -X POST localhost:19000/__reset >/dev/null
    env | grep '^LT_' > "$out/env.txt" || true
    "$PY" tools/monitor.py "$out" --interval 5 &
    mon=$!
    LT_OUT="$out" LT_SHAPE="$name" "$PY" -m locust -f locustfile.py --headless \
      --csv "$out/locust" --csv-full-history --html "$out/report.html" \
      --only-summary --loglevel WARNING ${LT_EXTRA:-} 2> "$out/locust.log" || true
    if [ "${LT_RECOVERY:-0}" = "1" ]; then  # measure self-recovery before anything else
      "$PY" tools/recovery_probe.py "$out" | tee -a "$out/recovery.txt"
    fi
    touch "$out/STOP"; wait "$mon" || true
    cp results/_runtime/pool.jsonl "$out/pool.jsonl"
    curl -s localhost:19000/__stats > "$out/external_calls.json"
    psql_load -At -F '|' -c "select calls, round(total_exec_time::numeric,0) total_ms,
        round(mean_exec_time::numeric,2) mean_ms, round(max_exec_time::numeric,1) max_ms, rows,
        shared_blks_hit, shared_blks_read, temp_blks_read + temp_blks_written,
        left(regexp_replace(query,'\s+',' ','g'),300)
      from pg_stat_statements order by total_exec_time desc limit 30" > "$out/pg_top.txt"
    psql_load -At -F '|' -c "select relname, n_tup_ins, n_tup_upd, n_dead_tup, autovacuum_count,
        autoanalyze_count from pg_stat_user_tables order by n_tup_upd+n_tup_ins desc limit 15" \
      > "$out/pg_tables.txt"
    "${DC[@]}" logs --since 2h db 2>&1 | grep -E "deadlock|lock|ERROR|FATAL|duration" \
      | tail -200 > "$out/db_log.txt" || true
    "${DC[@]}" logs --since 2h backend 2>&1 | grep -E -i "error|exception|timeout|killed" \
      | grep -v '" 200\|" 201\|" 204' | tail -200 > "$out/backend_errors.txt" || true
    "$PY" tools/summarize.py "$out" | tee "$out/summary.md" ;;
  down) "${DC[@]}" down ;;
  destroy) "${DC[@]}" down -v ;;
  all)
    "$0" up; "$0" seed 1
    "$0" run baseline; "$0" run target; "$0" run spike ;;
  *) sed -n '2,20p' "$0" ;;
esac
