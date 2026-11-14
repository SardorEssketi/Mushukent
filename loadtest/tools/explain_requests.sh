#!/usr/bin/env bash
# Capture the real query plans (EXPLAIN ANALYZE, BUFFERS via auto_explain) of the app's Feed and
# Map requests on the load database. Disposable load DB only: auto_explain is switched on for the
# database, the backend is restarted so its pool picks it up, and everything is reset afterwards.
#   bash tools/explain_requests.sh <out_file>
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=${1:?out file}
DC=(docker compose --env-file .secrets/secrets.env -f compose.yml)
PSQL=(docker exec mushukistan-load-db-1 psql -U mushukistan -d mushukistan_load -qAt)
"${PSQL[@]}" -c "alter database mushukistan_load set session_preload_libraries='auto_explain'" \
  -c "alter database mushukistan_load set auto_explain.log_min_duration=0" \
  -c "alter database mushukistan_load set auto_explain.log_analyze=on" \
  -c "alter database mushukistan_load set auto_explain.log_buffers=on" \
  -c "alter database mushukistan_load set auto_explain.log_timing=on"
"${DC[@]}" restart backend >/dev/null 2>&1; sleep 25
docker exec mushukistan-load-nginx-1 nginx -s reload >/dev/null 2>&1; sleep 2
TOK=$(python -c "import json;print(json.load(open('results/tokens.json'))['users'][570]['token'])")
R=(--resolve api.mushukistan.uz:18443:127.0.0.1 -sk)
B=https://api.mushukistan.uz:18443/api/v1
get() { curl "${R[@]}" -o /dev/null -w "%{http_code} %{time_total}s $1\n" -H "X-Forwarded-For: 10.93.$RANDOM.1" "${@:2}" "$B/$1"; }
cursor() { curl "${R[@]}" -H "X-Forwarded-For: 10.93.0.9" "${@:2}" "$B/$1" | python -c "import sys,json;print(json.load(sys.stdin)['data']['next_cursor'])"; }
START=$(docker logs mushukistan-load-db-1 2>&1 | wc -l)
NEAR="feed?filter=nearby&lat=41.3111&lon=69.2797&radius_meters=5000&limit=20"
get "feed?limit=20"
get "feed?limit=20" -H "Authorization: Bearer $TOK"
C=$(cursor "feed?limit=20"); get "feed?limit=20&cursor=$C"
get "feed?filter=popular&limit=20"
get "$NEAR"
C=$(cursor "$NEAR"); get "$NEAR&cursor=$C"
get "cats?filter=recently_added&limit=100&bbox=69.23,41.29,69.33,41.34"
get "cats?filter=recently_added&limit=100&bbox=69.15,41.25,69.40,41.37"
sleep 2
docker logs mushukistan-load-db-1 2>&1 | tail -n +$((START + 1)) > "$OUT.raw"
"${PSQL[@]}" -c "alter database mushukistan_load reset all"
"${DC[@]}" restart backend >/dev/null 2>&1; sleep 20
docker exec mushukistan-load-nginx-1 nginx -s reload >/dev/null 2>&1
# Summary: statements over 5 ms with their scan nodes.
grep -E "duration: |Query Text: .{0,70}|(Index|Seq|Bitmap Heap|Bitmap Index|Index Only) Scan|Execution Time" "$OUT.raw" \
  | awk '/duration:/{split($0,a,"duration: "); split(a[2],b," ms"); keep=(b[1]+0>5)} keep' | cut -c1-170 > "$OUT"
wc -l "$OUT"
