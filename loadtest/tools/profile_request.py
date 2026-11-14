"""Profile where one API request spends its time (Python vs database), outside the box.

Runs inside a backend-image container attached to the load-test network (see README), drives the
real app in-process with TestClient against the load database, and prints the top functions by
cumulative and own time plus the database share.

    python /tools/profile_request.py '/api/v1/cats?filter=recently_added&limit=100&bbox=...' [token]
"""

from __future__ import annotations

import cProfile
import io
import pstats
import sys
import time

from fastapi.testclient import TestClient

from app.main import app

path = sys.argv[1]
token = sys.argv[2] if len(sys.argv) > 2 else None
repeats = int(sys.argv[3]) if len(sys.argv) > 3 else 20
headers = {"Authorization": f"Bearer {token}"} if token else {}

with TestClient(app) as client:
    for _ in range(3):  # warm up caches and connections
        assert client.get(path, headers=headers).status_code == 200
    started = time.perf_counter()
    profiler = cProfile.Profile()
    profiler.enable()
    for _ in range(repeats):
        client.get(path, headers=headers)
    profiler.disable()
    wall = (time.perf_counter() - started) / repeats * 1000

stats = pstats.Stats(profiler)
total = stats.total_tt / repeats * 1000
db = sum(
    entry[3]
    for func, entry in stats.stats.items()
    if "psycopg" in func[0] and func[2] in {"execute", "fetchall", "fetchmany", "_fetch_gen"}
) / repeats * 1000
out = io.StringIO()
pstats.Stats(profiler, stream=out).sort_stats("tottime").print_stats(18)
print(f"wall {wall:.1f} ms/request, profiled {total:.1f} ms, psycopg execute+fetch ~{db:.1f} ms")
print(out.getvalue()[-6000:])
