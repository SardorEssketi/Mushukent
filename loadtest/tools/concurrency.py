"""Phase 3 concurrency and consistency checks against the emulated box (never production).

Each check prints PASS/FAIL with the evidence and writes results/<out>/concurrency.json.
Writes go only to the disposable load database. Run with the loadtest venv:

    .venv/Scripts/python tools/concurrency.py results/<dir>

Checks
  hot_like       N distinct users like ONE post at the same time (viral post, H7):
                 latency, 5xx, final like_count == rows in likes.
  toggle_tabs    one account, two "tabs" hammering like/unlike on one post: count stays
                 equal to the rows, never negative.
  idempotent     5 concurrent POST /posts with the same Idempotency-Key: exactly one post.
  double_post    5 concurrent POST /posts WITHOUT a key (old clients / API): how many posts.
  reveal_race    two users reveal the same lost pet's contact at once; one user reveals 20
                 different pets concurrently: quota must hold.
  delete_live    a post is deleted while 30 viewers fetch it / batch-view it: only 200/404,
                 never 5xx; views on the deleted post are skipped.
  expiry         expired access token mid-action: 401 then refresh then success.
  popular_drift  page through `popular` while likes land on posts below the cursor: count
                 items skipped / duplicated versus a frozen snapshot (H9).
  recent_insert  page through `recent` while new posts arrive: duplicates / skips (H9).
  nearby_pages   page through `nearby` to the end: duplicates / skips and per-page latency.
"""

from __future__ import annotations

import io
import json
import os
import random
import subprocess
import sys
import time
import uuid
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

import requests
import urllib3

urllib3.disable_warnings()
HERE = Path(__file__).resolve().parent.parent
DATA = json.loads((HERE / "results" / "tokens.json").read_text(encoding="utf-8"))
BASE = os.getenv("LT_HOST", "https://127.0.0.1:18443") + "/api/v1"
USERS = DATA["users"]
results: dict[str, dict] = {}


def h(user=None, ip=None, token=None):
    headers = {"Host": "api.mushukistan.uz", "X-Forwarded-For": ip or f"10.200.{random.randint(0, 255)}.{random.randint(1, 254)}"}
    if user is not None or token:
        headers["Authorization"] = f"Bearer {token or user['token']}"
    return headers


def req(method, path, **kw):
    started = time.perf_counter()
    try:
        r = requests.request(method, BASE + path, verify=False, timeout=60, **kw)
        return r.status_code, (time.perf_counter() - started) * 1000, r
    except requests.RequestException as exc:
        return f"exc:{type(exc).__name__}", (time.perf_counter() - started) * 1000, None


def sql(query: str) -> str:
    return subprocess.run(
        ["docker", "exec", "mushukistan-load-db-1", "psql", "-U", "mushukistan", "-d",
         "mushukistan_load", "-At", "-c", query], capture_output=True, text=True).stdout.strip()


def record(name, ok, **evidence):
    results[name] = {"pass": ok, **evidence}
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {json.dumps(evidence, default=str)}", flush=True)


def codes(items):
    out: dict[str, int] = {}
    for c in items:
        out[str(c)] = out.get(str(c), 0) + 1
    return out


def pct(values, q):
    values = sorted(values)
    return round(values[min(len(values) - 1, int(q / 100 * (len(values) - 1)))]) if values else 0


def hot_like(n=200):
    post = sql("select id from posts where deleted_at is null and is_public order by created_at desc limit 1")
    sql(f"delete from likes where post_id='{post}'; update posts set like_count=0 where id='{post}'")
    users = USERS[:n]
    with ThreadPoolExecutor(max_workers=n) as pool:
        out = list(pool.map(lambda u: req("POST", f"/posts/{post}/likes", headers=h(u)), users))
    statuses = [o[0] for o in out]
    lat = [o[1] for o in out]
    rows = int(sql(f"select count(*) from likes where post_id='{post}'"))
    count = int(sql(f"select like_count from posts where id='{post}'"))
    record("hot_like", rows == count == statuses.count(200) and not any(
        str(s).startswith("5") or str(s).startswith("exc") for s in statuses),
        users=n, statuses=codes(statuses), p50_ms=pct(lat, 50), p95_ms=pct(lat, 95),
        max_ms=pct(lat, 100), like_rows=rows, like_count=count)


def toggle_tabs(rounds=40):
    post = sql("select id from posts where deleted_at is null and is_public order by created_at desc offset 1 limit 1")
    user = USERS[300]
    sql(f"delete from likes where post_id='{post}'; update posts set like_count=0 where id='{post}'")

    def tab(_):
        out = []
        for _ in range(rounds):
            out.append(req(random.choice(["POST", "DELETE"]), f"/posts/{post}/likes", headers=h(user, ip="10.201.0.1"))[0])
        return out

    with ThreadPoolExecutor(max_workers=2) as pool:
        statuses = sum(pool.map(tab, range(2)), [])
    rows = int(sql(f"select count(*) from likes where post_id='{post}'"))
    count = int(sql(f"select like_count from posts where id='{post}'"))
    record("toggle_tabs", rows == count and count in (0, 1), statuses=codes(statuses),
           like_rows=rows, like_count=count)


def _post_body():
    from PIL import Image  # noqa: PLC0415

    buf = io.BytesIO()
    Image.new("RGB", (800, 600), (random.randint(0, 255), 90, 120)).save(buf, "JPEG")
    data = {"description": f"concurrency {uuid.uuid4().hex[:6]}", "kind": "observation", "status": "healthy",
            "location": json.dumps({"latitude": 41.31, "longitude": 69.28}),
            "new_cat": json.dumps({"name": "Race cat"})}
    return data, buf.getvalue()


def idempotent(key=True, n=5):
    user = USERS[301 if key else 302]
    data, photo = _post_body()
    before = int(sql(f"select count(*) from posts where user_id='{user['user_id']}'"))
    headers = h(user, ip="10.202.0.1")
    if key:
        headers["Idempotency-Key"] = str(uuid.uuid4())

    def send(_):
        return req("POST", "/posts", headers=headers, data=data,
                   files=[("photos", ("p.jpg", photo, "image/jpeg"))])

    with ThreadPoolExecutor(max_workers=n) as pool:
        out = list(pool.map(send, range(n)))
    after = int(sql(f"select count(*) from posts where user_id='{user['user_id']}'"))
    ids = {o[2].json()["data"]["id"] for o in out if o[2] is not None and o[0] in (200, 201)}
    name = "idempotent" if key else "double_post"
    ok = (after - before == 1 and len(ids) == 1) if key else True
    record(name, ok, statuses=codes([o[0] for o in out]), posts_created=after - before,
           distinct_ids_returned=len(ids), note=None if key else "informational: no key = no dedupe")


def reveal_race():
    pet = DATA["lost_pets"][0]
    a, b = USERS[310], USERS[311]
    with ThreadPoolExecutor(max_workers=2) as pool:
        out = list(pool.map(lambda u: req("POST", f"/lost-pets/{pet}/contact-reveal", headers=h(u)), [a, b]))
    pets = DATA["lost_pets"][1:21]
    user = USERS[312]
    with ThreadPoolExecutor(max_workers=20) as pool:
        many = list(pool.map(lambda p: req("POST", f"/lost-pets/{p}/contact-reveal", headers=h(user, ip="10.203.0.1")), pets))
    stored = int(sql(f"select count(*) from contact_reveals where viewer_id='{user['user_id']}'")
                 or 0) if sql("select 1 from information_schema.columns where table_name='contact_reveals' and column_name='viewer_id'") else None
    ok200 = sum(1 for o in many if o[0] == 200)
    record("reveal_race", all(o[0] == 200 for o in out) and ok200 <= 15 and all(
        not str(o[0]).startswith("5") for o in many), two_users=codes([o[0] for o in out]),
        one_user_20_pets=codes([o[0] for o in many]), allowed_per_day=15, stored_rows=stored)


def delete_live(viewers=30):
    owner = USERS[320]
    data, photo = _post_body()
    s, _, r = req("POST", "/posts", headers={**h(owner), "Idempotency-Key": str(uuid.uuid4())}, data=data,
                  files=[("photos", ("p.jpg", photo, "image/jpeg"))])
    post = r.json()["data"]["id"]
    stop = time.time() + 6
    statuses: list = []

    def view(i):
        u = USERS[330 + i]
        out = []
        while time.time() < stop:
            out.append(req("GET", f"/posts/{post}", headers=h(u))[0])
            out.append(req("POST", "/views/seen", headers=h(u), json={"items": [{"kind": "post", "id": post}]})[0])
        return out

    with ThreadPoolExecutor(max_workers=viewers + 1) as pool:
        futures = [pool.submit(view, i) for i in range(viewers)]
        time.sleep(2)
        deleted = req("DELETE", f"/posts/{post}", headers=h(owner))[0]
        for f in futures:
            statuses += f.result()
    bad = [s for s in statuses if str(s).startswith("5") or str(s).startswith("exc")]
    record("delete_live", not bad and deleted == 204, delete_status=deleted, viewer_statuses=codes(statuses))


def expiry():
    u = USERS[340]
    post = random.choice(DATA["posts"])
    s1 = req("POST", f"/posts/{post}/likes", headers=h(token=u["expired_token"]))[0]
    s2, _, r = req("POST", "/auth/refresh", headers=h(), json={"refresh_token": u["refresh_token"]})
    new = r.json()["data"]["access_token"] if s2 == 200 else None
    s3 = req("POST", f"/posts/{post}/likes", headers=h(token=new))[0] if new else None
    record("expiry", s1 == 401 and s2 == 200 and s3 in (200, 409), expired=s1, refresh=s2, retry=s3)


def page_through(filter_by, limit=20, max_pages=60, during=None, extra=None):
    user = USERS[350]
    seen, dupes, cursor, lat = [], 0, None, []
    for page in range(max_pages):
        params = {"filter": filter_by, "limit": limit, **(extra or {})}
        if cursor:
            params["cursor"] = cursor
        status, ms, r = req("GET", "/feed", headers=h(user, ip="10.204.0.1"), params=params)
        lat.append(ms)
        if status != 200:
            return seen, dupes, lat, f"status {status} on page {page}"
        body = r.json()["data"]
        for item in body["items"]:
            if item["id"] in seen:
                dupes += 1
            seen.append(item["id"])
        if during:
            during(page)
        cursor = body.get("next_cursor")
        if not cursor:
            break
    return seen, dupes, lat, None


def popular_drift(pages=15):
    # Snapshot of what `popular` would list right now (same visibility: public, visible cat).
    snapshot = sql(f"""select string_agg(id::text, ',') from (select p.id from posts p join cats c on c.id=p.cat_id
        where p.deleted_at is null and p.is_public and c.deleted_at is null and c.is_active and c.merged_into is null
        order by p.like_count desc, p.created_at desc, p.id desc limit {pages * 20}) s""").split(",")
    likers = iter(USERS[400:600])

    def during(page):
        # After each page, 5 users like posts that are just *below* the current cursor and
        # 5 posts the reader has not reached yet get likes (they move up past the cursor).
        target = snapshot[min(len(snapshot) - 1, (page + 1) * 20 + 30): min(len(snapshot), (page + 1) * 20 + 35)]
        for post in target:
            try:
                req("POST", f"/posts/{post}/likes", headers=h(next(likers)))
            except StopIteration:
                return

    seen, dupes, lat, err = page_through("popular", max_pages=pages, during=during)
    skipped = [p for p in snapshot[: len(seen)] if p not in set(seen)]
    record("popular_drift", dupes == 0 and not skipped and not err, pages=pages, items=len(seen),
           duplicates=dupes, skipped_vs_snapshot=len(skipped), error=err, p95_ms=pct(lat, 95))


def recent_insert(pages=10):
    poster = USERS[360]

    def during(page):
        data, photo = _post_body()
        req("POST", "/posts", headers={**h(poster), "Idempotency-Key": str(uuid.uuid4())}, data=data,
            files=[("photos", ("p.jpg", photo, "image/jpeg"))])

    seen, dupes, lat, err = page_through("recent", max_pages=pages, during=during)
    record("recent_insert", dupes == 0 and not err, pages=pages, items=len(seen), duplicates=dupes,
           error=err, p95_ms=pct(lat, 95))


def nearby_pages():
    seen, dupes, lat, err = page_through("nearby", max_pages=400, limit=20,
                                         extra={"lat": 41.3111, "lon": 69.2797, "radius_meters": 3000})
    expected = int(sql("""select (select count(*) from posts p join cats c on c.id=p.cat_id
        where p.deleted_at is null and p.is_public and c.deleted_at is null and c.is_active and c.merged_into is null
        and p.location is not null and ST_DWithin(p.location::geography, ST_SetSRID(ST_MakePoint(69.2797,41.3111),4326)::geography, 3000))
        + (select count(*) from lost_pets where deleted_at is null and is_public and not is_resolved
        and ST_DWithin(last_seen_location::geography, ST_SetSRID(ST_MakePoint(69.2797,41.3111),4326)::geography, 3000))"""))
    record("nearby_pages", dupes == 0 and len(set(seen)) == expected and not err, pages=len(lat),
           items=len(seen), expected=expected, duplicates=dupes, error=err,
           page1_ms=round(lat[0]) if lat else None, p50_ms=pct(lat, 50), p95_ms=pct(lat, 95),
           last_page_ms=round(lat[-1]) if lat else None)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else HERE / "results" / "concurrency"
    out.mkdir(parents=True, exist_ok=True)
    only = set(sys.argv[2].split(",")) if len(sys.argv) > 2 else None
    for check in (hot_like, toggle_tabs, lambda: idempotent(True), lambda: idempotent(False), reveal_race,
                  delete_live, expiry, popular_drift, recent_insert, nearby_pages):
        name = getattr(check, "__name__", "idempotent")
        if only and name not in only and not (name == "<lambda>" and "idempotent" in only):
            continue
        try:
            check()
        except Exception as exc:  # keep going; report the crash as a failure
            record(name, False, crashed=f"{type(exc).__name__}: {exc}")
    (out / "concurrency.json").write_text(json.dumps(results, indent=1, default=str), encoding="utf-8")


if __name__ == "__main__":
    main()
