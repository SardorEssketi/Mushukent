#!/bin/sh
# READ-ONLY inspection of the Mushukistan production host. It changes nothing:
# no docker start/stop/restart, no alembic command, no writes, no file creation (docker exec only runs
# printenv/ps/grep/psql inside READ ONLY transactions),
# no backup, no secret values (configuration is reported as set/unset only).
#
# Run it from the operator's machine (see docs/DEPLOYMENT.md, "Server access"):
#   ssh root@143.198.192.201 'sh -s' < scripts/deploy/remote-inspect.sh > prod_inspect.txt
# The output contains no secrets. Review the script first.
#
# Container names come from docker-compose.yml: mushukistan-backend, mushukistan-db, mushukistan-nginx.

section() { printf '\n=== %s\n' "$1"; }

section "host"
hostname; date -u +%FT%TZ; uptime -p 2>/dev/null
section "disk (df -h, root and docker)"
df -h / /var/lib/docker 2>/dev/null
section "memory"
free -m 2>/dev/null
section "containers (name, image, status, health)"
docker ps --format '{{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null
for c in mushukistan-backend mushukistan-db mushukistan-nginx; do
  printf '%s health=' "$c"; docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}no-healthcheck{{end}} restart={{.RestartCount}} started={{.State.StartedAt}}' "$c" 2>/dev/null || echo "not found"
done
section "backend image id and labels (no environment)"
docker inspect --format '{{.Image}} created={{.Created}}' mushukistan-backend 2>/dev/null
docker image ls --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.CreatedSince}}' 2>/dev/null | head -10
section "backend start command (does it auto-migrate?)"
docker inspect --format 'entrypoint={{json .Config.Entrypoint}} cmd={{json .Config.Cmd}}' mushukistan-backend 2>/dev/null
section "compose project / release directory (labels only)"
docker inspect --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}} {{index .Config.Labels "com.docker.compose.project.config_files"}}' mushukistan-backend 2>/dev/null
section "ACTIVE release (nginx container compose labels) and all labelled containers"
docker inspect --format '{{index .Config.Labels "com.docker.compose.project"}} workdir={{index .Config.Labels "com.docker.compose.project.working_dir"}} files={{index .Config.Labels "com.docker.compose.project.config_files"}}' mushukistan-nginx 2>/dev/null
docker ps -a --filter label=com.docker.compose.project=mushukistan --format '{{.Names}}\t{{.ID}}\t{{.Image}}\t{{.Label "com.docker.compose.service"}}'
section "release directories (listing only)"
ls -ldt /opt/mushukistan-releases/* 2>&1 | head -15
section "docker networks and nginx image"
docker inspect --format 'image={{.Config.Image}} networks={{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' mushukistan-nginx 2>/dev/null
section "PostgreSQL / PostGIS versions (read-only SQL)"
docker exec mushukistan-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "BEGIN READ ONLY; SELECT version(); SELECT postgis_full_version(); COMMIT;"' 2>&1 | cut -c1-200
section "alembic revision (read-only SQL)"
docker exec mushukistan-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "BEGIN READ ONLY; SELECT version_num FROM alembic_version; COMMIT;"' 2>&1
section "row counts for the restore comparison (read-only)"
docker exec mushukistan-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "BEGIN READ ONLY; SELECT '"'"'users'"'"', count(*) FROM users; SELECT '"'"'posts'"'"', count(*) FROM posts; SELECT '"'"'lost_pets'"'"', count(*) FROM lost_pets; SELECT '"'"'adoption_posts'"'"', count(*) FROM adoption_posts; SELECT '"'"'comments'"'"', count(*) FROM comments; COMMIT;"' 2>&1
section "database size"
docker exec mushukistan-db sh -c 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "BEGIN READ ONLY; SELECT pg_size_pretty(pg_database_size(current_database())); COMMIT;"' 2>&1
section "backup readiness (listing only, nothing created or read)"
ls -ld /root/mushukistan-backups 2>&1
ls -l --time-style=long-iso /root/mushukistan-backups 2>&1 | tail -8
crontab -l 2>&1 | grep -i -E "dump|backup" | sed 's/[A-Za-z0-9+\/=_-]\{24,\}/<redacted>/g'
systemctl list-timers --all 2>/dev/null | grep -i -E "backup|dump"
section "configuration presence (names only: set / unset)"
for v in APP_ENV APP_DEBUG RATE_LIMIT_ENABLED JWT_SECRET_KEY POSTGRES_PASSWORD DATABASE_URL CORS_ALLOWED_ORIGINS PUBLIC_APP_BASE_URL RESEND_API_KEY RESEND_FROM_EMAIL GOOGLE_OAUTH_CLIENT_ID R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY R2_BUCKET R2_PUBLIC_BASE_URL FIREBASE_CREDENTIALS_FILE FIREBASE_PROJECT_ID PUSH_TOKEN_ENCRYPTION_KEY POSTHOG_PROJECT_TOKEN POSTHOG_HOST TRUSTED_PROXY_CIDRS ENABLE_API_DOCS CONTACT_REVEAL_MAX_PER_DAY CONTACT_REVEAL_MAX_PER_WEEK CONTACT_LEGACY_DETAIL_ENABLED; do
  if [ -n "$(docker exec mushukistan-backend printenv "$v" 2>/dev/null)" ]; then echo "$v: set"; else echo "$v: unset"; fi
done
printf 'APP_ENV value (non-secret): '; docker exec mushukistan-backend printenv APP_ENV 2>/dev/null
printf 'APP_DEBUG value (non-secret): '; docker exec mushukistan-backend printenv APP_DEBUG 2>/dev/null
printf 'uvicorn workers (process count): '; docker exec mushukistan-backend sh -c 'ps -eo args | grep -c "[u]vicorn"' 2>/dev/null
section "nginx: does /api get cached? (config grep only)"
docker exec mushukistan-nginx sh -c 'grep -rn "proxy_cache" /etc/nginx 2>/dev/null | head -5; nginx -T 2>/dev/null | grep -c "X-Forwarded-For"' 2>&1
echo; echo "done (read-only)"
