"""After a load run stops: how long until the box serves normally again, with no manual help?

Polls a guest feed page every 2 s (15 s timeout, the app's own) and counts active Postgres queries.
"Recovered" = the first moment from which 5 consecutive requests succeed in < 2 s and no query is
still running. Writes <out>/recovery.json.

    python tools/recovery_probe.py <out_dir> [--max-seconds 600]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import time
from pathlib import Path

import requests
import urllib3

urllib3.disable_warnings()
URL = "https://127.0.0.1:18443/api/v1/feed"
SQL = ("select count(*) from pg_stat_activity where datname=current_database() "
       "and state='active' and pid<>pg_backend_pid()")


def active_queries() -> int:
    out = subprocess.run(["docker", "exec", "mushukistan-load-db-1", "psql", "-U", "mushukistan",
                          "-d", "mushukistan_load", "-At", "-c", SQL],
                         capture_output=True, text=True, timeout=30).stdout.strip()
    return int(out) if out.isdigit() else -1


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("out", type=Path)
    ap.add_argument("--max-seconds", type=float, default=600)
    args = ap.parse_args()
    started = time.time()
    samples, streak, recovered_at = [], 0, None
    while time.time() - started < args.max_seconds:
        t = time.time()
        try:
            r = requests.get(URL, params={"limit": 20}, verify=False, timeout=15,
                             headers={"Host": "api.mushukistan.uz", "X-Forwarded-For": "10.254.0.1"})
            status, ms = r.status_code, (time.time() - t) * 1000
        except requests.RequestException:
            status, ms = 0, (time.time() - t) * 1000
        active = active_queries()
        ok = status == 200 and ms < 2000 and active <= 1
        streak = streak + 1 if ok else 0
        samples.append({"t": round(t - started, 1), "status": status, "ms": round(ms), "active": active})
        if streak == 1:
            candidate = round(t - started, 1)
        if streak >= 5:
            recovered_at = candidate
            break
        time.sleep(max(0.0, 2 - (time.time() - t)))
    result = {"recovered_after_s": recovered_at, "samples": samples}
    (args.out / "recovery.json").write_text(json.dumps(result, indent=1), encoding="utf-8")
    print(f"recovered_after_s={recovered_at} (first sample active queries: {samples[0]['active']}, "
          f"first status {samples[0]['status']} in {samples[0]['ms']} ms)")


if __name__ == "__main__":
    main()
