"""Independent latency probe, separate from Locust: one request per second each to the health check
(never shed, no DB) and a guest feed page. When Locust itself is CPU-bound its timings include its
own queueing; this probe's do not. Writes <out>/side_probe.csv until <out>/STOP exists.

    python tools/side_probe.py <out_dir>
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

import requests
import urllib3

urllib3.disable_warnings()
BASE = "https://127.0.0.1:18443/api/v1"
HEADERS = {"Host": "api.mushukistan.uz", "X-Forwarded-For": "10.250.0.1"}


def one(session: requests.Session, path: str) -> tuple[int, float]:
    t = time.perf_counter()
    try:
        code = session.get(f"{BASE}/{path}", headers=HEADERS, verify=False, timeout=60).status_code
    except requests.RequestException:
        code = 0
    return code, (time.perf_counter() - t) * 1000


def main() -> None:
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    session = requests.Session()  # keep-alive, like the app
    with (out / "side_probe.csv").open("w", encoding="utf-8") as f:
        f.write("t,path,status,ms\n")
        while not (out / "STOP").exists():
            start = time.time()
            for path in ("health", "feed?filter=recent&limit=20"):
                code, ms = one(session, path)
                f.write(f"{start:.1f},{path.split('?')[0]},{code},{ms:.0f}\n")
            f.flush()
            time.sleep(max(0.0, 1.0 - (time.time() - start)))


if __name__ == "__main__":
    main()
