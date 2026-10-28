#!/usr/bin/env bash
# End-to-end rehearsal of activate-web-release.sh against REAL Docker Compose inside a
# disposable Docker-in-Docker daemon. Nothing touches the host's Docker or any server.
#   bash scripts/deploy/e2e_disposable.sh
# Requires a local Docker engine and network access to pull docker:dind and nginx images.
# It builds a miniature "mushukistan" project (same compose files and nginx config as the
# repo, a stub backend, self-signed TLS) with a backend-only release whose web/dist are
# symlinks, then switches Nginx to a new web release and rolls back.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NAME="mushukistan-e2e-dind-$$"
cleanup() { docker rm -f -v "$NAME" >/dev/null 2>&1 || true; }   # -v: drop the dind volume
trap cleanup EXIT

docker run -d --privileged --name "$NAME" -e DOCKER_TLS_CERTDIR= docker:27-dind >/dev/null
for _ in $(seq 1 60); do docker exec "$NAME" docker info >/dev/null 2>&1 && break; sleep 2; done
docker exec "$NAME" docker info >/dev/null || { echo "dind did not start"; exit 1; }
cd "$REPO"   # relative paths: a Windows "D:" prefix would be parsed as a container name
docker cp scripts "$NAME:/scripts"
docker cp docker-compose.yml "$NAME:/seed-compose.yml"
docker cp docker-compose.prod.yml "$NAME:/seed-prod.yml"
docker cp docker-compose.notifications.yml "$NAME:/seed-notif.yml"
docker cp infrastructure/nginx/default.conf "$NAME:/seed-nginx.conf"

docker exec -i "$NAME" sh -s <<'INNER'
set -eu
apk add --no-cache bash curl openssl util-linux >/dev/null
docker pull -q nginx:1.27-alpine >/dev/null
docker tag nginx:1.27-alpine mushukistan-backend:local     # stub backend image (never built here)
# stub db image: answers `pg_restore --list` like a catalog with 40 entries
mkdir /dbimg && printf 'FROM nginx:1.27-alpine\nRUN printf "#!/bin/sh\\nseq 1 40\\n" > /usr/local/bin/pg_restore && chmod +x /usr/local/bin/pg_restore\n' > /dbimg/Dockerfile
docker build -q -t postgis/postgis:15-3.4 /dbimg >/dev/null
R=/opt/mushukistan-releases
mkrel() { # dir  web-label
  d=$R/$1; mkdir -p $d/infrastructure/nginx $d/infrastructure/certbot/www
  cp /seed-compose.yml $d/docker-compose.yml; cp /seed-prod.yml $d/docker-compose.prod.yml
  cp /seed-notif.yml $d/docker-compose.notifications.yml; cp /seed-nginx.conf $d/infrastructure/nginx/default.conf
  printf 'POSTGRES_DB=x\nPOSTGRES_USER=x\nPOSTGRES_PASSWORD=x\nFIREBASE_CREDENTIALS_HOST_PATH=/etc/fb.json\n' > $d/.env
}
webdirs() { # dir label : real, complete web + landing
  d=$R/$1; mkdir -p $d/frontend/build/web/canvaskit $d/website/dist
  printf '<html>flutter %s</html>' "$2" > $d/frontend/build/web/index.html
  printf 'var a="https://api.mushukistan.uz/api/v1/"; // %s' "$2" > $d/frontend/build/web/main.dart.js
  printf '{"useLocalCanvasKit":true}' > $d/frontend/build/web/flutter_bootstrap.js
  printf '<html>landing %s</html>' "$2" > $d/website/dist/index.html
}
echo FIREBASE > /etc/fb.json
mkdir -p /etc/letsencrypt/live/mushukistan.uz
openssl req -x509 -nodes -newkey rsa:2048 -days 2 -subj /CN=mushukistan.uz \
  -keyout /etc/letsencrypt/live/mushukistan.uz/privkey.pem -out /etc/letsencrypt/live/mushukistan.uz/fullchain.pem 2>/dev/null
# Fixture overlay: the healthcheck of the stub backend must pass; pins + command like production.
overlay() { cat > $R/$1/docker-compose.notification-release.yml <<EOF
services:
  db:
    healthcheck: {test: ["CMD", "true"], interval: 2s, retries: 1}
  backend:
    image: mushukistan-backend:local
    command: ["nginx", "-g", "daemon off;"]
    healthcheck: {test: ["CMD", "true"], interval: 2s, retries: 1}
  notification-worker:
    image: mushukistan-backend:local
    command: ["nginx", "-g", "daemon off;"]
EOF
}
# 1. web release A (complete), 2. backend-only release (symlinks to A) = the "active" working dir.
mkrel 20260101-aaaaaaa-web; webdirs 20260101-aaaaaaa-web A; overlay 20260101-aaaaaaa-web
mkrel 20260102-bbbbbbb-backend; overlay 20260102-bbbbbbb-backend
mkdir -p $R/20260102-bbbbbbb-backend/frontend/build $R/20260102-bbbbbbb-backend/website
ln -s $R/20260101-aaaaaaa-web/frontend/build/web $R/20260102-bbbbbbb-backend/frontend/build/web
ln -s $R/20260101-aaaaaaa-web/website/dist $R/20260102-bbbbbbb-backend/website/dist
# 3. new web release C
mkrel 20260103-ccccccc-web; webdirs 20260103-ccccccc-web C; overlay 20260103-ccccccc-web
cp -r /scripts $R/20260103-ccccccc-web/scripts

# bring up the "production" stack from the backend-only release, like 2026-10-19
cd $R/20260102-bbbbbbb-backend
DC="docker compose --profile notifications -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.notifications.yml -f docker-compose.notification-release.yml"
$DC up -d --no-build db backend notification-worker nginx >/dev/null 2>&1 || { $DC up -d --no-build 2>&1 | tail -5; }
docker ps --format '{{.Names}} {{.Status}}'
ids_before=$(docker ps -q | xargs docker inspect --format '{{.Name}} {{.Id}}' | sort)

# local verify stub standing in for the public HTTPS checks
cat > /verify-local.sh <<'EOF'
#!/usr/bin/env bash
want="$2/index.html"; got="$(curl -sk --resolve mushukistan.uz:443:127.0.0.1 https://mushukistan.uz/index.html)"
[ "$got" = "$(cat "$want")" ] && echo "LOCAL-VERIFY OK: $got" || { echo "LOCAL-VERIFY FAIL: got '$got'"; exit 1; }
EOF
chmod +x /verify-local.sh
export VERIFY_SCRIPT=/verify-local.sh
SCRIPT=$R/20260103-ccccccc-web/scripts/deploy/activate-web-release.sh
printf 'dump-placeholder-needs-pg_restore' > /backup.dump

echo; echo "=== E2E 1: dry run reads labels + resolves symlinks, changes nothing"
bash $SCRIPT 20260103-ccccccc-web 2>&1 | grep -E "web currently|nginx -t|DRY RUN|ERROR|notifications profile|->"
page() { curl -sk --resolve mushukistan.uz:443:127.0.0.1 https://mushukistan.uz/index.html; }
others() { docker ps -q | xargs docker inspect --format '{{.Name}} {{.Id}}' | grep -v nginx | sort; }
fail=0
expect() { if [ "$2" = "$3" ]; then echo "E2E PASS  $1"; else echo "E2E FAIL  $1 (got '$2', want '$3')"; fail=1; fi; }
others_before="$(others)"
echo; echo "=== E2E 2: served page before"
expect "initial page is release A" "$(page)" "<html>flutter A</html>"

echo; echo "=== E2E 3: --execute through a real pty, wrong phrase"
printf 'nope\n' | script -qec "bash $SCRIPT 20260103-ccccccc-web --execute --backup-file /backup.dump" /dev/null | grep -E "did not match|ERROR" || true
expect "wrong phrase left release A" "$(page)" "<html>flutter A</html>"

echo; echo "=== E2E 4: --execute success"
printf 'ACTIVATE 20260103-ccccccc-web\n' | script -qec "bash $SCRIPT 20260103-ccccccc-web --execute --backup-file /backup.dump" /dev/null | tail -12
expect "page switched to release C" "$(page)" "<html>flutter C</html>"
expect "db/backend/worker container IDs unchanged" "$(others)" "$others_before"
expect "PREVIOUS_STATE written" "$(grep -c '^previous_working_dir=' $R/20260103-ccccccc-web/PREVIOUS_STATE.txt)" "1"
N=$(docker inspect mushukistan-nginx --format '{{range .Mounts}}{{.Source}}{{println}}{{end}}' | grep -c 20260103-ccccccc-web)
expect "nginx now mounts the new release (real bind mounts)" "$([ "$N" -ge 3 ] && echo yes)" "yes"

echo; echo "=== E2E 5: re-run is a no-op"
printf 'x\n' | script -qec "bash $SCRIPT 20260103-ccccccc-web --execute --backup-file /backup.dump" /dev/null | grep -E "already what Nginx serves" || echo "E2E FAIL no-op message missing"

echo; echo "=== E2E 6: rollback with the saved command"
RB="$(grep '^rollback=' $R/20260103-ccccccc-web/PREVIOUS_STATE.txt | cut -d= -f2-)"
sh -c "$RB" >/dev/null 2>&1
sleep 2
expect "rollback restored release A through the symlinks" "$(page)" "<html>flutter A</html>"
expect "rollback left other containers untouched" "$(others)" "$others_before"

echo; echo "=== E2E 7: failed public verification prints rollback and exits non-zero"
printf '#!/bin/sh\necho VERIFY-FAILED; exit 1\n' > /verify-bad.sh; chmod +x /verify-bad.sh
out="$(printf 'ACTIVATE 20260103-ccccccc-web\n' | VERIFY_SCRIPT=/verify-bad.sh script -qec "bash $SCRIPT 20260103-ccccccc-web --execute --backup-file /backup.dump; echo EXIT=\$?" /dev/null | tail -8)"
echo "$out" | grep -q "Roll back ONLY Nginx" && echo "E2E PASS  rollback hint printed" || { echo "E2E FAIL  no rollback hint"; fail=1; }
echo "$out" | grep -q "EXIT=1" && echo "E2E PASS  non-zero exit" || { echo "E2E FAIL  exit code"; fail=1; }
sh -c "$(grep '^rollback=' $R/20260103-ccccccc-web/PREVIOUS_STATE.txt | cut -d= -f2-)" >/dev/null 2>&1; sleep 2
expect "second rollback restored release A" "$(page)" "<html>flutter A</html>"

echo; echo "=== E2E 8: broken new release (missing overlay) is refused before any change"
mkrel 20260104-ddddddd-web; webdirs 20260104-ddddddd-web D; cp -r /scripts $R/20260104-ddddddd-web/
bash $R/20260104-ddddddd-web/scripts/deploy/activate-web-release.sh 20260104-ddddddd-web 2>&1 | grep -E "ERROR" || echo "E2E FAIL not refused"
expect "page unchanged after refused release" "$(page)" "<html>flutter A</html>"
echo; [ "$fail" -eq 0 ] && echo "E2E ALL PASSED" || { echo "E2E FAILURES"; exit 1; }
INNER

