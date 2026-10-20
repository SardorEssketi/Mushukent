"""Exercise the production Nginx config with real bundles on private test ports.

Requires Docker, Python 3.10+, and cryptography. The upstream is a disposable
echo server; no production API, database, secrets, or shared Compose stack is used.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import http.client
import json
import re
import ssl
import subprocess
import time
import uuid
from pathlib import Path
from urllib.parse import urlsplit

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID


def docker(*args: str) -> str:
    result = subprocess.run(["docker", *args], capture_output=True, text=True, timeout=90)
    if result.returncode:
        raise RuntimeError(f"docker {args[0]} failed: {result.stderr.strip()}")
    return (result.stdout + (result.stderr if args[0] in {"logs", "exec"} else "")).strip()


def certificate(directory: Path) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "mushukistan.uz")])
    now = dt.datetime.now(dt.timezone.utc)
    cert = (x509.CertificateBuilder().subject_name(name).issuer_name(name)
            .public_key(key.public_key()).serial_number(x509.random_serial_number())
            .not_valid_before(now - dt.timedelta(minutes=5))
            .not_valid_after(now + dt.timedelta(days=2))
            .add_extension(x509.SubjectAlternativeName([x509.DNSName("mushukistan.uz")]), critical=False)
            .sign(key, hashes.SHA256()))
    (directory / "fullchain.pem").write_bytes(cert.public_bytes(serialization.Encoding.PEM))
    (directory / "privkey.pem").write_bytes(key.private_bytes(
        serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
        serialization.NoEncryption()))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--flutter", required=True, type=Path)
    parser.add_argument("--website", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    flutter, website = args.flutter.resolve(), args.website.resolve()
    report_path = args.report.resolve()
    stage = report_path.parent / "nginx-fixture"
    stage.mkdir(parents=True, exist_ok=True)
    certificate(stage / "tls/live/mushukistan.uz")
    upstream = stage / "upstream.py"
    upstream.write_text('''from http.server import BaseHTTPRequestHandler, HTTPServer
import json
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        value = {"status": "ok"} if self.path == "/api/v1/health" else {
            "path": self.path, "method": self.command, "body": body,
            "host": self.headers.get("Host"), "proto": self.headers.get("X-Forwarded-Proto")}
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        if self.path.startswith("/media/"):
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
    do_POST = do_GET
HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
''', encoding="utf-8")
    tag = "landing-check-" + uuid.uuid4().hex[:10]
    network, backend, nginx = tag, tag + "-backend", tag + "-nginx"
    containers: list[str] = []
    report = {"checks": [], "passed": False}
    config = root / "infrastructure/nginx/default.conf"
    try:
        docker("network", "create", network)
        docker("run", "-d", "--name", backend, "--network", network,
               "--network-alias", "backend", "--mount", f"type=bind,src={upstream},dst=/upstream.py,readonly",
               "python:3.13-slim", "python", "/upstream.py")
        containers.append(backend)
        docker("run", "-d", "--name", nginx, "--network", network,
               "--publish", "127.0.0.1::443", "--publish", "127.0.0.1::80",
               "--mount", f"type=bind,src={config},dst=/etc/nginx/conf.d/default.conf,readonly",
               "--mount", f"type=bind,src={flutter},dst=/usr/share/nginx/html,readonly",
               "--mount", f"type=bind,src={website},dst=/var/www/landing,readonly",
               "--mount", f"type=bind,src={stage / 'tls'},dst=/etc/letsencrypt,readonly",
               "nginx:1.27-alpine")
        containers.append(nginx)
        report["nginx_syntax"] = docker("exec", nginx, "nginx", "-t")
        info = json.loads(docker("inspect", nginx))[0]
        https_port = int(info["NetworkSettings"]["Ports"]["443/tcp"][0]["HostPort"])
        http_port = int(info["NetworkSettings"]["Ports"]["80/tcp"][0]["HostPort"])
        context = ssl._create_unverified_context()  # disposable fixture certificate only

        def request(path: str, method: str = "GET", body: bytes | None = None,
                    host: str = "mushukistan.uz", tls: bool = True) -> tuple[int, dict, bytes]:
            conn = (http.client.HTTPSConnection("127.0.0.1", https_port, context=context, timeout=15)
                    if tls else http.client.HTTPConnection("127.0.0.1", http_port, timeout=15))
            conn.request(method, path, body=body, headers={"Host": host})
            response = conn.getresponse()
            result = response.status, dict((k.lower(), v) for k, v in response.getheaders()), response.read()
            conn.close()
            return result

        for attempt in range(40):
            try:
                if request("/")[0] == 200:
                    break
            except (OSError, http.client.HTTPException):
                pass
            time.sleep(.25)
        else:
            raise AssertionError("isolated Nginx did not start")

        expected_csp = re.findall(r'add_header Content-Security-Policy "([^"]+)" always;', config.read_text())[0]

        def security(headers: dict) -> None:
            assert headers.get("strict-transport-security") == "max-age=31536000; includeSubDomains"
            assert headers.get("x-content-type-options") == "nosniff"
            assert headers.get("x-frame-options") == "DENY"
            assert headers.get("referrer-policy") == "strict-origin-when-cross-origin"
            assert headers.get("content-security-policy") == expected_csp

        def check_file(path: str, file: Path, cache: str | None = None) -> None:
            status, headers, data = request(path)
            assert status == 200, (path, status)
            assert data == file.read_bytes(), f"wrong artifact at {path}"
            security(headers)
            if cache:
                assert cache in headers.get("cache-control", ""), (path, headers)
            report["checks"].append({"path": path, "status": status,
                                     "sha256": hashlib.sha256(data).hexdigest(),
                                     "cache_control": headers.get("cache-control")})

        for path, relative in [("/", "index.html"), ("/en/", "en/index.html"), ("/uz/", "uz/index.html")]:
            check_file(path, website / relative, "no-store")
        for path in ["/feed", "/map", "/posts/test-post", "/lost-pets/test-lost",
                     "/adoption-posts/test-adoption", "/users/test-user", "/login", "/register",
                     "/verify-email?token=test-only", "/notifications", "/notifications/settings",
                     "/profile/settings", "/legal/terms", "/unknown-product-route"]:
            check_file(path, flutter / "index.html", "no-store")
        for path in ["privacy", "child-safety", "delete-account"]:
            check_file("/" + path, flutter / path / "index.html")
        check_file("/delete-account/delete-account.js", flutter / "delete-account/delete-account.js", "no-store")
        for path in ["flutter_bootstrap.js", "main.dart.js", "version.json"]:
            check_file("/" + path, flutter / path, "no-store")
        check_file("/canvaskit/canvaskit.js", flutter / "canvaskit/canvaskit.js", "no-cache")
        check_file("/canvaskit/canvaskit.wasm", flutter / "canvaskit/canvaskit.wasm", "no-cache")
        check_file("/manifest.json", flutter / "manifest.json", "no-cache")
        manifest = json.loads(request("/manifest.json")[2])
        assert manifest["start_url"] == "/feed" and manifest["scope"] == "/"
        for name in ["robots.txt", "sitemap.xml"]:
            check_file("/" + name, website / name, "no-store")
        for asset in sorted((website / "landing-assets").iterdir()):
            check_file("/landing-assets/" + asset.name, asset, "immutable")
        for path in ["/landing-assets/missing.js", "/missing.js", "/canvaskit/missing.wasm"]:
            status, headers, data = request(path)
            assert status == 404 and b"flutter-startup" not in data, path
            security(headers)
            if path.startswith("/landing-assets/"):
                assert "no-store" in headers.get("cache-control", ""), (path, headers)
            report["checks"].append({"path": path, "status": status})
        for path in ["/en", "/uz"]:
            status, headers, _ = request(path)
            assert status == 308 and urlsplit(headers["location"]).path == path + "/"
            assert request(path + "/")[0] == 200
            report["checks"].append({"path": path, "status": status, "location": headers["location"]})
        for path in ["/ru", "/ru/"]:   # Russian moved to the root; the old URLs must keep working
            status, headers, _ = request(path)
            assert status == 301 and urlsplit(headers["location"]).path == "/", (path, status, headers.get("location"))
            report["checks"].append({"path": path, "status": status, "location": headers["location"]})
        assert b'<html lang="ru"' in request("/")[2] and b'<html lang="en"' in request("/en/")[2]
        status, headers, _ = request("/feed?test=1", tls=False)
        assert status == 301 and headers["location"] == "https://mushukistan.uz/feed?test=1"
        report["checks"].append({"path": "http:/feed?test=1", "status": status})
        for path, method, payload in [("/api/v1/probe?value=1", "GET", None),
                                      ("/api/v1/probe", "POST", b"test-request-body"),
                                      ("/media/probe.jpg?version=1", "GET", None)]:
            status, headers, data = request(path, method, payload)
            value = json.loads(data)
            assert status == 200 and value["path"] == path and value["method"] == method
            assert value["body"] == (payload or b"").decode()
            assert value["proto"] == "https" and value["host"] == "mushukistan.uz"
            security(headers)
            if path.startswith("/media/"):
                assert "immutable" in headers["cache-control"]
            report["checks"].append({"path": path, "status": status, "method": method})
        assert json.loads(request("/health")[2])["status"] == "ok"
        status, headers, data = request("/api/v1/health", host="api.mushukistan.uz")
        assert status == 200 and json.loads(data)["status"] == "ok"
        assert headers["content-security-policy"] == "default-src 'none'; frame-ancestors 'none';"
        report["passed"] = True
        print(f"Passed {len(report['checks'])} HTTP artifact/routing checks with the production Nginx config.")
    except Exception as error:
        report["error"] = str(error)
        raise
    finally:
        for container in reversed(containers):
            try:
                report[container + "_logs"] = docker("logs", container)
            except Exception as error:
                report[container + "_logs"] = str(error)
            docker("rm", "-f", container)
        try:
            docker("network", "rm", network)
        except Exception:
            pass
        report_path.parent.mkdir(parents=True, exist_ok=True)
        report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
