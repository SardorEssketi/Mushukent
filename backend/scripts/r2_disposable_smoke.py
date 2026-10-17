"""Disposable Cloudflare R2 upload test.

Dry run by default: prints the unique object key it WOULD use and which variables are present
(names only, never values). Nothing is contacted.

    python scripts/r2_disposable_smoke.py                 # dry run
    python scripts/r2_disposable_smoke.py --execute       # real upload, check, delete

With --execute it uploads one 8x8 PNG to `release-smoke/<random>/smoke.png`, reads its metadata,
fetches it through R2_PUBLIC_BASE_URL (when set), then deletes it. The object name is random, so
it can never overwrite a user's media, and it is removed in a `finally` block. Run it only with
credentials the operator has approved for the target bucket (prefer a staging bucket first).
"""

from __future__ import annotations

import argparse
import os
import struct
import sys
import zlib
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from app.infrastructure.storage.r2 import R2ObjectStorage, R2StorageConfig  # noqa: E402

REQUIRED = ("R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET")

# urllib's default "Python-urllib/x" User-Agent is rejected by Cloudflare's Browser Integrity
# Check (HTTP 403, body "error code: 1010") on the public media domain, while browsers and the
# app are served normally. Identify the probe explicitly instead of weakening the protection.
USER_AGENT = "Mozilla/5.0 (compatible; MushukistanSmoke/1.0)"
SAFE_HEADERS = ("server", "content-type", "cache-control", "cf-cache-status", "cf-ray")


def _png() -> bytes:
    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    rows = b"".join(b"\x00" + b"\x20\x80\xc0" * 8 for _ in range(8))
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", 8, 8, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(rows))
        + chunk(b"IEND", b"")
    )


def public_read(url: str, *, opener=urlopen) -> tuple[bool, str]:
    """Fetch `url` and describe the outcome without echoing the URL, body or credentials."""
    request = Request(url, headers={"User-Agent": USER_AGENT})  # noqa: S310 - https URL
    try:
        with opener(request, timeout=15) as response:
            status = response.status
            return status == 200, f"{'PASS' if status == 200 else 'FAIL'} public read ({status})"
    except HTTPError as exc:
        headers = {k: exc.headers.get(k) for k in SAFE_HEADERS if exc.headers.get(k)}
        hint = ""
        if exc.code == 403:
            hint = " (403 from the edge: check Cloudflare WAF / Browser Integrity Check rules)"
        return False, f"FAIL public read HTTP {exc.code} {exc.reason}; headers={headers}{hint}"
    except URLError as exc:
        return False, f"FAIL public read {type(exc.reason).__name__} (DNS/TLS/connection)"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()

    key = f"release-smoke/{uuid4().hex}/smoke.png"
    missing = [name for name in REQUIRED if not os.getenv(name)]
    print(f"object key: {key}")
    print(f"variables present: {[n for n in REQUIRED if os.getenv(n)]}; missing: {missing}")
    if not args.execute:
        print("dry run: nothing was contacted. Re-run with --execute to upload and delete.")
        return 0 if not missing else 2
    if missing:
        print("refusing to run: credentials incomplete")
        return 2

    config = R2StorageConfig(
        account_id=os.environ["R2_ACCOUNT_ID"],
        access_key_id=os.environ["R2_ACCESS_KEY_ID"],
        secret_access_key=os.environ["R2_SECRET_ACCESS_KEY"],
        bucket=os.environ["R2_BUCKET"],
        public_base_url=os.getenv("R2_PUBLIC_BASE_URL") or None,
    )
    storage = R2ObjectStorage(config)
    ok = True
    try:
        assert storage.exists(key) is False, "key unexpectedly exists"
        uploaded = storage.upload(
            key=key, content=_png(), content_type="image/png", cache_control="no-cache"
        )
        print("PASS upload")
        assert storage.exists(key) is True
        print("PASS exists")
        if config.public_base_url:
            url = config.public_base_url.rstrip("/") + "/" + key
            read_ok, message = public_read(url)
            print(message)
            ok = ok and read_ok
        _ = uploaded
    # Report the class only, never details that may hold keys.
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL {type(exc).__name__}")
        ok = False
    finally:
        try:
            storage.delete(key)
            print(f"PASS cleanup (exists after delete: {storage.exists(key)})")
        except Exception as exc:  # noqa: BLE001
            print(f"FAIL cleanup {type(exc).__name__}; remove {key} manually")
            ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
