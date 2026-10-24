import sys, uuid
sys.path.insert(0, "D:/Data science/mushukent/backend/tests")
import pytest
from fastapi.testclient import TestClient
from geoalchemy2.elements import WKTElement
from sqlalchemy import select
from app.infrastructure.db.models import schema
from app.main import app
from test_interactions import (  # noqa
    interactions_runtime, client, _create_user_with_token as mk, _create_cat, _create_post, _create_comment,
)

def H(t): return {"Authorization": f"Bearer {t}"}

# ---------- F-01 blocking ----------
def test_f01_block_effect(client, interactions_runtime):
    m = interactions_runtime.db_session_manager; ts = interactions_runtime.token_service
    a, ta = mk(m, ts, email=f"a-{uuid.uuid4().hex}@e.com", name="Alice")
    b, tb = mk(m, ts, email=f"b-{uuid.uuid4().hex}@e.com", name="Bob")
    cat = _create_cat(m, creator_id=a.id)
    pa = _create_post(m, cat_id=cat.id, user_id=a.id, description="alice post")
    pb = _create_post(m, cat_id=cat.id, user_id=b.id, description="bob post")
    r = client.post(f"/api/v1/users/{b.id}/block", headers=H(ta))
    print("block:", r.status_code)
    assert r.status_code in (200, 201, 204)
    # (1) bob comments on alice's post after being blocked
    r = client.post(f"/api/v1/posts/{pa}/comments", headers=H(tb), json={"content": "hi from blocked bob"})
    print("blocked user comment status:", r.status_code)
    # (2) alice sees bob's comment
    r2 = client.get(f"/api/v1/posts/{pa}/comments", headers=H(ta))
    seen = [c for c in r2.json().get("data", {}).get("items", r2.json().get("data", [])) if "blocked bob" in str(c)]
    print("alice sees blocked bob's comment:", bool(seen))
    # (3) feed shows bob's post to alice
    f = client.get("/api/v1/feed", headers=H(ta)).json()
    print("alice feed contains bob post:", "bob post" in str(f))
    # (4) notification created for alice
    n = client.get("/api/v1/notifications", headers=H(ta)).json()
    print("alice notification from blocked bob:", "Bob" in str(n) or len(str(n)) > 120, str(n)[:200])
    # (5) like
    lk = client.post(f"/api/v1/posts/{pa}/likes", headers=H(tb)).status_code
    print("blocked user like status:", lk)
    assert not seen, "blocked user's comment still visible"
    assert "bob post" not in str(f), "blocked user's post still in feed"

# ---------- F-02 rate limit ----------
def _rl_client(monkeypatch):
    for k, v in dict(RATE_LIMIT_ENABLED="true", RATE_LIMIT_ANON_PER_MINUTE="3", RATE_LIMIT_USER_PER_MINUTE="3",
                     RATE_LIMIT_AUTH_PER_MINUTE="100", RATE_LIMIT_UPLOAD_PER_MINUTE="3",
                     RATE_LIMIT_PUBLIC_READ_PER_MINUTE="3").items():
        monkeypatch.setenv(k, v)
    from app.core.config import get_settings
    get_settings.cache_clear()
    from app.main import create_app
    return create_app()

def test_f02_rate_limit_bypass(monkeypatch):
    a = _rl_client(monkeypatch)
    with TestClient(a) as c:
        plain = [c.get("/api/v1/health").status_code for _ in range(10)]
        print("no token       :", plain)
    a = _rl_client(monkeypatch)
    with TestClient(a) as c:
        same = [c.get("/api/v1/health", headers=H("garbage")).status_code for _ in range(10)]
        print("same garbage   :", same)
    a = _rl_client(monkeypatch)
    with TestClient(a) as c:
        rnd = [c.get("/api/v1/health", headers=H(uuid.uuid4().hex)).status_code for _ in range(200)]
        print("random per req : 429 count =", rnd.count(429), "of", len(rnd))
        store = None
        for mw in a.user_middleware: pass
    assert 429 in plain and rnd.count(429) == 0

def test_f03_memory_growth_and_per_process():
    from app.core.rate_limit import InMemoryRateLimitStore, FixedWindowRateLimiter
    s = InMemoryRateLimitStore(); l = FixedWindowRateLimiter(store=s, window_seconds=60, clock=lambda: 0.0)
    for i in range(50000): l.check(key=f"token:{i}", limit=3)
    print("keys after 50k distinct tokens:", len(s._hits))
    l2 = FixedWindowRateLimiter(store=InMemoryRateLimitStore(), window_seconds=60, clock=lambda: 0.0)
    l1 = FixedWindowRateLimiter(store=InMemoryRateLimitStore(), window_seconds=60, clock=lambda: 0.0)
    ok = sum(l.check(key="ip:1", limit=3).allowed for l in (l1, l2) for _ in range(5))
    print("allowed with limit 3 across 2 independent workers:", ok)
    # time passes: keys still stored after window expiry?
    l = FixedWindowRateLimiter(store=s, window_seconds=60, clock=lambda: 10_000.0)
    l.check(key="other", limit=3)
    print("stale keys retained after window expiry:", len(s._hits))
    assert len(s._hits) > 50000
