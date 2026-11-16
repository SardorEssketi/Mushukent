"""Scenario-based load model for Mushukistan (Feed + Map focus).

Each Locust user is one app session that behaves like the Flutter client (see REPORT.md, "Load
model"): a cold start, foreground activity of one persona, and the background timers that every
open client runs (unread count 1/min, lost-pet + adoption follow-up checks 1/min, batched
`POST /views/seen` every 10 s while cards are being seen). Sessions end after an exponential
duration (mean SESSION_MEAN_S) and the user starts a new cold session.

Personas (weights are env-configurable; defaults are the REPORT assumptions):
  guest_feed, guest_map           -> no token; identity = client IP
  user_feed, user_map, user_poster -> minted access token (seed.py)

Client IP: every user gets its own address by default (LT_USERS_PER_IP=1). Set LT_USERS_PER_IP=N
to put N users behind one address (CGNAT, H3). Addresses travel in X-Forwarded-For through the
production nginx config; the backend trusts it because nginx (the immediate peer) is trusted.

Requests that the real client sends WITHOUT a bearer token even for signed-in users
(`includeViewerContext: false` / `authenticated: false`): map marker tap
`GET /cats/{id}/posts`, `GET /places`, `GET /places/{id}`. They are modelled the same way.

Status codes per endpoint are written to $LT_OUT/status_counts.json at the end of a run.
OSM tiles are never requested (not our server; see REPORT H4).
"""

from __future__ import annotations

import io
import json
import math
import os
import random
import time
import uuid
from collections import Counter
from pathlib import Path

from locust import FastHttpUser, constant, events, task
from locust.exception import StopUser

HERE = Path(__file__).parent
DATA = json.loads((HERE / "results" / "tokens.json").read_text(encoding="utf-8"))
OUT = Path(os.getenv("LT_OUT", HERE / "results" / "latest"))
OUT.mkdir(parents=True, exist_ok=True)

USERS_PER_IP = int(os.getenv("LT_USERS_PER_IP", "1"))
SESSION_MEAN_S = float(os.getenv("LT_SESSION_MEAN_S", "480"))
UPLOADS = os.getenv("LT_UPLOADS", "1") == "1"
EXPIRED_TOKENS = os.getenv("LT_EXPIRED_TOKENS", "0") == "1"  # spike after idle: refresh storm
PACE = float(os.getenv("LT_PACE", "1.0"))  # >1 = more active users (stress / heavy profile)

LON0, LAT0 = 69.2797, 41.3111
BOUNDS = (69.05, 41.18, 69.47, 41.43)
CATEGORIES = ["pet_shop", "veterinary", "shelter", "veterinary_pharmacy"]

status_counts: Counter[str] = Counter()
_user_seq = 0
_t0 = time.time()
_raw = (OUT / "requests.csv").open("w", encoding="utf-8")
_raw.write("t,name,status,ms,persona\n")


@events.request.add_listener
def _count(request_type, name, response, exception, response_time, context=None, **_):
    code = getattr(response, "status_code", None) or 0
    if exception and not code:
        code = "exc"
    status_counts[f"{name} {code}"] += 1
    persona = (context or {}).get("persona", "")
    _raw.write(f"{time.time() - _t0:.2f},{name},{code},{response_time:.1f},{persona}\n")


@events.test_stop.add_listener
def _dump(**_):
    _raw.flush()
    (OUT / "status_counts.json").write_text(
        json.dumps(dict(sorted(status_counts.items())), indent=1), encoding="utf-8"
    )


def _jpeg(width=1920, height=1440) -> bytes:
    """A ~1 MB JPEG like the client produces (1920px max side, quality 90)."""
    from PIL import Image  # noqa: PLC0415

    noise = os.urandom(width * height * 3 // 16)
    image = Image.frombytes("RGB", (width // 4, height // 4), noise[: (width // 4) * (height // 4) * 3])
    image = image.resize((width, height))
    buffer = io.BytesIO()
    image.save(buffer, "JPEG", quality=90)
    return buffer.getvalue()


try:
    PHOTO = _jpeg()
except Exception:  # Pillow missing: fall back to a pre-generated file
    PHOTO = (HERE / "seed" / "photo.jpg").read_bytes()


def multipart(fields: dict[str, str], photos: list[bytes]) -> tuple[bytes, str]:
    boundary = uuid.uuid4().hex
    parts = []
    for key, value in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{key}"\r\n\r\n'
                     f"{value}\r\n".encode())
    for i, photo in enumerate(photos):
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="photos"; '
                     f'filename="p{i}.jpg"\r\nContent-Type: image/jpeg\r\n\r\n'.encode()
                     + photo + b"\r\n")
    parts.append(f"--{boundary}--\r\n".encode())
    return b"".join(parts), f"multipart/form-data; boundary={boundary}"


def _ip_for(index: int) -> str:
    group = index // USERS_PER_IP
    return f"10.{(group >> 16) & 255}.{(group >> 8) & 255}.{group & 255 or 1}"


class Session(FastHttpUser):
    abstract = True
    host = os.getenv("LT_HOST", "https://127.0.0.1:18443")
    insecure = True
    connection_timeout = 30.0
    network_timeout = 60.0  # the Flutter client's request timeout is environment-specific
    wait_time = constant(0.25)
    signed_in = False
    persona = "base"

    def on_start(self):
        global _user_seq
        self.index = _user_seq
        _user_seq += 1
        self.ip = _ip_for(self.index)
        self.viewer_id = str(uuid.uuid4())
        if self.signed_in:
            account = DATA["users"][self.index % len(DATA["users"])]
            self.access = account["expired_token"] if EXPIRED_TOKENS else account["token"]
            self.refresh = account["refresh_token"]
        self.pending_seen: list[dict] = []
        self.feed_cursor = None
        self.feed_filter = "recent"
        self.viewport = None
        self._new_session()

    # ---- plumbing ---------------------------------------------------------------------------
    def headers(self, auth=True):
        h = {"Host": "api.mushukistan.uz", "X-Forwarded-For": self.ip,
             "X-Viewer-Id": self.viewer_id, "Accept": "application/json"}
        if auth and self.signed_in:
            h["Authorization"] = f"Bearer {self.access}"
        return h

    def call(self, method, path, name, auth=True, retry_on_401=True, **kw):
        with self.client.request(method, f"/api/v1/{path}", name=name, headers=self.headers(auth),
                                 catch_response=True, context={"persona": self.persona},
                                 **kw) as resp:
            code = resp.status_code
            if code == 401 and auth and self.signed_in and retry_on_401:
                resp.success()  # the client refreshes and retries; count the retry instead
                if self._refresh():
                    return self.call(method, path, name, auth, retry_on_401=False, **kw)
                return resp
            if code == 429:
                resp.failure("429")
            elif code >= 500 or code == 0:
                resp.failure(f"{code}")
            elif code in (404, 409):
                resp.success()  # likes on liked posts, deleted posts: expected in a live feed
            return resp

    def _refresh(self) -> bool:
        with self.client.post("/api/v1/auth/refresh", name="POST /auth/refresh",
                              headers={"Host": "api.mushukistan.uz", "X-Forwarded-For": self.ip},
                              json={"refresh_token": self.refresh}, catch_response=True,
                              context={"persona": self.persona}) as resp:
            if resp.status_code == 200:
                self.access = resp.json()["data"]["access_token"]
                return True
            resp.failure(str(resp.status_code))
            return False

    def json(self, resp):
        try:
            return resp.json().get("data") or {}
        except Exception:
            return {}

    def every(self, key, seconds):
        now = time.monotonic()
        if now >= self.due.get(key, 0):
            self.due[key] = now + random.uniform(0.8, 1.2) * seconds / PACE
            return True
        return False

    # ---- session lifecycle ------------------------------------------------------------------
    def _new_session(self):
        self.session_end = time.monotonic() + random.expovariate(1 / SESSION_MEAN_S)
        self.due: dict[str, float] = {}
        now = time.monotonic()
        # Background timers fire for the first time at a random phase, like real clients.
        for key in ("unread", "followups"):
            self.due[key] = now + random.uniform(5, 60)
        self.cold_start()

    def cold_start(self):
        if self.signed_in:
            for _ in range(3):  # F-24: three /users/me at start-up
                self.call("GET", "users/me", "GET /users/me")
            self.call("GET", "notifications/unread-count", "GET /notifications/unread-count")
            self.call("GET", "lost-pets/follow-ups/due", "GET /lost-pets/follow-ups/due")
            self.call("GET", "adoption-posts/follow-ups/due", "GET /adoption-posts/follow-ups/due")
        self.start_persona()

    def start_persona(self):
        pass

    def background(self):
        if not self.signed_in:
            return
        if self.every("unread", 60):
            self.call("GET", "notifications/unread-count", "GET /notifications/unread-count")
        if self.every("followups", 60):
            self.call("GET", "lost-pets/follow-ups/due", "GET /lost-pets/follow-ups/due")
            self.call("GET", "adoption-posts/follow-ups/due", "GET /adoption-posts/follow-ups/due")

    def flush_seen(self):
        if self.pending_seen and self.every("seen", 10):
            batch, self.pending_seen = self.pending_seen[:20], self.pending_seen[20:]
            self.call("POST", "views/seen", "POST /views/seen", json={"items": batch})

    @task
    def tick(self):
        if time.monotonic() >= self.session_end:
            self._new_session()
            return
        self.background()
        self.flush_seen()
        self.foreground()

    def foreground(self):
        pass

    # ---- feed --------------------------------------------------------------------------------
    def feed_page(self, first=False):
        if first or self.feed_cursor is None:
            roll = random.random()
            self.feed_filter = ("recent" if roll < 0.75 else "popular" if roll < 0.85
                                else "nearby" if roll < 0.95 else "needs_help")
            self.feed_cursor = None
        params = {"filter": self.feed_filter, "limit": 20}
        if self.feed_filter == "nearby":
            params.update(lat=41.3111, lon=69.2797, radius_meters=5000)
        if self.feed_cursor:
            params["cursor"] = self.feed_cursor
        page = "page1" if not self.feed_cursor else "pageN"
        resp = self.call("GET", "feed", f"GET /feed {self.feed_filter} {page}", params=params)
        data = self.json(resp)
        self.feed_cursor = data.get("next_cursor")
        for item in data.get("items", [])[:20]:
            kind = {"lost_pet": "lost_pet", "adoption": "adoption"}.get(item.get("item_type"), "post")
            if item.get("id"):
                self.pending_seen.append({"kind": kind, "id": item["id"]})
        self.last_items = [i for i in data.get("items", []) if i.get("item_type", "observation")
                           in ("observation", None) and i.get("id")]

    def open_post(self, post_id):
        self.call("GET", f"posts/{post_id}", "GET /posts/{id}")
        self.call("GET", f"posts/{post_id}/comments", "GET /posts/{id}/comments",
                  params={"limit": 20})
        self.call("POST", f"posts/{post_id}/views", "POST /posts/{id}/views")

    def pick_post(self):
        items = getattr(self, "last_items", None)
        if items and random.random() < 0.8:
            return random.choice(items)["id"]
        pool = DATA["hot_posts"] if random.random() < 0.3 else DATA["posts"]
        return random.choice(pool)

    # ---- map ---------------------------------------------------------------------------------
    def map_open(self):
        if random.random() < 0.25:  # places cache (6 h, local storage) misses for ~1 in 4 sessions
            for category in CATEGORIES:
                self.places_category(category, BOUNDS, depth=0)
        zoom_span = random.choice([0.06, 0.1, 0.16, 0.25])  # ~zoom 15..12 on a phone
        lon = LON0 + random.gauss(0, 0.04)
        lat = LAT0 + random.gauss(0, 0.025)
        self.viewport = [lon, lat, zoom_span]
        self.map_viewport()

    def places_category(self, category, bbox, depth):
        resp = self.call("GET", "places", "GET /places (map per category)", auth=False,
                         params={"category": category, "map_only": "true", "limit": 200,
                                 "bbox": ",".join(f"{v:.5f}" for v in bbox)})
        items = self.json(resp).get("items", [])
        if len(items) >= 200 and depth < 2:  # client splits capped bboxes
            w, s, e, n = bbox
            mx, my = (w + e) / 2, (s + n) / 2
            for sub in ((w, s, mx, my), (mx, s, e, my), (w, my, mx, n), (mx, my, e, n)):
                self.places_category(category, sub, depth + 1)

    def bbox(self):
        lon, lat, span = self.viewport
        w = max(BOUNDS[0], lon - span / 2)
        e = min(BOUNDS[2], lon + span / 2)
        s = max(BOUNDS[1], lat - span * 0.9 / 2)
        n = min(BOUNDS[3], lat + span * 0.9 / 2)
        return f"{w:.5f},{s:.5f},{e:.5f},{n:.5f}"

    def map_viewport(self):
        box = self.bbox()
        resp = self.call("GET", "cats", "GET /cats (map bbox)",
                         params={"filter": "recently_added", "bbox": box, "limit": 100})
        self.map_cats = [c["id"] for c in self.json(resp).get("items", []) if c.get("id")]
        resp = self.call("GET", "lost-pets/map", "GET /lost-pets/map", params={"bbox": box,
                                                                              "limit": 100})
        self.map_lost = [p["id"] for p in self.json(resp).get("items", []) if p.get("id")]

    def map_pan(self):
        lon, lat, span = self.viewport
        angle = random.uniform(0, 2 * math.pi)
        dist = span * random.uniform(0.3, 0.8)
        if random.random() < 0.25:  # pinch zoom
            span = min(0.4, max(0.03, span * random.choice([0.5, 2.0])))
        lon = lon + dist * math.cos(angle)
        lat = lat + dist * math.sin(angle) * 0.6
        # The client's camera cannot leave tashkentMapBounds; keep the centre inside them.
        lon = min(max(lon, BOUNDS[0] + span / 2), BOUNDS[2] - span / 2)
        lat = min(max(lat, BOUNDS[1] + span * 0.45), BOUNDS[3] - span * 0.45)
        self.viewport = [lon, lat, span]
        self.map_viewport()

    def marker_tap(self):
        if getattr(self, "map_lost", None) and random.random() < 0.15:
            self.call("GET", f"lost-pets/{random.choice(self.map_lost)}", "GET /lost-pets/{id}")
            return
        if getattr(self, "map_cats", None):
            # includeViewerContext: false -> no bearer token, even when signed in.
            self.call("GET", f"cats/{random.choice(self.map_cats)}/posts",
                      "GET /cats/{id}/posts (marker tap)", auth=False,
                      params={"limit": 1, "sort": "latest"})


class GuestFeed(Session):
    weight = int(os.getenv("LT_W_GUEST_FEED", "21"))
    persona = "guest_feed"

    def start_persona(self):
        self.feed_page(first=True)

    def foreground(self):
        if self.every("page", 25):
            self.feed_page()
        if self.every("open", 75):
            self.open_post(self.pick_post())


class GuestMap(Session):
    weight = int(os.getenv("LT_W_GUEST_MAP", "14"))
    persona = "guest_map"

    def start_persona(self):
        self.map_open()

    def foreground(self):
        if self.every("pan", 8):
            self.map_pan()
        if self.every("tap", 30):
            self.marker_tap()


class UserFeed(Session):
    weight = int(os.getenv("LT_W_USER_FEED", "29"))
    persona = "user_feed"
    signed_in = True

    def start_persona(self):
        self.feed_page(first=True)

    def foreground(self):
        if self.every("page", 25):
            self.feed_page()
        if self.every("open", 60):
            self.open_post(self.pick_post())
        if self.every("like", 45):
            post = self.pick_post()
            resp = self.call("POST", f"posts/{post}/likes", "POST /posts/{id}/likes")
            if resp.status_code == 409 and random.random() < 0.5:
                self.call("DELETE", f"posts/{post}/likes", "DELETE /posts/{id}/likes")
        if self.every("comment", 300):
            self.call("POST", f"posts/{self.pick_post()}/comments", "POST /posts/{id}/comments",
                      json={"content": f"load comment {uuid.uuid4().hex[:8]}"})
        if self.every("save", 400):
            self.call("POST", f"posts/{self.pick_post()}/saved", "POST /posts/{id}/saved")


class UserMap(Session):
    weight = int(os.getenv("LT_W_USER_MAP", "23"))
    persona = "user_map"
    signed_in = True

    def start_persona(self):
        self.map_open()

    def foreground(self):
        if self.every("pan", 8):
            self.map_pan()
        if self.every("tap", 25):
            self.marker_tap()


class UserPoster(Session):
    weight = int(os.getenv("LT_W_USER_POSTER", "13"))
    persona = "user_poster"
    signed_in = True

    def start_persona(self):
        self.feed_page(first=True)

    def foreground(self):
        if self.every("page", 40):
            self.feed_page()
        if UPLOADS and self.every("post", 600):
            self.create_post()

    def create_post(self):
        photos = random.choice([1, 1, 2, 3])
        lon = LON0 + random.gauss(0, 0.04)
        lat = LAT0 + random.gauss(0, 0.025)
        data = {"description": "load-test observation", "kind": "observation",
                "status": "healthy", "location": json.dumps({"latitude": lat, "longitude": lon}),
                "new_cat": json.dumps({"name": "Load cat"})}
        headers = self.headers()
        headers["Idempotency-Key"] = str(uuid.uuid4())
        body, content_type = multipart(data, [PHOTO] * photos)
        headers["Content-Type"] = content_type
        with self.client.post("/api/v1/posts", name="POST /posts (upload)", headers=headers,
                              data=body, catch_response=True,
                              context={"persona": self.persona}) as resp:
            if resp.status_code == 429:
                resp.failure("429")
            elif resp.status_code >= 400 or resp.status_code == 0:
                resp.failure(str(resp.status_code))


# ---- load shapes (select with LT_SHAPE) ------------------------------------------------------
SHAPE = os.getenv("LT_SHAPE")
if SHAPE:
    from locust import LoadTestShape

    STAGES = {
        # (end_second, users, spawn_rate)
        "baseline": [(300, 10, 2)],
        "target": [(600, 300, 0.5), (1500, 300, 1)],          # ramp 10 min, hold 15 min
        # 0 -> 300 in 1 min, hold 5 min, then drop to 30 users for 5 min to see if it recovers
        # (LT_SPIKE_HOLD_S / LT_SPIKE_TAIL_S shorten it; tail 0 ends at the hold, e.g. for
        # LT_RECOVERY=1)
        "spike": [(60, 300, 5), (60 + int(os.getenv("LT_SPIKE_HOLD_S", "300")), 300, 5)]
                 + ([(60 + int(os.getenv("LT_SPIKE_HOLD_S", "300"))
                      + int(os.getenv("LT_SPIKE_TAIL_S", "300")), 30, 50)]
                    if int(os.getenv("LT_SPIKE_TAIL_S", "300")) > 0 else []),
        # 3-minute steps of 20 users to locate the knee (target already fails at ~110)
        # LT_STEP_USERS per 3-minute step, LT_STEPS steps (defaults: 20 x 8)
        "stress": [(int(os.getenv("LT_STEP_S", "180")) * (i + 1),
                    int(os.getenv("LT_STEP_USERS", "20")) * (i + 1), 2)
                   for i in range(int(os.getenv("LT_STEPS", "8")))],
        "soak": [(300, int(os.getenv("LT_USERS", "200")), 1),
                 (300 + int(os.getenv("LT_SOAK_S", "3600")), int(os.getenv("LT_USERS", "200")), 1)],
        "short": [(60, int(os.getenv("LT_USERS", "50")), 10),
                  (60 + int(os.getenv("LT_HOLD_S", "300")), int(os.getenv("LT_USERS", "50")), 10)],
    }[SHAPE]

    class Shape(LoadTestShape):
        def tick(self):
            run_time = self.get_run_time()
            for end, users, rate in STAGES:
                if run_time < end:
                    return users, rate
            return None
