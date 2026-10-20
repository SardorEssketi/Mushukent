#!/usr/bin/env bash
# Automated checks for Mushukistan TLS and automatic renewal. Read-only except --probe, which
# writes and removes one tiny token file in the ACME webroot.
#
#   check-tls.sh                 # = --cert --acme (public checks, run from anywhere)
#   check-tls.sh --cert          # certificate days left for every hostname (WARN < 21, FAIL < 14)
#   check-tls.sh --acme          # HTTP-01 routing: /.well-known/acme-challenge/ must reach Nginx's ACME
#                                # location (404 for an unknown token), never a redirect or an error
#   check-tls.sh --server        # ON THE SERVER: renewal config, webroot == Nginx mount, hook, timer
#   check-tls.sh --probe         # ON THE SERVER: end-to-end token write -> HTTP fetch -> delete
#   check-tls.sh --all           # everything above
# Exit status is non-zero if any check FAILS. Never prints keys or certificate contents.
set -uo pipefail

HOSTS="${TLS_HOSTS:-mushukistan.uz www.mushukistan.uz api.mushukistan.uz}"
WARN_DAYS="${WARN_DAYS:-21}"; FAIL_DAYS="${FAIL_DAYS:-14}"
LE_DIR="${LE_DIR:-/etc/letsencrypt}"; CERT_NAME="${CERT_NAME:-mushukistan.uz}"
NGINX_CONTAINER="${NGINX_CONTAINER:-mushukistan-nginx}"; DOCKER="${DOCKER_BIN:-docker}"
HOOK_NAME="mushukistan-reload-nginx.sh"
# Test hooks: connect to another address while keeping the real hostname for SNI / Host.
TLS_CONNECT="${TLS_CONNECT:-}"; TLS_PORT="${TLS_PORT:-443}"
HTTP_CONNECT="${HTTP_CONNECT:-}"; HTTP_PORT="${HTTP_PORT:-80}"

do_cert=0; do_acme=0; do_server=0; do_probe=0
[ $# -eq 0 ] && { do_cert=1; do_acme=1; }
while [ $# -gt 0 ]; do
  case "$1" in
    --cert) do_cert=1 ;; --acme) do_acme=1 ;; --server) do_server=1 ;; --probe) do_probe=1 ;;
    --all) do_cert=1; do_acme=1; do_server=1; do_probe=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac; shift
done

fail=0
pass() { printf 'PASS  %s\n' "$1"; }
warn() { printf 'WARN  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fail=1; }
conf="$LE_DIR/renewal/$CERT_NAME.conf"

if [ "$do_cert" -eq 1 ]; then
  command -v openssl >/dev/null || { bad "openssl is not installed"; do_cert=0; }
fi
if [ "$do_cert" -eq 1 ]; then
  for h in $HOSTS; do
    end="$(echo | openssl s_client -connect "${TLS_CONNECT:-$h}:$TLS_PORT" -servername "$h" 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)"
    if [ -z "$end" ]; then bad "$h: could not read the served certificate"; continue; fi
    days=$(( ( $(date -u -d "$end" +%s) - $(date -u +%s) ) / 86400 ))
    if   [ "$days" -lt "$FAIL_DAYS" ]; then bad "$h: certificate expires in $days days (renewal is overdue)"
    elif [ "$days" -lt "$WARN_DAYS" ]; then warn "$h: certificate expires in $days days (renewal should have happened at 30)"
    else pass "$h: certificate valid for $days more days"; fi
  done
fi

if [ "$do_acme" -eq 1 ]; then
  for h in $HOSTS; do
    code="$(curl -s -o /dev/null --max-time 15 -H "Host: $h" -w '%{http_code}' "http://${HTTP_CONNECT:-$h}:$HTTP_PORT/.well-known/acme-challenge/check-$RANDOM$RANDOM" || true)"
    case "$code" in
      404) pass "$h: HTTP-01 path reaches the ACME location (404 for an unknown token, no redirect)" ;;
      3??) bad  "$h: HTTP-01 path is REDIRECTED ($code): validation would fail" ;;
      *)   bad  "$h: HTTP-01 path returned '$code' (expected 404 from the ACME location)" ;;
    esac
  done
fi

# --- server-side helpers -------------------------------------------------------------
conf_value() { sed -nE "s/^$1 *= *([^ ,#]+).*/\1/p" "$conf" | head -1; }
webroot_map() { awk '/^\[\[webroot_map\]\]/{f=1;next} /^\[/{f=0} f && /=/{gsub(/ /,""); print}' "$conf"; }
mount_source() { $DOCKER inspect -f '{{range .Mounts}}{{if eq .Destination "/var/www/certbot"}}{{.Source}}{{end}}{{end}}' "$NGINX_CONTAINER" 2>/dev/null; }
resolve() { readlink -f "$1" 2>/dev/null || echo "$1"; }
san_list() { openssl x509 -in "$LE_DIR/live/$CERT_NAME/cert.pem" -noout -text 2>/dev/null | grep -oE 'DNS:[^, ]+' | cut -d: -f2 | sort -u; }

if [ "$do_server" -eq 1 ] || [ "$do_probe" -eq 1 ]; then
  [ -r "$conf" ] || { bad "cannot read $conf (run on the server as root)"; do_server=0; do_probe=0; }
fi

if [ "$do_server" -eq 1 ]; then
  auth="$(conf_value authenticator)"
  [ "$auth" = "webroot" ] && pass "renewal authenticator is webroot" || bad "renewal authenticator is '$auth' (standalone needs port 80 and cannot work behind Nginx)"
  src="$(mount_source)"
  [ -n "$src" ] && src="$(resolve "$src")"
  [ -n "$src" ] && pass "Nginx serves /var/www/certbot from $src" || bad "cannot read Nginx's /var/www/certbot mount ($NGINX_CONTAINER)"
  map="$(webroot_map)"
  sans="$(san_list)"
  [ -n "$sans" ] || bad "cannot read the certificate's hostnames from $LE_DIR/live/$CERT_NAME/cert.pem"
  for d in $sans; do
    p="$(printf '%s\n' "$map" | sed -nE "s/^$d=//p" | head -1)"
    if [ -z "$p" ]; then bad "$d: no webroot path in the renewal config"
    elif [ -n "$src" ] && [ "$(resolve "$p")" = "$src" ]; then pass "$d: renewal webroot equals Nginx's mount"
    else bad "$d: renewal webroot '$p' is NOT what Nginx serves ('${src:-unknown}'): run scripts/tls/set-webroot.sh '${src:-<path>}'"; fi
  done
  hook="$LE_DIR/renewal-hooks/deploy/$HOOK_NAME"
  [ -x "$hook" ] && pass "deploy hook installed ($HOOK_NAME)" || bad "deploy hook missing or not executable: $hook"
  if command -v systemctl >/dev/null && systemctl list-unit-files certbot.timer >/dev/null 2>&1; then
    [ "$(systemctl is-enabled certbot.timer 2>/dev/null)" = "enabled" ] && pass "certbot.timer is enabled" || bad "certbot.timer is not enabled"
    res="$(systemctl show certbot.service -p Result --value 2>/dev/null)"
    case "$res" in success|"") pass "last certbot.service run: ${res:-never ran}" ;; *) bad "last certbot.service run: $res (see journalctl -u certbot.service)" ;; esac
  else warn "systemd certbot.timer not present here (skipped)"; fi
fi

if [ "$do_probe" -eq 1 ]; then
  for h in $HOSTS; do
    p="$(webroot_map | sed -nE "s/^$h=//p" | head -1)"; [ -n "$p" ] || p="$(conf_value webroot_path)"
    if [ -z "$p" ] || [ ! -d "$p" ]; then bad "$h: webroot '$p' does not exist"; continue; fi
    tok="mk-probe-$RANDOM$RANDOM"; dir="$p/.well-known/acme-challenge"
    mkdir -p "$dir" && printf '%s' "$tok" > "$dir/$tok" && chmod 644 "$dir/$tok"
    got="$(curl -s --max-time 15 -H "Host: $h" "http://${HTTP_CONNECT:-$h}:$HTTP_PORT/.well-known/acme-challenge/$tok" || true)"
    rm -f "$dir/$tok"
    [ "$got" = "$tok" ] && pass "$h: probe file written to the webroot is served over HTTP" || bad "$h: probe file was NOT served (got '${got:0:40}')"
  done
fi

[ "$fail" -eq 0 ] && echo "ALL TLS CHECKS PASSED" || echo "SOME TLS CHECKS FAILED"
exit "$fail"
