"""Overload run: server-side vs Locust-side latency, for when Locust itself is CPU-bound.

Needs a run made with LOADTEST_TRACE=1 (trace.jsonl) and LT_SIDE_PROBE=1 (side_probe.csv).

    python tools/overload_split.py <run_dir> [<run_dir> ...]
"""

from __future__ import annotations

import csv
import json
import sys


def q(v, p):
    v = sorted(v)
    return v[int(p * (len(v) - 1))] if v else float("nan")


def main() -> None:
    for d in sys.argv[1:]:
        print(f"## {d.rstrip('/').split('/')[-1]}")
        req, loop = [], []
        for line in open(f"{d}/trace.jsonl", encoding="utf-8"):
            r = json.loads(line)
            (req if r.get("kind") == "req" else loop).append(r)
        for st in sorted({r["s"] for r in req}):
            v = [r["ms"] for r in req if r["s"] == st]
            if len(v) >= 5:
                print(f"server {st}: n={len(v)} p50={q(v, .5):.1f} p95={q(v, .95):.1f} ms")
        ok = [r for r in req if r["s"] == 200]
        for k in ("pool_ms", "tp_wait_ms", "db_ms"):
            print(f"  200s {k}: p50={q([r.get(k, 0) for r in ok], .5):.0f} "
                  f"p95={q([r.get(k, 0) for r in ok], .95):.0f} ms")
        lag = [r["lag_p95_ms"] for r in loop if "lag_p95_ms" in r]
        print(f"event-loop lag (per-second p95): median {q(lag, .5):.0f} ms, max {max(lag):.0f} ms")
        sp = list(csv.DictReader(open(f"{d}/side_probe.csv", encoding="utf-8")))
        for path in ("health", "feed"):
            v = [float(r["ms"]) for r in sp if r["path"] == path]
            codes = sorted({r["status"] for r in sp if r["path"] == path})
            print(f"side probe {path}: n={len(v)} p50={q(v, .5):.0f} p95={q(v, .95):.0f} ms "
                  f"codes {codes}")
        lc = list(csv.DictReader(open(f"{d}/requests.csv", encoding="utf-8")))
        for st in ("200", "503", "0"):
            v = [float(r["ms"]) for r in lc if r["status"] == st]
            if v:
                print(f"locust {st}: n={len(v)} p50={q(v, .5):.0f} p95={q(v, .95):.0f} ms")
        print()


if __name__ == "__main__":
    main()
