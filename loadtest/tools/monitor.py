"""Sample the emulated box every few seconds while a load test runs.

Writes <out>/monitor.csv with, per sample: container CPU % and memory (MiB) for db, backend,
worker and nginx, their sum, Postgres connection states, ungranted locks (lock waits),
notification push-job backlog, and container restart / OOM counters.

Stops when <out>/STOP exists or after --max-seconds. Uses only the docker CLI.
"""

from __future__ import annotations

import argparse
import csv
import subprocess
import time
from pathlib import Path

PROJECT = "mushukistan-load"
SERVICES = ["db", "backend", "notification-worker", "nginx"]
SQL = (
    "select "
    "(select count(*) from pg_stat_activity where datname=current_database()),"
    "(select count(*) from pg_stat_activity where datname=current_database() and state='active'),"
    "(select count(*) from pg_stat_activity where datname=current_database() "
    " and state='idle in transaction'),"
    "(select count(*) from pg_locks where not granted),"
    "(select count(*) from notification_push_jobs where status in ('pending','sending')),"
    "(select coalesce(sum(xact_commit),0) from pg_stat_database where datname=current_database()),"
    "(select coalesce(sum(deadlocks),0) from pg_stat_database where datname=current_database())"
)


def container(service: str) -> str:
    return f"{PROJECT}-{service}-1"


def docker(*args: str) -> str:
    return subprocess.run(["docker", *args], capture_output=True, text=True, timeout=30).stdout


def mib(value: str) -> float:
    value = value.strip()
    for unit, factor in (("GiB", 1024), ("MiB", 1), ("KiB", 1 / 1024), ("B", 1 / 1048576)):
        if value.endswith(unit):
            return float(value[: -len(unit)]) * factor
    return 0.0


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--interval", type=float, default=5)
    parser.add_argument("--max-seconds", type=float, default=6 * 3600)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    stop = args.out / "STOP"
    names = [container(s) for s in SERVICES]
    header = ["t"]
    for s in SERVICES:
        header += [f"{s}_cpu", f"{s}_mem"]
    header += ["box_cpu", "box_mem", "pg_conns", "pg_active", "pg_idle_in_tx", "lock_waits",
               "push_backlog", "pg_commits", "pg_deadlocks", "backend_restarts", "backend_oom",
               "db_restarts", "db_oom"]
    started = time.time()
    with (args.out / "monitor.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(header)
        while not stop.exists() and time.time() - started < args.max_seconds:
            tick = time.time()
            stats = {}
            for line in docker("stats", "--no-stream", "--format",
                               "{{.Name}}|{{.CPUPerc}}|{{.MemUsage}}", *names).splitlines():
                name, cpu, mem = line.split("|")
                stats[name] = (float(cpu.rstrip("%") or 0), mib(mem.split("/")[0]))
            row = [round(tick, 1)]
            cpu_sum = mem_sum = 0.0
            for name in names:
                cpu, mem = stats.get(name, (0.0, 0.0))
                cpu_sum += cpu
                mem_sum += mem
                row += [cpu, round(mem, 1)]
            row += [round(cpu_sum, 1), round(mem_sum, 1)]
            pg = docker("exec", container("db"), "psql", "-U", "mushukistan", "-d",
                        "mushukistan_load", "-At", "-F", ",", "-c", SQL).strip().split(",")
            row += pg if len(pg) == 7 else [""] * 7
            for name in (container("backend"), container("db")):
                state = docker("inspect", "-f", "{{.RestartCount}},{{.State.OOMKilled}}",
                               name).strip().split(",")
                row += state if len(state) == 2 else ["", ""]
            writer.writerow(row)
            handle.flush()
            time.sleep(max(0.0, args.interval - (time.time() - tick)))


if __name__ == "__main__":
    main()
