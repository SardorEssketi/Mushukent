"""H6/H1: concurrent publications against the emulated box, with a latency probe.

    .venv/Scripts/python tools/upload_stress.py <out_dir> --concurrent 10 --files 5 --size max
    --size phone  ~1.4 MB, 1920x1440 (what the app sends after client-side resizing)
    --size max    just under the server limits: <=10 MB and <=25 MP per file (a client
                  that skips resizing, an old build, or a deliberate abuser)

All uploads start together (one per user, distinct IPs, so the 10/min upload limit never
applies). A probe thread requests the recent feed and toggles a like every 0.5 s and records
latency, so the effect of uploads on fast requests is visible. Run tools/monitor.py alongside
for memory (run.sh-style) or use --monitor to start it here.
"""

from __future__ import annotations

import argparse
import io
import json
import os
import subprocess
import sys
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests
import urllib3
from PIL import Image

urllib3.disable_warnings()
HERE = Path(__file__).resolve().parent.parent
DATA = json.loads((HERE / "results" / "tokens.json").read_text(encoding="utf-8"))
BASE = os.getenv("LT_HOST", "https://127.0.0.1:18443") + "/api/v1"


def make_photo(size: str) -> bytes:
    if size == "phone":
        w, h, q = 1920, 1440, 90
    elif size == "max25":
        w, h, q = 5600, 4400, 92  # 24.6 MP: the largest accepted before FIX-6 (25 MP cap)
    else:
        w, h, q = 3264, 2448, 97  # 7.99 MP: the largest accepted after FIX-6 (8 MP cap)
    # Noise at 1/2 scale keeps the JPEG close to the 10 MB per-file limit.
    small = Image.frombytes("RGB", (w // 2, h // 2), os.urandom((w // 2) * (h // 2) * 3))
    image = small.resize((w, h), Image.Resampling.BILINEAR)
    while True:
        buf = io.BytesIO()
        image.save(buf, "JPEG", quality=q)
        if buf.tell() <= 10 * 1024 * 1024 - 4096 or q <= 40:
            return buf.getvalue()
        q -= 4


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--concurrent", type=int, default=10)
    ap.add_argument("--files", type=int, default=5)
    ap.add_argument("--size", choices=["phone", "max", "max25"], default="max")
    ap.add_argument("--monitor", action="store_true")
    args = ap.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    photo = make_photo(args.size)
    print(f"photo {len(photo) / 1048576:.2f} MB x {args.files} files x {args.concurrent} uploads", flush=True)
    mon = None
    if args.monitor:
        mon = subprocess.Popen([sys.executable, str(HERE / "tools" / "monitor.py"), str(args.out),
                                "--interval", "1"])
        time.sleep(3)

    stop = threading.Event()
    probe: list[tuple[float, str, int, float]] = []
    prober = DATA["users"][500]

    def run_probe():
        post = DATA["posts"][0]
        hdr = {"Host": "api.mushukistan.uz", "X-Forwarded-For": "10.250.0.1",
               "Authorization": f"Bearer {prober['token']}"}
        flip = True
        while not stop.is_set():
            for name, method, path, kw in (("feed", "GET", "/feed", {"params": {"limit": 20}}),
                                           ("like", "POST" if flip else "DELETE", f"/posts/{post}/likes", {})):
                t = time.perf_counter()
                try:
                    s = requests.request(method, BASE + path, headers=hdr, verify=False, timeout=60, **kw).status_code
                except requests.RequestException:
                    s = 0
                probe.append((time.time(), name, s, (time.perf_counter() - t) * 1000))
            flip = not flip
            time.sleep(0.5)

    threading.Thread(target=run_probe, daemon=True).start()
    time.sleep(5)  # probe baseline before the burst
    burst_start = time.time()

    def upload(i):
        user = DATA["users"][520 if os.getenv("LT_SAME_USER") else 520 + i]
        hdr = {"Host": "api.mushukistan.uz", "X-Forwarded-For": f"10.251.0.{i + 1}",
               "Authorization": f"Bearer {user['token']}", "Idempotency-Key": str(uuid.uuid4())}
        data = {"description": "upload stress", "kind": "observation", "status": "healthy",
                "location": json.dumps({"latitude": 41.31, "longitude": 69.28}),
                "new_cat": json.dumps({"name": "Stress cat"})}
        files = [("photos", (f"p{j}.jpg", photo, "image/jpeg")) for j in range(args.files)]
        t = time.perf_counter()
        try:
            s = requests.post(BASE + "/posts", headers=hdr, data=data, files=files, verify=False, timeout=300).status_code
        except requests.RequestException as exc:
            s = f"exc:{type(exc).__name__}"
        return s, round(time.perf_counter() - t, 1)

    with ThreadPoolExecutor(max_workers=args.concurrent) as pool:
        uploads = list(pool.map(upload, range(args.concurrent)))
    burst_end = time.time()
    time.sleep(5)
    stop.set()
    if mon:
        (args.out / "STOP").touch()
        mon.wait()

    def stats(rows):
        ms = sorted(r[3] for r in rows)
        return {"n": len(ms), "p50": round(ms[len(ms) // 2]) if ms else 0,
                "p95": round(ms[int(len(ms) * 0.95)]) if ms else 0, "max": round(ms[-1]) if ms else 0,
                "non_2xx": sum(1 for r in rows if not (200 <= r[2] < 300 or r[2] == 409))}

    before = [r for r in probe if r[0] < burst_start]
    during = [r for r in probe if burst_start <= r[0] <= burst_end]
    result = {
        "config": vars(args) | {"out": str(args.out), "photo_mb": round(len(photo) / 1048576, 2)},
        "uploads": uploads,
        "burst_seconds": round(burst_end - burst_start, 1),
        "probe_before": {k: stats([r for r in before if r[1] == k]) for k in ("feed", "like")},
        "probe_during": {k: stats([r for r in during if r[1] == k]) for k in ("feed", "like")},
    }
    oom = subprocess.run(["docker", "inspect", "-f", "{{.RestartCount}} {{.State.OOMKilled}}",
                          "mushukistan-load-backend-1"], capture_output=True, text=True).stdout.strip()
    result["backend_restarts_oom"] = oom
    (args.out / "upload_stress.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    print(json.dumps(result, indent=1))


if __name__ == "__main__":
    main()
