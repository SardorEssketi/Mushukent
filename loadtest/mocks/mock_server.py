"""Sink for the external services the backend calls during a load test.

Stands in for Cloudflare R2 (S3 API), PostHog (events + OTLP logs) and any other HTTP
dependency. Every request gets a 200 with an ETag after an optional delay, and is counted so
the run can report external call volume (R2 PUT/DELETE operations, bytes uploaded, PostHog
batches). ``GET /__stats`` returns the counters as JSON; ``POST /__reset`` clears them.

Standard library only, so it runs in any Python image.
"""

from __future__ import annotations

import json
import os
import threading
import time
from collections import Counter
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

LATENCY_SECONDS = float(os.getenv("MOCK_LATENCY_MS", "40")) / 1000.0
_lock = threading.Lock()
_counts: Counter[str] = Counter()
_bytes: Counter[str] = Counter()


def _bucket(method: str, host: str, path: str) -> str:
    if path.startswith("/i/v1/logs"):
        return "posthog_logs"
    if path.startswith(("/batch", "/capture", "/i/v0/e", "/e/", "/decide", "/flags")):
        return "posthog_events"
    return f"s3_{method.lower()}"


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # silence per-request logging
        return

    def _handle(self) -> None:
        if "chunked" in (self.headers.get("transfer-encoding") or "").lower():
            body = self._read_chunked()
        else:
            length = int(self.headers.get("content-length") or 0)
            body = self.rfile.read(length) if length else b""
        if self.path.startswith("/__stats"):
            with _lock:
                payload = json.dumps({"counts": dict(_counts), "bytes": dict(_bytes)}).encode()
            self._reply(200, payload, "application/json")
            return
        if self.path.startswith("/__reset"):
            with _lock:
                _counts.clear()
                _bytes.clear()
            self._reply(200, b"{}", "application/json")
            return
        key = _bucket(self.command, self.headers.get("host", ""), self.path)
        with _lock:
            _counts[key] += 1
            _bytes[key] += len(body)
        if LATENCY_SECONDS:
            time.sleep(LATENCY_SECONDS)
        if self.command == "DELETE":
            self._reply(204, b"", None)
        elif self.command == "HEAD" or key.startswith("s3_"):
            self._reply(200, b"", None)  # S3 PUT/HEAD answer with an empty body
        else:
            self._reply(200, b"{}", "application/json")

    def _read_chunked(self) -> bytes:
        """botocore streams PutObject bodies with aws-chunked/chunked encoding and trailers."""
        chunks = []
        while True:
            size_line = self.rfile.readline().strip()
            size = int(size_line.split(b";")[0] or b"0", 16)
            if size == 0:
                while self.rfile.readline().strip():  # trailers (checksums) until blank line
                    pass
                return b"".join(chunks)
            chunks.append(self.rfile.read(size))
            self.rfile.readline()

    def _reply(self, status: int, payload: bytes, content_type: str | None) -> None:
        self.send_response(status)
        self.send_header("ETag", '"00000000000000000000000000000000"')
        if content_type:
            self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if payload and self.command != "HEAD":
            self.wfile.write(payload)

    do_GET = do_POST = do_PUT = do_DELETE = do_HEAD = _handle


if __name__ == "__main__":
    server = ThreadingHTTPServer(("0.0.0.0", 9000), Handler)
    server.daemon_threads = True
    print("mock server on :9000", flush=True)
    server.serve_forever()
