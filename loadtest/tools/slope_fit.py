"""Fit box CPU = floor + slope x users from remeasure.sh slope steps.

Reads results/cpu-slope/slope.csv (one row per variant, users, container) and prints, per variant:
the idle floor and the marginal cost (ms of a production core per extra active user-second) for the
whole box and per container, R2, and the capacity (0.7 x cores - floor) / slope. Steps where the box
is near its CPU budget (saturated, non-linear) are reported but left out of the fit.

Workstation CPU is converted to production cores with the measured calibration (the box budget
of 0.28 workstation core = one production core; LOADBOX_FACTOR overrides it).

    python tools/slope_fit.py results/cpu-slope/slope.csv [--cores 1] [--variant after]
"""

from __future__ import annotations

import argparse
import csv
import os
from collections import defaultdict
from pathlib import Path

FACTOR = float(os.getenv("LOADBOX_FACTOR", "0.28"))  # workstation cores per production core
SATURATED = 0.85  # fraction of the box budget above which a step is not used in the fit
FEED = ("GET /feed",)
MAP = ("GET /cats (map bbox)", "GET /lost-pets/map", "GET /places")


def fit(xs: list[float], ys: list[float]) -> tuple[float, float, float]:
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxx = sum((x - mx) ** 2 for x in xs)
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    slope = sxy / sxx if sxx else 0.0
    floor = my - slope * mx
    ss_tot = sum((y - my) ** 2 for y in ys)
    ss_res = sum((y - floor - slope * x) ** 2 for x, y in zip(xs, ys))
    return floor, slope, (1 - ss_res / ss_tot) if ss_tot else 1.0


def p95(values: list[float]) -> float:
    if not values:
        return float("nan")
    values = sorted(values)
    return values[min(len(values) - 1, int(round(0.95 * (len(values) - 1))))]


def latency(run_dir: str, start: float, end: float) -> dict[str, float]:
    path = Path(run_dir) / "requests.csv"
    if not run_dir or not path.exists():
        return {}
    feed, maps, total, errors = [], [], 0, 0
    with path.open() as f:
        for row in csv.DictReader(f):
            if not start <= float(row["t"]) <= end:
                continue
            total += 1
            status = row["status"]
            if not status.isdigit() or int(status) >= 500:
                errors += 1
            if row["name"].startswith(FEED):
                feed.append(float(row["ms"]))
            elif row["name"].startswith(MAP):
                maps.append(float(row["ms"]))
    return {
        "feed_p95": p95(feed),
        "map_p95": p95(maps),
        "err_pct": 100 * errors / total if total else float("nan"),
        "rps": total / (end - start),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("csv", type=Path)
    parser.add_argument("--cores", type=float, default=1.0, help="production cores of the box")
    parser.add_argument("--variant", action="append")
    parser.add_argument("--warmup", type=float, default=float(os.getenv("SLOPE_WARMUP_S", "90")))
    args = parser.parse_args()

    # (variant, users) -> latest step: {"seconds", "run_dir", "cores": {container: prod cores}}
    steps: dict[tuple[str, int], dict] = {}
    order: dict[str, int] = {}
    with args.csv.open() as f:
        for row in csv.DictReader(f):
            key, step_id = (row["variant"], int(row["users"])), int(row["step"])
            order.setdefault(row["variant"], step_id)
            step = steps.get(key)
            if step is None or step_id > step["id"]:
                step = steps[key] = {"id": step_id, "cores": {}}
            elif step_id < step["id"]:
                continue  # an older measurement of a re-measured step
            seconds = float(row["seconds"])
            step["seconds"], step["run_dir"] = seconds, row["run_dir"]
            step["cores"][row["container"]] = int(row["usage_us"]) / 1e6 / seconds / FACTOR

    variants = sorted(order, key=order.get)
    for variant in variants:
        if args.variant and variant not in args.variant:
            continue
        points = sorted((u, s) for (v, u), s in steps.items() if v == variant)
        print(f"\n## {variant}\n")
        print("| users | box prod cores | db | backend | worker | nginx | feed p95 ms | map p95 ms | 5xx/err % | req/s |")
        print("|---|---|---|---|---|---|---|---|---|---|")
        used = []
        for users, s in points:
            c = s["cores"]
            lat = latency(s.get("run_dir", ""), args.warmup, args.warmup + s["seconds"])
            sat = c["total"] >= SATURATED * args.cores
            if not sat:
                used.append((users, c))
            print(
                f"| {users} | {c['total']:.3f}{' (saturated)' if sat else ''} | {c.get('db', 0):.3f} | "
                f"{c.get('backend', 0):.3f} | {c.get('notification-worker', 0):.3f} | {c.get('nginx', 0):.3f} | "
                f"{lat.get('feed_p95', float('nan')):.0f} | {lat.get('map_p95', float('nan')):.0f} | "
                f"{lat.get('err_pct', float('nan')):.2f} | {lat.get('rps', float('nan')):.2f} |"
            )
        if len(used) < 2:
            print("\nnot enough unsaturated steps to fit")
            continue
        xs = [u for u, _ in used]
        print(f"\nFit over users {xs} (production-core ms; floor in ms of a core per second):\n")
        print("| part | floor ms/s | slope ms per user-s | R2 |")
        print("|---|---|---|---|")
        for part in ("total", "db", "backend", "notification-worker", "nginx"):
            floor, slope, r2 = fit(xs, [c.get(part, 0.0) for _, c in used])
            print(f"| {part} | {floor * 1000:.1f} | {slope * 1000:.2f} | {r2:.4f} |")
        floor, slope, r2 = fit(xs, [c["total"] for _, c in used])
        cap = (0.7 * args.cores - floor) / slope if slope > 0 else float("inf")
        print(
            f"\ncapacity at 70% of {args.cores:g} core(s): (0.7 x {args.cores:g} - {floor:.3f}) / "
            f"{slope * 1000:.2f} ms = **{cap:.1f} concurrent active users** (CPU only)"
        )


if __name__ == "__main__":
    main()
