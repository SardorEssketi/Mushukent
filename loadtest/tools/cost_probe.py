"""Uncontended cost of each request type on the idle emulated box.

Sends each request sequentially (one at a time) and records the median latency. With nginx,
backend and Postgres sharing ONE core and nothing else running, the median latency is a close
upper bound on the CPU time one request costs. Combined with the per-user request mix this
gives a capacity estimate that does not depend on memory caps or queueing behaviour.

    .venv/Scripts/python tools/cost_probe.py <out_dir> [repeats]
"""

from __future__ import annotations

import json
import random
import statistics
import sys
import time
from pathlib import Path

import requests
import urllib3

urllib3.disable_warnings()
HERE = Path(__file__).resolve().parent.parent
DATA = json.loads((HERE / "results" / "tokens.json").read_text(encoding="utf-8"))
B = "https://127.0.0.1:18443/api/v1"
user = DATA["users"][550]
AUTH = {"Host": "api.mushukistan.uz", "Authorization": f"Bearer {user['token']}"}
ANON = {"Host": "api.mushukistan.uz"}
LON0, LAT0 = 69.2797, 41.3111


def bbox(span):
    lon = LON0 + random.uniform(-0.03, 0.03)
    lat = LAT0 + random.uniform(-0.02, 0.02)
    return f"{lon - span / 2:.5f},{lat - span * 0.45:.5f},{lon + span / 2:.5f},{lat + span * 0.45:.5f}"


def cursor(params, headers):
    r = requests.get(B + "/feed", params=params, headers=headers, verify=False, timeout=120)
    return r.json()["data"]["next_cursor"]


def main():
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    repeats = int(sys.argv[2]) if len(sys.argv) > 2 else 15
    near = {"filter": "nearby", "lat": LAT0, "lon": LON0, "radius_meters": 5000, "limit": 20}
    cases = {
        "feed recent page1 (auth)": lambda: ("GET", "/feed", {"params": {"limit": 20}}, AUTH),
        "feed recent pageN (auth)": lambda: ("GET", "/feed", {"params": {"limit": 20, "cursor": cursor({"limit": 20}, AUTH)}}, AUTH),
        "feed recent page1 (guest)": lambda: ("GET", "/feed", {"params": {"limit": 20}}, ANON),
        "feed popular page1": lambda: ("GET", "/feed", {"params": {"filter": "popular", "limit": 20}}, AUTH),
        "feed needs_help page1": lambda: ("GET", "/feed", {"params": {"filter": "needs_help", "limit": 20}}, AUTH),
        "feed nearby page1": lambda: ("GET", "/feed", {"params": near}, AUTH),
        "feed nearby page2": lambda: ("GET", "/feed", {"params": {**near, "cursor": cursor(near, AUTH)}}, AUTH),
        "cats bbox span 0.06 (z15)": lambda: ("GET", "/cats", {"params": {"filter": "recently_added", "limit": 100, "bbox": bbox(0.06)}}, AUTH),
        "cats bbox span 0.10 (z14)": lambda: ("GET", "/cats", {"params": {"filter": "recently_added", "limit": 100, "bbox": bbox(0.10)}}, AUTH),
        "cats bbox span 0.25 (z12)": lambda: ("GET", "/cats", {"params": {"filter": "recently_added", "limit": 100, "bbox": bbox(0.25)}}, AUTH),
        "lost-pets/map span 0.25": lambda: ("GET", "/lost-pets/map", {"params": {"limit": 100, "bbox": bbox(0.25)}}, AUTH),
        "places category (city)": lambda: ("GET", "/places", {"params": {"category": "veterinary", "map_only": "true", "limit": 200, "bbox": "69.05,41.18,69.47,41.43"}}, ANON),
        "cats/{id}/posts limit 1": lambda: ("GET", f"/cats/{random.choice(DATA['cats'])}/posts", {"params": {"limit": 1}}, ANON),
        "posts/{id}": lambda: ("GET", f"/posts/{random.choice(DATA['posts'])}", {}, AUTH),
        "posts/{id}/comments": lambda: ("GET", f"/posts/{random.choice(DATA['hot_posts'])}/comments", {"params": {"limit": 20}}, AUTH),
        "views/seen batch of 20": lambda: ("POST", "/views/seen", {"json": {"items": [{"kind": "post", "id": p} for p in random.sample(DATA["posts"], 20)]}}, AUTH),
        "notifications/unread-count": lambda: ("GET", "/notifications/unread-count", {}, AUTH),
        "lost-pets/follow-ups/due": lambda: ("GET", "/lost-pets/follow-ups/due", {}, AUTH),
        "users/me": lambda: ("GET", "/users/me", {}, AUTH),
        "health (framework floor)": lambda: ("GET", "/health", {}, ANON),
    }
    only = set(sys.argv[3].split(";")) if len(sys.argv) > 3 else None
    results = {}
    for name, make in cases.items():
        if only and name not in only:
            continue
        samples = []
        for i in range(repeats):
            method, path, kw, headers = make()
            headers = {**headers, "X-Forwarded-For": f"10.97.{i}.{len(results) + 1}"}
            if "Authorization" in headers:  # rotate accounts: one user may send 60/min
                other = DATA["users"][100 + (len(results) * repeats + i) % 500]
                headers["Authorization"] = f"Bearer {other['token']}"
            t = time.perf_counter()
            r = requests.request(method, B + path, headers=headers, verify=False, timeout=300, **kw)
            samples.append((time.perf_counter() - t) * 1000)
            if r.status_code >= 400:
                samples[-1] = float("nan")
        good = [s for s in samples if s == s]
        results[name] = {"median_ms": round(statistics.median(good), 1) if good else None,
                         "p90_ms": round(sorted(good)[int(len(good) * 0.9) - 1], 1) if good else None,
                         "errors": len(samples) - len(good)}
        print(f"{name:32s} median {results[name]['median_ms']} ms  p90 {results[name]['p90_ms']} ms  errors {results[name]['errors']}", flush=True)
    (out / "cost_probe.json").write_text(json.dumps(results, indent=1), encoding="utf-8")


if __name__ == "__main__":
    main()
