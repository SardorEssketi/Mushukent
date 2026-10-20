#!/usr/bin/env bash
# Switch the certificate lineage from `standalone` (needs port 80, impossible behind Nginx) to the
# `webroot` authenticator, and install the Nginx-reload deploy hook. Run ON THE SERVER as root.
# No container is stopped, restarted or recreated; Nginx is only reloaded (by the hook) after a
# real renewal.
#
#   set-webroot.sh <webroot>                         # dry run: read-only checks, prints the plan
#   set-webroot.sh <webroot> --execute               # typed confirmation, then applies
#   set-webroot.sh --rollback <backup-file>          # typed confirmation, restores the renewal config
#
# <webroot> must be the host directory that Nginx ALREADY serves as /var/www/certbot (the script
# reads the container's mount and refuses anything else). After a release that changes that mount
# (for example to the stable /var/www/certbot), run it again with the new path.
#
# Safety: (1) the new method is first validated with `certbot certonly --dry-run --force-renewal`
# against the CA's STAGING environment, which saves nothing; (2) the renewal config is backed up and
# rewritten deterministically; (3) the saved config is validated again with the exact timer path
# (`certbot renew --dry-run`); (4) if any step fails the backup is restored automatically.
# (`certbot reconfigure` is not used: certbot 2.9 rejects domain/webroot-map arguments there.)
# Environment (tests only): LE_DIR, CERT_NAME, NGINX_CONTAINER, DOCKER_BIN, CERTBOT_SERVER,
# BACKUP_DIR, PROBE_HOST (address to probe, default 127.0.0.1).
set -euo pipefail
umask 077

LE_DIR="${LE_DIR:-/etc/letsencrypt}"; CERT_NAME="${CERT_NAME:-mushukistan.uz}"
NGINX_CONTAINER="${NGINX_CONTAINER:-mushukistan-nginx}"; DOCKER="${DOCKER_BIN:-docker}"
BACKUP_DIR="${BACKUP_DIR:-/root/mushukistan-backups/tls}"
HOOK_SRC="$(cd "$(dirname "$0")" && pwd)/reload-nginx.sh"
HOOK_DST="$LE_DIR/renewal-hooks/deploy/mushukistan-reload-nginx.sh"
conf="$LE_DIR/renewal/$CERT_NAME.conf"
die() { echo "ERROR: $*" >&2; exit 1; }
ok()  { echo "ok    $*"; }

webroot=""; execute=0; rollback=""
while [ $# -gt 0 ]; do
  case "$1" in
    --execute) execute=1; shift ;;
    --rollback) rollback="${2:?--rollback needs a backup file}"; shift 2 ;;
    -h|--help) sed -n '2,23p' "$0"; exit 0 ;;
    -*) die "unknown argument: $1" ;;
    *) [ -z "$webroot" ] || die "only one webroot may be given"; webroot="$1"; shift ;;
  esac
done
[ "$(id -u)" -eq 0 ] || [ -n "${ALLOW_NON_ROOT:-}" ] || die "run as root on the server"

confirm() { # phrase
  [ -t 0 ] || die "this needs an interactive terminal (ssh -t) so a human can confirm"
  printf 'Type "%s" to continue: ' "$1"; read -r answer
  [ "$answer" = "$1" ] || die "confirmation did not match; nothing changed"
}

if [ -n "$rollback" ]; then
  [ -f "$rollback" ] || die "backup file not found: $rollback"
  grep -q '^\[renewalparams\]' "$rollback" || die "$rollback does not look like a certbot renewal config"
  echo "Restoring $conf from $rollback"; confirm "TLS-ROLLBACK"
  cp -p "$conf" "$conf.before-rollback.$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$rollback" "$conf"
  ok "restored. NOTE: a restored 'standalone' config will fail again while Nginx holds port 80."
  exit 0
fi

[ -n "$webroot" ] || die "webroot path required (see --help)"
case "$webroot" in /*) ;; *) die "webroot must be an absolute path" ;; esac
command -v certbot >/dev/null || die "certbot is not installed"
command -v openssl >/dev/null || die "openssl is not installed"
[ -r "$conf" ] || die "renewal config not found: $conf"
[ -x "$HOOK_SRC" ] || die "missing hook script $HOOK_SRC"

echo "== 1. current state"
auth="$(sed -nE 's/^authenticator *= *([^ ]+).*/\1/p' "$conf" | head -1)"
ok "authenticator now: ${auth:-unknown}"
sans="$(openssl x509 -in "$LE_DIR/live/$CERT_NAME/cert.pem" -noout -text 2>/dev/null | grep -oE 'DNS:[^, ]+' | cut -d: -f2 | sort -u | tr '\n' ' ')"
[ -n "$sans" ] || die "could not read the certificate's hostnames"
ok "hostnames on the certificate: $sans"

echo "== 2. the webroot must be what Nginx really serves"
src="$($DOCKER inspect -f '{{range .Mounts}}{{if eq .Destination "/var/www/certbot"}}{{.Source}}{{end}}{{end}}' "$NGINX_CONTAINER" 2>/dev/null)" || true
[ -n "$src" ] || die "cannot read the /var/www/certbot mount of $NGINX_CONTAINER"
want="$(readlink -f "$src")"; have="$(readlink -f "$webroot" 2>/dev/null || echo "$webroot")"
[ "$want" = "$have" ] || die "Nginx serves /var/www/certbot from '$want', not '$have'. A challenge written elsewhere would never be served."
ok "Nginx serves /var/www/certbot from $want"
[ -d "$webroot" ] || { [ "$execute" -eq 1 ] || echo "note  $webroot does not exist yet (would be created)"; }

# certbot 2.9 refuses -d in `reconfigure`, so the hostname -> webroot mapping is given as JSON
map_json="{"; for d in $sans; do map_json+="\"$d\":\"$webroot\","; done; map_json="${map_json%,}}"
echo "== 3. plan"
echo "backup   : $BACKUP_DIR/renewal-$CERT_NAME.conf.<timestamp>   (private, mode 600)"
echo "hook     : $HOOK_DST   (nginx -t && nginx -s reload; no container restart)"
echo "validate1 : certbot certonly --dry-run --force-renewal --cert-name $CERT_NAME --webroot -w $webroot $(for d in $sans; do printf -- '-d %s ' "$d"; done)  (CA staging, saves nothing)"
echo "rewrite   : $conf  -> authenticator = webroot, webroot_path, [[webroot_map]] for every hostname"
echo "validate2 : certbot renew --cert-name $CERT_NAME --dry-run   (the exact timer path; restores the backup on failure)"
if [ "$execute" -ne 1 ]; then echo "DRY RUN complete: nothing was changed."; exit 0; fi

confirm "TLS-WEBROOT $webroot"
mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
bk="$BACKUP_DIR/renewal-$CERT_NAME.conf.$(date -u +%Y%m%dT%H%M%SZ)"
cp -p "$conf" "$bk"; chmod 600 "$bk"; ok "backed up the renewal config to $bk"
before="$(sha256sum < "$conf")"
mkdir -p "$webroot"; chmod 755 "$webroot"

server_args=(); [ -z "${CERTBOT_SERVER:-}" ] || server_args=(--server "$CERTBOT_SERVER")
restore() { cp -p "$bk" "$conf"; echo "restored the renewal config from the backup"; }

echo "== validation 1: the webroot method against the CA staging environment (nothing is saved)"
dargs=(certonly --dry-run --force-renewal --non-interactive --cert-name "$CERT_NAME" --webroot -w "$webroot")
for d in $sans; do dargs+=(-d "$d"); done
certbot "${dargs[@]}" "${server_args[@]}" || die "staging validation failed; the renewal config was NOT changed (backup: $bk)"
ok "staging validation passed for every hostname"

echo "== rewriting the renewal config"
tmp="$(mktemp)"
awk -v wr="$webroot" -v sans="$sans" '
  /^\[\[webroot_map\]\]/ {skip=1; next}
  skip && /^\[/ {skip=0}
  skip {next}
  /^webroot_path *=/ {next}
  /^authenticator *=/ {print "authenticator = webroot"; print "webroot_path = " wr ","; next}
  {print}
  END {print "[[webroot_map]]"; n=split(sans, a, " "); for (i=1;i<=n;i++) print a[i] " = " wr}
' "$conf" > "$tmp"
grep -q '^authenticator = webroot' "$tmp" || { rm -f "$tmp"; die "rewrite produced an unexpected config; nothing changed"; }
cat "$tmp" > "$conf"; rm -f "$tmp"

echo "== validation 2: the exact timer path against the saved config"
if ! certbot renew --cert-name "$CERT_NAME" --dry-run --non-interactive "${server_args[@]}"; then
  restore; die "validation of the saved config failed; the original config was restored (backup: $bk)"
fi
ok "dry-run renewal with the saved config passed"

# Installed last, so a failed attempt leaves nothing but the backup file behind.
mkdir -p "$(dirname "$HOOK_DST")"; install -m 0755 -o root -g root "$HOOK_SRC" "$HOOK_DST" 2>/dev/null || install -m 0755 "$HOOK_SRC" "$HOOK_DST"
ok "installed the deploy hook"
echo "== 4. result"
grep -E '^(authenticator|webroot_path)|=' "$conf" | grep -vE '^(account|server|key_type|version|archive_dir|cert|privkey|chain|fullchain|pref_chal)' | sed -E 's/^/    /'
ok "renewal config now uses webroot. Rollback: set-webroot.sh --rollback $bk"
echo "Verify: scripts/tls/check-tls.sh --all"
