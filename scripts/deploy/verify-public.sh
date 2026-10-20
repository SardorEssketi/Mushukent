#!/usr/bin/env bash
# Read-only public smoke test of https://mushukistan.uz and https://api.mushukistan.uz.
# Only GET/HEAD requests. No login, no data written, TLS is always verified.
#
#   scripts/deploy/verify-public.sh [--flutter-dir frontend/build/web]
#
# --flutter-dir: also require the served /main.dart.js to match the SHA-256 of the
# local build (proves the intended Flutter bundle is live).
# For the deep artifact/header comparison use website/tool/check_production_http.py.
# Exit code 0 only when every check passed.
set -uo pipefail

WEB_BASE="${WEB_BASE:-https://mushukistan.uz}"
API_BASE="${API_BASE:-https://api.mushukistan.uz}"
flutter_dir=""

while [ $# -gt 0 ]; do
  case "$1" in
    --flutter-dir) flutter_dir="${2:?--flutter-dir needs a path}"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
fail=0
pass() { printf 'PASS  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fail=1; }

# fetch URL -> sets $code and writes headers to $tmp/h, body to $tmp/b
fetch() { # url [max-seconds]; the 4.7 MB main.dart.js needs a long limit on slow links
  code="$(curl -sS --max-time "${2:-30}" -o "$tmp/b" -D "$tmp/h" -w '%{http_code}' "$1" 2>"$tmp/err")" || code="000"
}
expect_status() { # url expected [label] [max-seconds]
  fetch "$1" "${4:-30}"
  if [ "$code" = "$2" ]; then pass "${3:-$1} -> $code"; else bad "${3:-$1} -> $code (expected $2)"; fi
}
expect_no_store() { # url (call right after expect_status for the same url)
  if [ "$code" = "200" ] && grep -qi '^cache-control:.*no-store' "$tmp/h"; then pass "$1 sends no-store"; else bad "$1 missing Cache-Control: no-store (status $code)"; fi
}

expect_status "$API_BASE/api/v1/health" 200 "API health"
expect_status "$WEB_BASE/health" 200 "Web /health proxy"
expect_status "$WEB_BASE/" 200 "Landing /"
expect_no_store "/"
expect_status "$WEB_BASE/feed" 200 "Flutter /feed"
expect_status "$WEB_BASE/map" 200 "Flutter /map"
expect_status "$WEB_BASE/index.html" 200 "Flutter shell"
expect_no_store "/index.html"
expect_status "$WEB_BASE/flutter_bootstrap.js" 200 "flutter_bootstrap.js"
expect_no_store "/flutter_bootstrap.js"
expect_status "$WEB_BASE/main.dart.js" 200 "main.dart.js" 180
expect_no_store "/main.dart.js"
if [ -n "$flutter_dir" ]; then
  want="$(sha256sum "$flutter_dir/main.dart.js" | cut -d' ' -f1)"
  got="$(sha256sum "$tmp/b" | cut -d' ' -f1)"
  [ "$want" = "$got" ] && pass "main.dart.js SHA-256 matches local build ($want)" \
    || bad "main.dart.js SHA-256 differs: served $got, local $want"
fi
for p in /privacy /child-safety /delete-account /robots.txt /sitemap.xml; do
  expect_status "$WEB_BASE$p" 200
done
fetch "${WEB_BASE/https:/http:}/"
case "$code" in 301|308) pass "http -> https redirect ($code)" ;; *) bad "http redirect gave $code" ;; esac
fetch "$API_BASE/docs"
[ "$code" != "200" ] && pass "API docs not public ($code)" || bad "API /docs is public (ENABLE_API_DOCS must be false)"

if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "$fail"
