#!/usr/bin/env bash
# Runs INSIDE the disposable "server" container started by e2e_tls_renewal.sh. Do not run on a real host.
# Layout: /work/repo has scripts/tls and infrastructure/nginx/default.conf from the repository.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
S=https://localhost:14000/dir
CN=mushukistan.uz
HOSTS="mushukistan.uz www.mushukistan.uz api.mushukistan.uz"
NGX_IP=10.30.50.10
REL_A=/opt/mushukistan-releases/rel-a/infrastructure/certbot/www      # the release-relative dir Nginx mounts today
REL_B=/var/www/certbot                                                # the stable dir of the next release
TLS=/work/repo/scripts/tls
fail=0; n=0
pass() { n=$((n+1)); echo "E2E PASS  $1"; }
bad()  { n=$((n+1)); echo "E2E FAIL  $1"; fail=1; }
expect() { if [ "$2" = "$3" ]; then pass "$1"; else bad "$1 (got '$2', want '$3')"; fi; }
contains() { if grep -qF -- "$3" <<<"$2"; then pass "$1"; else bad "$1 (missing '$3')"; fi; }
section() { echo; echo "=== $1"; }
pty() { printf '%s\n' "$1" | script -qec "$2" /dev/null; }
conf=/etc/letsencrypt/renewal/$CN.conf

section "setup: packages, docker daemon, ACME test server (Pebble + mock DNS)"
apt-get update -qq >/dev/null
apt-get install -y -qq docker.io certbot curl openssl ca-certificates iproute2 util-linux iptables procps >/dev/null 2>&1
update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true
(dockerd >/var/log/dockerd.log 2>&1 &)
for _ in $(seq 1 60); do docker info >/dev/null 2>&1 && break; sleep 1; done
docker info >/dev/null 2>&1 || { echo "dockerd failed"; tail -5 /var/log/dockerd.log; exit 1; }
echo "certbot: $(certbot --version 2>&1)"
docker pull -q nginx:1.27-alpine >/dev/null
docker pull -q ghcr.io/letsencrypt/pebble:latest >/dev/null
docker pull -q ghcr.io/letsencrypt/pebble-challtestsrv:latest >/dev/null
docker create --name pebcp ghcr.io/letsencrypt/pebble:latest >/dev/null
docker cp pebcp:/test/certs/pebble.minica.pem /tmp/minica.pem && docker rm pebcp >/dev/null
export REQUESTS_CA_BUNDLE=/tmp/minica.pem
docker network create --subnet 10.30.50.0/24 acmenet >/dev/null
cat > /tmp/pebble-config.json <<'EOF'
{"pebble":{"listenAddress":"0.0.0.0:14000","managementListenAddress":"0.0.0.0:15000",
 "certificate":"/test/certs/localhost/cert.pem","privateKey":"/test/certs/localhost/key.pem",
 "httpPort":80,"tlsPort":443,"ocspResponderURL":"","externalAccountBindingRequired":false}}
EOF
docker run -d --name challtest --network acmenet --ip 10.30.50.3 ghcr.io/letsencrypt/pebble-challtestsrv:latest \
  -defaultIPv4 10.30.50.1 -defaultIPv6 "" -http01 "" -https01 "" -tlsalpn01 "" >/dev/null
docker run -d --name pebble --network acmenet --ip 10.30.50.2 -p 14000:14000 -p 15000:15000 \
  -e PEBBLE_VA_NOSLEEP=1 -e PEBBLE_WFE_NONCEREJECT=0 -e PEBBLE_AUTHZREUSE=0 -v /tmp/pebble-config.json:/tmp/pebble-config.json:ro ghcr.io/letsencrypt/pebble:latest \
  -config /tmp/pebble-config.json -dnsserver 10.30.50.3:8053 >/dev/null
for _ in $(seq 1 40); do curl -s --cacert /tmp/minica.pem $S >/dev/null 2>&1 && break; sleep 1; done
if curl -s --cacert /tmp/minica.pem $S | grep -q newNonce; then pass "ACME test server (Pebble) is up"
else bad "Pebble did not start"; docker ps -a --format '{{.Names}} {{.Status}}'; docker logs pebble 2>&1 | tail -15; curl -sv --cacert /tmp/minica.pem $S 2>&1 | tail -8; fi

section "initial certificate with the OLD method (standalone), like the production history"
certbot certonly --standalone --non-interactive --agree-tos -m e2e@example.test --server $S \
  --cert-name $CN --key-type ecdsa $(for h in $HOSTS; do printf -- '-d %s ' "$h"; done) >/tmp/issue.log 2>&1 \
  && pass "initial standalone issuance succeeded (no web server running yet)" || { bad "initial issuance failed"; tail -15 /tmp/issue.log; }
expect "lineage authenticator is standalone" "$(sed -nE 's/^authenticator *= *([^ ]+).*/\1/p' $conf)" "standalone"
cp -p $conf /tmp/conf.original; ORIG_HASH="$(sha256sum < $conf)"
for h in $HOSTS; do curl -s -X POST -d "{\"host\":\"$h\",\"addresses\":[\"$NGX_IP\"]}" http://10.30.50.3:8055/add-a >/dev/null; done

section "start Nginx with the repository's REAL config and a release-relative ACME mount"
mkdir -p /srv/web /srv/landing $REL_A /opt/mushukistan-releases/rel-a
echo '<html>flutter</html>' > /srv/web/index.html; echo '<html>landing</html>' > /srv/landing/index.html
docker run -d --name backend --network acmenet --network-alias backend nginx:1.27-alpine >/dev/null
start_nginx() { # acme-host-dir
  docker rm -f mushukistan-nginx >/dev/null 2>&1 || true
  docker run -d --name mushukistan-nginx --network acmenet --ip $NGX_IP -p 80:80 -p 443:443 \
    -v /work/repo/infrastructure/nginx/default.conf:/etc/nginx/conf.d/default.conf:ro \
    -v /srv/web:/usr/share/nginx/html:ro -v /srv/landing:/var/www/landing:ro \
    -v /etc/letsencrypt:/etc/letsencrypt:ro -v "$1":/var/www/certbot:ro nginx:1.27-alpine >/dev/null
  for _ in $(seq 1 30); do curl -sk --resolve mushukistan.uz:443:$NGX_IP -o /dev/null https://mushukistan.uz/ && return 0; sleep 1; done; return 1
}
start_nginx $REL_A && pass "Nginx is serving HTTPS with the real configuration" || bad "Nginx failed to start"
serial() { echo | openssl s_client -connect $NGX_IP:443 -servername mushukistan.uz 2>/dev/null | openssl x509 -noout -serial | cut -d= -f2; }
export TLS_CONNECT=$NGX_IP HTTP_CONNECT=$NGX_IP

section "T1 root cause: standalone renewal cannot work while Nginx holds port 80"
out="$(certbot -q renew --no-random-sleep-on-renew --force-renewal 2>&1)"; rc=$?
[ $rc -ne 0 ] && pass "renewal fails (exit $rc)" || bad "renewal unexpectedly succeeded"
contains "failure reason is the port-80 conflict" "$out" "Could not bind TCP port 80"
contains "Docker's proxy owns port 80 on the host" "$(ss -ltnp | grep ':80 ')" "docker-proxy"

section "T2 HTTP-01 routing for all three hostnames"
for h in $HOSTS; do
  expect "$h: ACME path reaches the ACME location (404, no redirect)" "$(curl -s -o /dev/null -H "Host: $h" -w '%{http_code}' http://$NGX_IP/.well-known/acme-challenge/x)" "404"
  expect "$h: everything else redirects to HTTPS" "$(curl -s -o /dev/null -H "Host: $h" -w '%{http_code}' http://$NGX_IP/)" "301"
done
bash $TLS/check-tls.sh --acme >/tmp/c1.log 2>&1 && pass "check-tls --acme passes" || { bad "check-tls --acme"; cat /tmp/c1.log; }

section "T3 the detector flags the broken state"
bash $TLS/check-tls.sh --server >/tmp/c2.log 2>&1 && bad "check-tls --server should FAIL before the fix" || pass "check-tls --server FAILS while authenticator is standalone"
contains "detector names the cause" "$(cat /tmp/c2.log)" "authenticator is 'standalone'"

section "T4 dry run changes nothing; a webroot Nginx does not serve is refused"
bash $TLS/set-webroot.sh $REL_A >/tmp/s1.log 2>&1; rc=$?
expect "dry run exits 0" "$rc" "0"
contains "dry run prints the plan" "$(cat /tmp/s1.log)" "DRY RUN complete"
expect "renewal config untouched by the dry run" "$(sha256sum < $conf)" "$ORIG_HASH"
out="$(bash $TLS/set-webroot.sh /var/www/not-mounted 2>&1)"; rc=$?
[ $rc -ne 0 ] && pass "an unmounted webroot is refused" || bad "unmounted webroot accepted"
contains "refusal explains why" "$out" "would never be served"
out="$(printf 'wrong\n' | script -qec "CERTBOT_SERVER=$S bash $TLS/set-webroot.sh $REL_A --execute" /dev/null)"
contains "wrong confirmation aborts" "$out" "confirmation did not match"
expect "config untouched after a wrong confirmation" "$(sha256sum < $conf)" "$ORIG_HASH"

section "T5 safe failure: if validation cannot succeed the config is left unchanged"
out="$(printf 'TLS-WEBROOT %s\n' "$REL_A" | script -qec "CERTBOT_SERVER=https://localhost:1/dir bash $TLS/set-webroot.sh $REL_A --execute" /dev/null)"
contains "staging-validation failure is reported" "$out" "staging validation failed"
expect "config unchanged after the failed validation" "$(sha256sum < $conf)" "$ORIG_HASH"
[ ! -e /etc/letsencrypt/renewal-hooks/deploy/mushukistan-reload-nginx.sh ] && pass "no hook installed by a failed attempt" || bad "hook left behind by a failed attempt"

section "T6 apply: standalone -> webroot with staging-style validation, hook installed"
out="$(printf 'TLS-WEBROOT %s\n' "$REL_A" | script -qec "CERTBOT_SERVER=$S bash $TLS/set-webroot.sh $REL_A --execute" /dev/null)"
echo "$out" | tail -12
expect "authenticator is now webroot" "$(sed -nE 's/^authenticator *= *([^ ]+).*/\1/p' $conf)" "webroot"
for h in $HOSTS; do expect "$h mapped to the webroot" "$(awk '/^\[\[webroot_map\]\]/{f=1;next} /^\[/{f=0} f' $conf | tr -d ' ' | sed -nE "s/^$h=//p")" "$REL_A"; done
[ -x /etc/letsencrypt/renewal-hooks/deploy/mushukistan-reload-nginx.sh ] && pass "deploy hook installed and executable" || bad "hook missing"
BK="$(ls /root/mushukistan-backups/tls/renewal-$CN.conf.* 2>/dev/null | head -1)"
[ -n "$BK" ] && [ "$(sha256sum < "$BK")" = "$ORIG_HASH" ] && pass "backup is byte-identical to the original config" || bad "backup missing or different"
expect "backup is private (mode 600)" "$(stat -c %a "$BK")" "600"

section "T7 automated checks pass after the fix"
bash $TLS/check-tls.sh --all >/tmp/c3.log 2>&1 && pass "check-tls --all passes (cert, acme, server, probe)" || { bad "check-tls --all"; cat /tmp/c3.log; }
grep -E "PASS|FAIL|WARN" /tmp/c3.log | sed 's/^/        /'

section "T8 real renewal with the exact timer command, ZERO downtime, no container restart"
ID1="$(docker inspect -f '{{.Id}}' mushukistan-nginx)"; ST1="$(docker inspect -f '{{.State.StartedAt}}' mushukistan-nginx)"; SER1="$(serial)"
rm -f /tmp/stop /tmp/codes; touch /tmp/codes
( while [ ! -f /tmp/stop ]; do curl -sk --max-time 3 --resolve mushukistan.uz:443:$NGX_IP -o /dev/null -w '%{http_code}\n' https://mushukistan.uz/ >> /tmp/codes 2>/dev/null || echo 000 >> /tmp/codes; sleep 0.05; done ) &
LOOP=$!
sleep 1
certbot -q renew --no-random-sleep-on-renew --force-renewal >/tmp/renew.log 2>&1; rc=$?
sleep 2; touch /tmp/stop; wait $LOOP 2>/dev/null
expect "renewal exit status" "$rc" "0"
SER2="$(serial)"
[ "$SER1" != "$SER2" ] && pass "Nginx now serves the NEW certificate (serial changed)" || bad "served certificate did not change"
expect "same Nginx container (not recreated)" "$(docker inspect -f '{{.Id}}' mushukistan-nginx)" "$ID1"
expect "Nginx not restarted (StartedAt unchanged)" "$(docker inspect -f '{{.State.StartedAt}}' mushukistan-nginx)" "$ST1"
total="$(wc -l < /tmp/codes)"; nok="$(grep -c '^200$' /tmp/codes)"
[ "$total" -gt 20 ] && pass "load probe made $total HTTPS requests during the renewal" || bad "too few probe requests ($total)"
expect "every request succeeded during renewal+reload (failures: $((total-nok)))" "$nok" "$total"
contains "deploy hook ran and reloaded Nginx" "$(grep -h 'mushukistan-reload-nginx' /var/log/letsencrypt/letsencrypt.log /tmp/renew.log 2>/dev/null)" "reloaded mushukistan-nginx"

section "T9 next release: Nginx is recreated with the STABLE mount; the detector catches the drift, one command fixes it"
mkdir -p $REL_B; start_nginx $REL_B && pass "Nginx recreated with /var/www/certbot (as the repo compose file does)" || bad "recreate failed"
bash $TLS/check-tls.sh --server >/tmp/c4.log 2>&1 && bad "drift not detected" || pass "check-tls --server FAILS: renewal webroot no longer matches Nginx"
contains "detector prints the exact remedy" "$(cat /tmp/c4.log)" "set-webroot.sh '$REL_B'"
out="$(printf 'TLS-WEBROOT %s\n' "$REL_B" | script -qec "CERTBOT_SERVER=$S bash $TLS/set-webroot.sh $REL_B --execute" /dev/null)"
bash $TLS/check-tls.sh --all >/tmp/c5.log 2>&1 && pass "after set-webroot on the stable path every check passes" || { bad "checks after the switch"; cat /tmp/c5.log; }
SER3="$(serial)"; ID2="$(docker inspect -f '{{.Id}}' mushukistan-nginx)"
certbot -q renew --no-random-sleep-on-renew --force-renewal >/tmp/renew2.log 2>&1 && pass "forced renewal succeeds with the stable webroot" || { bad "renewal with the stable webroot"; cat /tmp/renew2.log | tail; }
sleep 2   # the reload is graceful: give the new workers a moment (same as in T8)
[ "$(serial)" != "$SER3" ] && pass "new certificate served after the second renewal" || bad "no new certificate"
contains "deploy hook reloaded Nginx after the second renewal" "$(cat /tmp/renew2.log; grep -h 'mushukistan-reload-nginx' /var/log/letsencrypt/letsencrypt.log | tail -3)" "reloaded mushukistan-nginx"
expect "Nginx container unchanged by the renewal" "$(docker inspect -f '{{.Id}}' mushukistan-nginx)" "$ID2"
ls /var/www/certbot/.well-known/acme-challenge/ >/dev/null 2>&1 && pass "challenge directory lives under the stable webroot" || bad "no challenge dir under the stable webroot"

section "T10 rollback restores the original renewal config byte for byte"
out="$(printf 'TLS-ROLLBACK\n' | script -qec "bash $TLS/set-webroot.sh --rollback $BK" /dev/null)"
expect "config identical to the original after rollback" "$(sha256sum < $conf)" "$ORIG_HASH"

echo
[ "$fail" -eq 0 ] && echo "E2E-TLS ALL PASSED ($n checks)" || echo "E2E-TLS FAILURES"
exit "$fail"
