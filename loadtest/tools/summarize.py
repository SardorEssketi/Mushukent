"""Summarise one load-test run directory into Markdown (stdout).

Inputs (written by run.sh / locustfile.py / monitor.py): requests.csv, status_counts.json,
monitor.csv, pool.jsonl, external_calls.json, env.txt.
The "steady" window excludes the ramp: target 600-1500 s, spike 0-420 s, soak 300 s-end,
stress is reported per 3-minute step. Standard library only.
"""

from __future__ import annotations

import csv
import json
import statistics
import sys
from collections import defaultdict
from pathlib import Path

WINDOWS = {"target": (600, 1500), "spike": (0, 420), "soak": (300, 10**9),
           "baseline": (0, 10**9), "short": (60, 10**9)}


def pct(values, q):
    if not values:
        return 0.0
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q / 100 * (len(values) - 1))))]


def load_requests(path: Path):
    rows = []
    # Parse from both ends: endpoint names may contain commas.
    with path.open(encoding="utf-8") as handle:
        next(handle, None)
        for line in handle:
            t, _, rest = line.rstrip("\r\n").partition(",")
            parts = rest.rsplit(",", 3)
            if len(parts) != 4:
                continue
            try:
                rows.append((float(t), parts[0], parts[1], float(parts[2]), parts[3]))
            except ValueError:
                continue
    return rows


def endpoint_table(rows, start, end):
    by = defaultdict(list)
    codes = defaultdict(lambda: defaultdict(int))
    for t, name, status, ms, _ in rows:
        if start <= t < end:
            by[name].append(ms)
            codes[name][status] += 1
    duration = max(1.0, min(end, max((r[0] for r in rows), default=1)) - start)
    out = ["| Endpoint | req | req/s | p50 ms | p95 ms | p99 ms | max ms | 429 | 5xx | timeouts/exc |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    tot = defaultdict(int)
    allms = []
    for name in sorted(by, key=lambda n: -len(by[n])):
        ms = by[name]
        c = codes[name]
        n429 = c.get("429", 0)
        n5xx = sum(v for k, v in c.items() if k.isdigit() and int(k) >= 500)
        nexc = c.get("exc", 0) + c.get("0", 0)
        tot["n"] += len(ms); tot["429"] += n429; tot["5xx"] += n5xx; tot["exc"] += nexc
        allms += ms
        out.append(f"| {name} | {len(ms)} | {len(ms) / duration:.2f} | {pct(ms, 50):.0f} | "
                   f"{pct(ms, 95):.0f} | {pct(ms, 99):.0f} | {max(ms):.0f} | {n429} | {n5xx} | {nexc} |")
    n = max(1, tot["n"])
    out.append(f"| **all** | {tot['n']} | {tot['n'] / duration:.1f} | {pct(allms, 50):.0f} | "
               f"{pct(allms, 95):.0f} | {pct(allms, 99):.0f} | {max(allms or [0]):.0f} | "
               f"{tot['429']} ({100 * tot['429'] / n:.2f}%) | {tot['5xx']} ({100 * tot['5xx'] / n:.2f}%) | "
               f"{tot['exc']} ({100 * tot['exc'] / n:.2f}%) |")
    return "\n".join(out)


def persona_429(rows, start, end):
    total = defaultdict(int)
    limited = defaultdict(int)
    for t, name, status, ms, persona in rows:
        if start <= t < end:
            total[persona] += 1
            limited[persona] += status == "429"
    return ", ".join(f"{p or '?'}: {limited[p]}/{total[p]} ({100 * limited[p] / max(1, total[p]):.1f}%)"
                     for p in sorted(total))


def steps(rows, size=180):
    buckets = defaultdict(list)
    for t, name, status, ms, _ in rows:
        buckets[int(t // size)].append((status, ms))
    out = ["| step (s) | req/s | p50 | p95 | p99 | 429 % | 5xx % | exc % |", "|---|---|---|---|---|---|---|---|"]
    for b in sorted(buckets):
        items = buckets[b]
        ms = [m for _, m in items]
        n = len(items)
        r = lambda pred: 100 * sum(1 for s, _ in items if pred(s)) / n  # noqa: E731
        out.append(f"| {b * size}-{(b + 1) * size} | {n / size:.1f} | {pct(ms, 50):.0f} | {pct(ms, 95):.0f} | "
                   f"{pct(ms, 99):.0f} | {r(lambda s: s == '429'):.2f} | "
                   f"{r(lambda s: s.isdigit() and int(s) >= 500):.2f} | {r(lambda s: s in ('exc', '0')):.2f} |")
    return "\n".join(out)


def monitor(path: Path, start_epoch=None):
    if not path.exists():
        return "no monitor data"
    rows = list(csv.DictReader(path.open(encoding="utf-8")))
    if not rows:
        return "no monitor data"

    def col(name):
        vals = []
        for r in rows:
            try:
                vals.append(float(r[name]))
            except (ValueError, KeyError):
                pass
        return vals

    lines = []
    for key, label in (("box_cpu", "box CPU % (1 core = 100)"), ("backend_cpu", "backend CPU %"),
                       ("db_cpu", "db CPU %"), ("box_mem", "box memory MiB"),
                       ("backend_mem", "backend MiB"), ("db_mem", "db MiB"),
                       ("pg_conns", "pg connections"), ("pg_active", "pg active"),
                       ("lock_waits", "ungranted locks"), ("push_backlog", "push backlog")):
        v = col(key)
        if v:
            lines.append(f"- {label}: mean {statistics.mean(v):.0f}, p95 {pct(v, 95):.0f}, max {max(v):.0f}"
                         f" (first {v[0]:.0f}, last {v[-1]:.0f})")
    last = rows[-1]
    lines.append(f"- restarts/OOM: backend {last.get('backend_restarts')}/{last.get('backend_oom')}, "
                 f"db {last.get('db_restarts')}/{last.get('db_oom')}; deadlocks {last.get('pg_deadlocks')}")
    return "\n".join(lines)


def pool(path: Path):
    if not path.exists() or path.stat().st_size == 0:
        return "no pool data"
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            rows.append(json.loads(line))
        except ValueError:
            continue  # torn line (two writers on a shared bind mount)
    if not rows:
        return "no pool data"
    co = [r["checked_out"] for r in rows]
    of = [r["overflow"] for r in rows]
    wp95 = [r["wait_p95_ms"] for r in rows]
    wmax = [r["wait_max_ms"] for r in rows]
    thr = [r["threads"] for r in rows]
    return (f"- checked out: mean {statistics.mean(co):.1f}, max {max(co)} (pool 5 + overflow 10 = 15)\n"
            f"- overflow max {max(of)}; checkout wait p95 (per 2 s) median {statistics.median(wp95):.1f} ms, "
            f"max {max(wp95):.0f} ms; worst single wait {max(wmax):.0f} ms\n"
            f"- pool timeouts total {rows[-1]['pool_timeouts_total']}; backend threads max {max(thr)}")


def main():
    out = Path(sys.argv[1])
    env = dict(line.split("=", 1) for line in (out / "env.txt").read_text().splitlines() if "=" in line) \
        if (out / "env.txt").exists() else {}
    name = out.name.split("-", 2)[2].split("-")[0] if out.name.count("-") >= 2 else "run"
    rows = load_requests(out / "requests.csv")
    start, end = WINDOWS.get(name, (0, 10**9))
    print(f"# Run {out.name}\n\nSettings: {', '.join(f'{k}={v}' for k, v in sorted(env.items())) or 'defaults'}\n")
    print(f"## Steady window {start}-{min(end, int(max((r[0] for r in rows), default=0)))} s\n")
    print(endpoint_table(rows, start, end))
    print(f"\n429 share by persona (steady window): {persona_429(rows, start, end)}\n")
    print("## Per 3-minute step (whole run)\n")
    print(steps(rows))
    print("\n## Emulated box (docker stats, 5 s samples)\n")
    print(monitor(out / "monitor.csv"))
    print("\n## Connection pool (backend)\n")
    print(pool(out / "pool.jsonl"))
    ext = out / "external_calls.json"
    if ext.exists():
        print(f"\n## External calls (mock sink)\n\n`{ext.read_text().strip()}`")


if __name__ == "__main__":
    main()
