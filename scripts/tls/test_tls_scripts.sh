#!/usr/bin/env bash
# Offline tests for scripts/tls/*: stub docker/certbot and a throwaway certificate; no network,
# no Docker daemon, nothing on a server. The end-to-end behaviour against a real ACME server is
# covered by e2e_tls_renewal.sh.
#   bash scripts/tls/test_tls_scripts.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
fails=0; total=0
check() { # description, expected(0|nonzero), needle, command...
  local desc="$1" want="$2" needle="$3"; shift 3
  local out rc good=1
  out="$("$@" 2>&1 </dev/null)"; rc=$?
  total=$((total+1))
  if [ "$want" = "0" ]; then [ $rc -eq 0 ] || good=0; else [ $rc -ne 0 ] || good=0; fi
  if [ -n "$needle" ] && ! grep -qF -- "$needle" <<<"$out"; then good=0; fi
  if [ $good -eq 1 ]; then echo "PASS  $desc"; else echo "FAIL  $desc (exit $rc)"; echo "$out" | tail -8 | sed 's/^/        /'; fails=$((fails+1)); fi
}
for s in check-tls reload-nginx set-webroot e2e_tls_renewal e2e_tls_inner; do check "syntax: $s.sh" 0 "" bash -n "$HERE/$s.sh"; done

# ---- fixture: Let's Encrypt-like directory with a SAN certificate ----
LE="$T/le"; mkdir -p "$LE/live/mushukistan.uz" "$LE/renewal" "$LE/renewal-hooks/deploy" "$T/webroot" "$T/other"
cat > "$T/openssl.cnf" <<'EOF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = mushukistan.uz
[v3]
subjectAltName = DNS:mushukistan.uz,DNS:www.mushukistan.uz,DNS:api.mushukistan.uz
EOF
openssl req -x509 -newkey rsa:2048 -nodes -days 40 -config "$T/openssl.cnf" \
  -keyout "$T/key.pem" -out "$LE/live/mushukistan.uz/cert.pem" >/dev/null 2>&1
write_conf() { # authenticator webroot
  { echo "[renewalparams]"; echo "account = abc"; echo "authenticator = $1"; echo "server = https://example.test/dir"
    if [ "$1" = webroot ]; then echo "webroot_path = $2,"; echo "[[webroot_map]]"; for h in mushukistan.uz www.mushukistan.uz api.mushukistan.uz; do echo "$h = $2"; done; fi; } > "$LE/renewal/mushukistan.uz.conf"
}
cat > "$T/docker" <<'EOF'
#!/usr/bin/env bash
echo "docker $*" >> "$STUB_LOG"
case "$*" in
  *"inspect"*) printf '%s\n' "${STUB_MOUNT:-}" ;;
  *"nginx -t"*) [ -n "${STUB_NGINX_T_FAIL:-}" ] && { echo "nginx: configuration test failed" >&2; exit 1; }; echo "syntax is ok" ;;
  *) : ;;
esac
EOF
chmod +x "$T/docker"
cat > "$T/certbot" <<'EOF'
#!/usr/bin/env bash
echo "certbot $*" >> "$STUB_LOG"; [ -n "${STUB_CERTBOT_FAIL:-}" ] && exit 1; exit 0
EOF
chmod +x "$T/certbot"
export STUB_LOG="$T/stub.log" DOCKER_BIN="$T/docker" LE_DIR="$LE" PATH="$T:$PATH" ALLOW_NON_ROOT=1
CT="$HERE/check-tls.sh"; SW="$HERE/set-webroot.sh"; RH="$HERE/reload-nginx.sh"

# ---- check-tls --server ----
write_conf webroot "$T/webroot"; install -m 755 "$RH" "$LE/renewal-hooks/deploy/mushukistan-reload-nginx.sh"
STUB_MOUNT="$T/webroot" check "server: webroot == nginx mount, hook present -> passes" 0 "renewal webroot equals Nginx's mount" bash "$CT" --server
STUB_MOUNT="$T/other" check "server: drift between renewal webroot and nginx mount FAILS" nonzero "NOT what Nginx serves" bash "$CT" --server
STUB_MOUNT="$T/other" check "server: drift message names the exact remedy" nonzero "set-webroot.sh '$T/other'" bash "$CT" --server
write_conf standalone ""
STUB_MOUNT="$T/webroot" check "server: standalone authenticator FAILS" nonzero "standalone needs port 80" bash "$CT" --server
write_conf webroot "$T/webroot"; rm "$LE/renewal-hooks/deploy/mushukistan-reload-nginx.sh"
STUB_MOUNT="$T/webroot" check "server: missing deploy hook FAILS" nonzero "deploy hook missing" bash "$CT" --server
install -m 755 "$RH" "$LE/renewal-hooks/deploy/mushukistan-reload-nginx.sh"
STUB_MOUNT="" check "server: unreadable nginx mount FAILS" nonzero "cannot read Nginx's /var/www/certbot mount" bash "$CT" --server

# ---- check-tls --acme against tiny local HTTP servers (python3 needed) ----
if command -v python3 >/dev/null || command -v python >/dev/null; then
  PY="$(command -v python3 || command -v python)"
  cat > "$T/srv.py" <<'EOF'
import http.server, sys
code = int(sys.argv[2])
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(code)
        if code == 301: self.send_header("Location", "https://example.test/")
        self.end_headers()
    def log_message(self, *a): pass
http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
EOF
  "$PY" "$T/srv.py" 18404 404 & P1=$!; "$PY" "$T/srv.py" 18301 301 & P2=$!; sleep 1
  HTTP_CONNECT=127.0.0.1 HTTP_PORT=18404 check "acme: 404 from the ACME location passes for all hosts" 0 "reaches the ACME location" bash "$CT" --acme
  HTTP_CONNECT=127.0.0.1 HTTP_PORT=18301 check "acme: a redirect on the challenge path FAILS" nonzero "REDIRECTED (301)" bash "$CT" --acme
  HTTP_CONNECT=127.0.0.1 HTTP_PORT=1 check "acme: unreachable port 80 FAILS" nonzero "returned" bash "$CT" --acme
  kill $P1 $P2 2>/dev/null
else echo "SKIP  acme routing tests (no python)"; fi

# ---- deploy hook ----
: > "$STUB_LOG"
check "hook: validates then reloads, container not restarted" 0 "reloaded mushukistan-nginx" bash "$RH"
check "hook: nginx -t runs before the reload" 0 "" bash -c "awk '/nginx -t/{a=NR} /nginx -s reload/{b=NR} END{exit !(a&&b&&a<b)}' '$STUB_LOG'"
check "hook: never restarts or recreates containers" nonzero "" grep -E " (restart|stop|rm|run|kill)( |$)" "$STUB_LOG"
: > "$STUB_LOG"
STUB_NGINX_T_FAIL=1 check "hook: a failing config test aborts and does NOT reload" nonzero "" bash "$RH"
check "hook: no reload was sent after the failed test" nonzero "" grep -q "nginx -s reload" "$STUB_LOG"

# ---- set-webroot ----
write_conf standalone ""; H0="$(sha256sum < "$LE/renewal/mushukistan.uz.conf")"
: > "$STUB_LOG"
STUB_MOUNT="$T/webroot" check "set-webroot: dry run succeeds and says so" 0 "DRY RUN complete" bash "$SW" "$T/webroot"
check "set-webroot: dry run did not touch certbot" nonzero "" grep -q "^certbot " "$STUB_LOG"
check "set-webroot: dry run left the config unchanged" 0 "" test "$(sha256sum < "$LE/renewal/mushukistan.uz.conf")" = "$H0"
STUB_MOUNT="$T/webroot" check "set-webroot: refuses a webroot Nginx does not serve" nonzero "would never be served" bash "$SW" "$T/other"
STUB_MOUNT="$T/webroot" check "set-webroot: refuses a relative path" nonzero "absolute path" bash "$SW" relative/path
STUB_MOUNT="$T/webroot" check "set-webroot: --execute without a terminal is refused" nonzero "interactive terminal" bash "$SW" "$T/webroot" --execute
check "set-webroot: rollback of a missing backup is refused" nonzero "not found" bash "$SW" --rollback "$T/nope"
check "set-webroot: rollback of a non-certbot file is refused" nonzero "does not look like" bash -c "echo junk > '$T/junk'; bash '$SW' --rollback '$T/junk'"
check "set-webroot: no certbot call happened in any refusal" nonzero "" grep -q "^certbot " "$STUB_LOG"

echo; echo "$((total-fails))/$total passed"
exit "$fails"
