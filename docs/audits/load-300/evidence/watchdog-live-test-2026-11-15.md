# Load-harness watchdog: live test (2026-11-15)

Purpose: prove that the harness stops a load run by itself, so Claude Code's background memory
reaper can be turned off for long runs. Harness at `c14dc8b` (watchdog wired into `run.sh`, whole
process tree killed). The floor was changed only through the environment for these two runs.
`LT_ABORT_FREE_MB` stays 1200 MB by default and no code changed.

Result: **both PASS** (**Verified**).

| Test | Trigger | Locust running before | Stopped after | Marker | Process list after | Lock |
|---|---|---|---|---|---|---|
| A, memory floor | floor = free − 600 MB (3132 MB); after 40 s a helper allocated 1.1 GB, free fell to 2324 MB | yes: run.sh, Locust (venv launcher + interpreter), monitor | ~4 s after the drop (run.sh exit 4) | `MEMORY_STOP`: "host free memory 2324 MB < 3132 MB … run stopped" | empty | released |
| B, driver killed | `kill -9` of the driver shell 40 s into the run | yes: driver, run.sh, Locust (launcher + interpreter), monitor | 1 s after the kill | `ORPHAN_STOP`: "driver (pid …) is gone … run stopped" | empty after 15 s | released |

Process lists (pid, parent, name; command lines shortened), from the test output:

```
=== A: memory floor, real drop mid-run
13:40:09 free=3732 MB, floor=3132 MB
--- before:
(end)
--- 13:40:50 running (before the drop):
38252 29140 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-memory2
19872 38252 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-memory2
26380 38252 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-memory2
8980 19872 python.exe "D:\Data science\mushukent\loadtest\.venv\Scripts\python.exe" tools/monitor.py results/20261115-134010-short-watchdog-test-memory2 --interva
33696 38252 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-memory2
8036 26380 python.exe "D:\Data science\mushukent\loadtest\.venv\Scripts\python.exe" -m locust -f locustfile.py --headless --csv results/20261115-134010-short-watc
30732 8980 python.exe "C:\Python312\python.exe" tools/monitor.py results/20261115-134010-short-watchdog-test-memory2 --interval 5
8964 8036 python.exe "C:\Python312\python.exe" -m locust -f locustfile.py --headless --csv results/20261115-134010-short-watchdog-test-memory2/locust --csv-full-
(end)
13:40:56 run.sh exit=4
--- after:
(end)
results/20261115-134010-short-watchdog-test-memory2: MEMORY_STOP STOP env.txt host_free_min_mb.txt locust.log locust_exceptions.csv locust_failures.csv locust_stats.csv locust_stats_history.csv monitor.csv requests.csv 
host free memory 2324 MB < 3132 MB at 2026-11-15 13:40:52; run stopped
lock: pool.jsonl trace.jsonl 
free now 3575 MB

=== B: driver killed mid-run
--- before:
(end)
--- 13:41:51 running (driver pid 36127):
29264 22596 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" -c "bash run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-orphan > results/_watchdog-o
22472 13920 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-orphan
16208 22472 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-orphan
40324 22472 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-orphan
35728 16208 python.exe "D:\Data science\mushukent\loadtest\.venv\Scripts\python.exe" tools/monitor.py results/20261115-134112-short-watchdog-test-orphan --interval
38460 22472 bash.exe "C:\Program Files\Git\usr\bin\bash.exe" run.sh run short LT_USERS=5 LT_HOLD_S=150 LT_TAG=watchdog-test-orphan
37008 40324 python.exe "D:\Data science\mushukent\loadtest\.venv\Scripts\python.exe" -m locust -f locustfile.py --headless --csv results/20261115-134112-short-watc
25944 35728 python.exe "C:\Python312\python.exe" tools/monitor.py results/20261115-134112-short-watchdog-test-orphan --interval 5
10316 37008 python.exe "C:\Python312\python.exe" -m locust -f locustfile.py --headless --csv results/20261115-134112-short-watchdog-test-orphan/locust --csv-full-h
(end)
13:41:52 driver killed
--- 13:42:07 15 s after the driver was killed:
(end)
results/20261115-134112-short-watchdog-test-orphan: ORPHAN_STOP STOP env.txt host_free_min_mb.txt locust.log locust_exceptions.csv locust_failures.csv locust_stats.csv locust_stats_history.csv monitor.csv requests.csv 
driver (pid 36127) is gone at 2026-11-15 13:41:53; run stopped
lock: pool.jsonl trace.jsonl 
```

An earlier test the same day with the floor above free memory (free 3715 MB, floor 4215 MB)
stopped at the first check, before Locust produced requests: exit 4, `MEMORY_STOP`, no processes
left. The guard self-test (`tools/test_guard.sh`, 12 checks) passes.
