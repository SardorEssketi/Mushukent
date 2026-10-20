#!/usr/bin/env bash
# Disposable end-to-end rehearsal of the TLS renewal fix. Needs a local Docker engine that allows
# privileged containers and network access (to pull ubuntu, nginx and the Pebble ACME test server).
#   bash scripts/tls/e2e_tls_renewal.sh
# Nothing here touches the host's Docker state beyond one throwaway container, and nothing contacts
# a real Certificate Authority or any real server. Pebble is Let's Encrypt's official ACME test CA.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"
NAME="mushukistan-tls-e2e-$$"
cleanup() { docker rm -fv "$NAME" >/dev/null 2>&1 || true; rm -rf "$REPO/.data/compose-check-$$"; }
trap cleanup EXIT
cd "$REPO"

echo "=== repo compose file: the ACME mount must be the stable host directory"
d=".data/compose-check-$$"; mkdir -p "$d"
cp docker-compose.yml docker-compose.prod.yml docker-compose.notifications.yml "$d/"
printf 'POSTGRES_DB=x\nPOSTGRES_USER=x\nPOSTGRES_PASSWORD=x\nFIREBASE_CREDENTIALS_HOST_PATH=/tmp/fb.json\n' > "$d/.env"
json="$(cd "$d" && docker compose --profile notifications -f docker-compose.yml -f docker-compose.prod.yml -f docker-compose.notifications.yml config --format json 2>/dev/null)"
printf '%s' "$json" | python -I -c "
import json,sys
c=json.load(sys.stdin)
m=[v for v in c['services']['nginx']['volumes'] if v['target']=='/var/www/certbot']
assert len(m)==1, m
assert m[0]['source']=='/var/www/certbot', m
assert m[0].get('read_only') is True, m
print('E2E PASS  nginx mounts the stable host directory /var/www/certbot read-only (no release-relative path)')
"

# /var/lib/docker must be a volume: overlayfs cannot nest on the container's own overlay root (same as docker:dind)
docker run -d --privileged --name "$NAME" -v /var/lib/docker ubuntu:24.04 sleep infinity >/dev/null
docker exec "$NAME" mkdir -p /work/repo/scripts /work/repo/infrastructure/nginx
docker cp scripts/tls "$NAME:/work/repo/scripts/tls"
docker cp infrastructure/nginx/default.conf "$NAME:/work/repo/infrastructure/nginx/default.conf"
docker exec "$NAME" bash -c 'chmod +x /work/repo/scripts/tls/*.sh'
docker exec "$NAME" bash /work/repo/scripts/tls/e2e_tls_inner.sh
