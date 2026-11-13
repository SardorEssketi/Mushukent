"""Fire N concurrent `nearby` page-2 feed requests; print latency and db block-I/O delta."""
import subprocess, sys, time, requests, urllib3
from concurrent.futures import ThreadPoolExecutor
urllib3.disable_warnings()
B = "https://127.0.0.1:18443/api/v1/feed"
H = {"Host": "api.mushukistan.uz"}
P = {"filter": "nearby", "lat": 41.3111, "lon": 69.2797, "radius_meters": 5000, "limit": 20}
n = int(sys.argv[1]) if len(sys.argv) > 1 else 10
def blkio():
    out = subprocess.run(["docker", "stats", "--no-stream", "--format", "{{.BlockIO}}", "mushukistan-load-db-1"],
                         capture_output=True, text=True).stdout.strip()
    return out
t = time.perf_counter(); r = requests.get(B, params=P, headers={**H, "X-Forwarded-For": "10.99.0.1"}, verify=False, timeout=300)
print("page1", r.status_code, round((time.perf_counter() - t) * 1000), "ms")
cursor = r.json()["data"]["next_cursor"]
t = time.perf_counter(); r = requests.get(B, params={**P, "cursor": cursor}, headers={**H, "X-Forwarded-For": "10.99.0.2"}, verify=False, timeout=300)
print("page2 alone", r.status_code, round((time.perf_counter() - t) * 1000), "ms")
before = blkio()
def one(i):
    t = time.perf_counter()
    s = requests.get(B, params={**P, "cursor": cursor}, headers={**H, "X-Forwarded-For": f"10.99.1.{i+1}"}, verify=False, timeout=600).status_code
    return s, round((time.perf_counter() - t) * 1000)
t = time.perf_counter()
with ThreadPoolExecutor(n) as pool:
    res = list(pool.map(one, range(n)))
print(f"{n} concurrent page2: wall {round(time.perf_counter() - t)} s, each ms {sorted(x[1] for x in res)}, statuses {set(x[0] for x in res)}")
print("db blockio before", before, "after", blkio())
