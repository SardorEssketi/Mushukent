#!/bin/sh
# Certbot deploy hook: make the running Nginx container pick up a renewed certificate.
# Installed (by set-webroot.sh) as /etc/letsencrypt/renewal-hooks/deploy/mushukistan-reload-nginx.sh.
# Certbot runs it only after a SUCCESSFUL renewal. It validates the configuration first and then
# sends a graceful reload (nginx -s reload): the container is NOT restarted or recreated, no
# connection is dropped, and a failed validation leaves the old, still-working workers running.
set -eu
CONTAINER="${NGINX_CONTAINER:-mushukistan-nginx}"
DOCKER="${DOCKER_BIN:-docker}"

$DOCKER exec "$CONTAINER" nginx -t
$DOCKER exec "$CONTAINER" nginx -s reload
echo "$(date -u +%FT%TZ) mushukistan-reload-nginx: reloaded $CONTAINER after renewal of ${RENEWED_LINEAGE:-<unknown lineage>}"
