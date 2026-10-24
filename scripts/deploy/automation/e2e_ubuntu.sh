#!/usr/bin/env bash
# The same end-to-end test as e2e_automation.sh, on Ubuntu 24.04 (the production distribution):
# Ubuntu's own sshd_config (Include first; UsePAM, AcceptEnv, Subsystem after it), PAM, sudo with
# `Defaults use_pty`, Python 3.12, docker.io + docker-compose-v2 (Compose v2 like production).
#   bash scripts/deploy/automation/e2e_ubuntu.sh
# Disposable and local only: a privileged ubuntu:24.04 container runs its own dockerd. About 1.5 GB
# of RAM and a few hundred MB of packages; nothing touches the host's containers or any server.
set -euo pipefail
export MSYS_NO_PATHCONV=1   # Git Bash on Windows would rewrite the /paths passed to docker exec
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../../.." && pwd)"
NAME="mushukistan-e2e-ubuntu-$$"
cleanup() { docker rm -f -v "$NAME" >/dev/null 2>&1 || true; }
trap cleanup EXIT

docker run -d --privileged --memory 1500m -v /var/lib/docker --name "$NAME" ubuntu:24.04 sleep infinity >/dev/null
docker exec "$NAME" bash -c 'apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
  openssh-server openssh-client sudo python3 docker.io docker-compose-v2 curl openssl ca-certificates util-linux \
  procps iproute2 >/dev/null 2>&1'
# containers cannot set the audit login uid; production hosts can. Nothing else in PAM is changed.
docker exec "$NAME" sed -i 's/^session\s\+required\s\+pam_loginuid.so/session optional pam_loginuid.so/' /etc/pam.d/sshd
docker exec -d "$NAME" dockerd --host=unix:///var/run/docker.sock
for _ in $(seq 1 60); do docker exec "$NAME" docker info >/dev/null 2>&1 && break; sleep 2; done
cd "$REPO"
tar -c scripts docker-compose.yml docker-compose.prod.yml docker-compose.notifications.yml infrastructure/nginx/default.conf \
  | docker exec -i "$NAME" sh -c 'mkdir -p /src && tar -x --no-same-owner -C /src'
MSYS_NO_PATHCONV=1 docker exec -e E2E_DISTRO=ubuntu "$NAME" bash /src/scripts/deploy/automation/e2e_inner.sh
