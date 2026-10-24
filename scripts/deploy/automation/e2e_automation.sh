#!/usr/bin/env bash
# End-to-end test of the approval-based deployment system inside a disposable Docker-in-Docker
# host. Nothing touches the host's Docker or any server.
#   bash scripts/deploy/automation/e2e_automation.sh
# Inside the throwaway host it uses REAL sshd, sudo, a restricted account created by the real
# install-server.sh, the real broker/gate, the real activate-web-release.sh and backup-db.sh,
# and real Docker Compose (stub backend/db images; a local check stands in for the public
# HTTPS verification). One container at a time; about 600 MB of RAM.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
NAME="mushukistan-e2e-automation-$$"
cleanup() { docker rm -f "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --privileged --memory 1g --name "$NAME" -e DOCKER_TLS_CERTDIR= docker:27-dind >/dev/null
for _ in $(seq 1 60); do docker exec "$NAME" docker info >/dev/null 2>&1 && break; sleep 2; done
cd "$REPO"
tar -c scripts docker-compose.yml docker-compose.prod.yml docker-compose.notifications.yml infrastructure/nginx/default.conf \
  | docker exec -i "$NAME" sh -c 'mkdir -p /src && tar -x -C /src'
docker exec "$NAME" apk add --no-cache --upgrade bash curl openssl util-linux coreutils python3 openssh sudo shadow >/dev/null
MSYS_NO_PATHCONV=1 docker exec "$NAME" bash /src/scripts/deploy/automation/e2e_inner.sh
