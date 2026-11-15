"""Where request time goes per load step (task 5a): latency knee by latency, not CPU.

Reads a traced slope series (remeasure.sh slope with LOADTEST_TRACE=1, SLOPE_LABEL=<label>):
results/cpu-slope/slope.csv + psi.csv for the window of each step, the run's requests.csv (client
latency, Locust side) and trace.jsonl (server side, from the shim: one line per request plus a
1 s event-loop sample).

Per step: client Feed/map p95, box CPU, CPU wait (cgroup cpu.pressure "some": share of the window
in which at least one task of the container was runnable but not running, quota throttling
included), event-loop lag and loop-thread run-queue wait, pool wait, 503 sheds. Per slow endpoint:
the slow tail (requests at or above the endpoint's server p90) split into

  tp_wait  waiting for a thread-pool thread (anyio limiter + hand-off)
  pool     waiting for a database connection (SQLAlchemy QueuePool)
  db       cursor execute wall time (network + Postgres, including Postgres waiting for CPU)
  cpu_q    the request's worker thread runnable but not running (run_delay: CPU run-queue)
  cpu      the rest of the sync handler time (Python running, GIL waits not separated)
  loop     the rest of server time (async middleware, event-loop queueing, response send)

The in-flight cap has no queue: requests above the cap are answered 503 at once (counted).

    python tools/knee_breakdown.py results/cpu-slope/slope.csv --label knee-abc
"""

from __future__ import annotations

import argparse
import csv
import json
import re
from collections import defaultdict
from pathlib import Path

from slope_fit import FACTOR, latency, p95

COMPONENTS = ("tp_wait", "pool", "db", "cpu_q", "cpu", "loop")


def pct(values: list[float], q: float) -> float:
    if not values:
        return float("nan")
    values = sorted(values)
    return values[min(len(values) - 1, int(round(q * (len(values) - 1))))]


def split(r: dict) -> dict[str, float]:
    tp_run = r["tp_run_ms"]
    inside = r["db_ms"] + r["pool_ms"] + r["tp_rq_ms"]
    return {
        "tp_wait": r["tp_wait_ms"],
        "pool": r["pool_ms"],
        "db": r["db_ms"],
        "cpu_q": r["tp_rq_ms"],
        "cpu": max(0.0, tp_run - inside),
        "loop": max(0.0, r["ms"] - r["tp_wait_ms"] - tp_run),
    }


def load_steps(slope_csv: Path, label: str) -> dict[int, dict]:
    steps: dict[int, dict] = {}
    with slope_csv.open() as f:
        for row in csv.DictReader(f):
            if row["variant"] != label:
                continue
            users, step_id = int(row["users"]), int(row["step"])
            s = steps.get(users)
            if s is None or step_id > s["step"]:
                s = steps[users] = {"step": step_id, "cores": {}, "psi": {}}
            elif step_id < s["step"]:
                continue
            s["seconds"], s["run_dir"] = float(row["seconds"]), row["run_dir"]
            name = re.sub(r"-\d+$", "", row["container"])
            s["cores"][name] = int(row["usage_us"]) / 1e6 / s["seconds"] / FACTOR
    psi = slope_csv.with_name("psi.csv")
    if psi.exists():
        with psi.open() as f:
            for row in csv.DictReader(f):
                s = steps.get(int(row["users"])) if row["variant"] == label else None
                if s is None or int(row["step"]) != s["step"]:
                    continue
                name = re.sub(r"-\d+$", "", row["container"])
                s["psi"][name] = int(row["cpu_wait_us"]) / 1e6 / float(row["seconds"])
    return steps


def read_trace(run_dir: str, start: float, end: float) -> tuple[list[dict], list[dict]]:
    reqs, loops = [], []
    path = Path(run_dir) / "trace.jsonl"
    if not path.exists():
        return reqs, loops
    with path.open() as f:
        for line in f:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if not start <= r["t"] <= end:
                continue
            (reqs if r["kind"] == "req" else loops).append(r)
    return reqs, loops


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path)
    parser.add_argument("--label", required=True)
    parser.add_argument("--warmup", type=float, default=90.0)
    parser.add_argument("--top", type=int, default=6)
    parser.add_argument("--min-n", type=int, default=30)
    args = parser.parse_args()

    steps = load_steps(args.csv, args.label)
    print(f"## {args.label}: per step (production-core units; CPU wait = share of the window)\n")
    print(
        "| users | box cores | Feed p95 | map p95 | err % | req/s | 503 sheds | box CPU wait | "
        "backend CPU wait | db CPU wait | loop lag p95 | loop thread run-queue | pool wait p95 | "
        "server p95 (all) |"
    )
    print("|" + "---|" * 14)
    detail = {}
    for users in sorted(steps):
        s = steps[users]
        lat = latency(s["run_dir"], args.warmup, args.warmup + s["seconds"])
        reqs, loops = read_trace(s["run_dir"], s["step"], s["step"] + s["seconds"])
        detail[users] = reqs
        lags = [x["lag_p95_ms"] for x in loops if x.get("lag_p95_ms") is not None]
        rq = [x["loop_rq_ns"] for x in loops if x.get("loop_rq_ns")]
        span = (loops[-1]["t"] - loops[0]["t"]) if len(loops) > 1 else 0
        loop_rq = (rq[-1] - rq[0]) / 1e9 / span if span and len(rq) > 1 else float("nan")
        sheds = sum(1 for r in reqs if r["s"] == 503)
        psi = s["psi"]
        print(
            f"| {users} | {s['cores'].get('total', 0):.3f} | {lat.get('feed_p95', float('nan')):.0f} | "
            f"{lat.get('map_p95', float('nan')):.0f} | {lat.get('err_pct', float('nan')):.2f} | "
            f"{lat.get('rps', float('nan')):.1f} | {sheds} | {psi.get('total', float('nan')):.0%} | "
            f"{psi.get('backend', float('nan')):.0%} | {psi.get('db', float('nan')):.0%} | "
            f"{pct(lags, 0.95):.0f} ms | {loop_rq:.0%} | {pct([r['pool_ms'] for r in reqs], 0.95):.1f} ms | "
            f"{pct([r['ms'] for r in reqs], 0.95):.0f} ms |"
        )

    print("\nServer time share over ALL requests (sum of each component / sum of server time):\n")
    print("| users | " + " | ".join(COMPONENTS) + " |")
    print("|---|" + "---|" * len(COMPONENTS))
    for users, reqs in detail.items():
        tot = sum(r["ms"] for r in reqs) or 1.0
        sums = defaultdict(float)
        for r in reqs:
            for k, v in split(r).items():
                sums[k] += v
        print(f"| {users} | " + " | ".join(f"{sums[k] / tot:.0%}" for k in COMPONENTS) + " |")

    print(
        f"\nSlowest endpoints (server p95, n >= {args.min_n}); breakdown = mean ms of the slow tail "
        "(requests >= that endpoint's server p90):\n"
    )
    print("| users | endpoint | n | p50 | p95 | tail mean | " + " | ".join(COMPONENTS) + " |")
    print("|---|---|---|---|---|---|" + "---|" * len(COMPONENTS))
    for users, reqs in detail.items():
        by = defaultdict(list)
        for r in reqs:
            if r["s"] != 503:
                by[f"{r['m']} {r['p']}"].append(r)
        ranked = sorted(
            (k for k, v in by.items() if len(v) >= args.min_n),
            key=lambda k: p95([r["ms"] for r in by[k]]),
            reverse=True,
        )[: args.top]
        for k in ranked:
            rs = by[k]
            ms = [r["ms"] for r in rs]
            cut = pct(ms, 0.90)
            tail = [r for r in rs if r["ms"] >= cut]
            parts = defaultdict(float)
            for r in tail:
                for c, v in split(r).items():
                    parts[c] += v / len(tail)
            print(
                f"| {users} | {k.replace('/api/v1', '')} | {len(rs)} | {pct(ms, 0.5):.0f} | {p95(ms):.0f} | "
                f"{sum(r['ms'] for r in tail) / len(tail):.0f} | "
                + " | ".join(f"{parts[c]:.0f}" for c in COMPONENTS)
                + " |"
            )


if __name__ == "__main__":
    main()
