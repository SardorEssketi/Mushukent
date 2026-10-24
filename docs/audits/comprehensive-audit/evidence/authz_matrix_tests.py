import sys, uuid, json, importlib, pkgutil, re
sys.path.insert(0, "D:/Data science/mushukent/backend/tests")
import pytest
from fastapi.routing import APIRoute
from geoalchemy2.elements import WKTElement
from app.infrastructure.db.models import schema
import app.api.v1.routes as pkg
from test_interactions import (  # noqa
    interactions_runtime, client, _create_user_with_token as mk, _create_cat, _create_post, _create_comment,
)
AUTHREQ = {"get_current_user", "get_current_active_user", "require_moderator", "get_current_principal"}
OPT = {"get_optional_current_user", "get_optional_current_principal"}
PHONE = "+998901234567"


def H(t):
    return {"Authorization": f"Bearer {t}"}


def deps(d, acc):
    for s in d.dependencies:
        acc.add(getattr(s.call, "__name__", "?"))
        deps(s, acc)


def all_routes():
    out = []
    for m in pkgutil.iter_modules(pkg.__path__):
        mod = importlib.import_module(f"app.api.v1.routes.{m.name}")
        for r in mod.router.routes:
            if isinstance(r, APIRoute):
                acc = set()
                deps(r.dependant, acc)
                kind = "required" if acc & AUTHREQ else ("optional" if acc & OPT else "none")
                for meth in sorted(r.methods):
                    out.append((meth, "/api/v1" + r.path, kind))
    return sorted(set(out), key=lambda x: (x[1], x[0]))


def fill(p):
    return re.sub(r"\{[^}]+\}", lambda m: str(uuid.uuid4()), p)


def test_unauthenticated_sweep(client):
    rows = []
    for meth, path, auth in all_routes():
        r = client.request(meth, fill(path))
        rows.append((meth, path, auth, r.status_code))
    for x in rows:
        print("SWEEP", *x)
    bad = [x for x in rows if x[2] == "required" and x[3] != 401]
    assert not bad, bad


def test_invalid_and_inactive_tokens(client, interactions_runtime):
    m = interactions_runtime.db_session_manager
    ts = interactions_runtime.token_service
    u, t = mk(m, ts, email=f"x-{uuid.uuid4().hex}@e.com", is_active=False)
    for label, tok in (("inactive", t), ("garbage", "abc.def.ghi"), ("tampered", t[:-3] + "AAA")):
        r = client.get("/api/v1/users/me", headers=H(tok))
        print("TOKEN", label, r.status_code)
    r = client.get("/api/v1/feed", headers=H("abc.def.ghi"))
    print("TOKEN garbage-on-public-feed", r.status_code)


def mkpet(m, uid, consent=False, kind="lost"):
    with m.session_scope() as s:
        cls = schema.LostPet if kind == "lost" else schema.AdoptionPost
        kw = dict(user_id=uid, pet_name="Rex", owner_phone_number=PHONE,
                  owner_phone_publication_consent=consent, additional_info="x")
        if kind == "lost":
            kw["last_seen_location"] = WKTElement("POINT(69.25 41.3)", srid=4326)
        o = cls(**kw)
        s.add(o)
        s.flush()
        ph = schema.LostPetPhoto if kind == "lost" else schema.AdoptionPostPhoto
        fk = "lost_pet_id" if kind == "lost" else "adoption_post_id"
        s.add(ph(**{fk: o.id, "photo_url": "https://example.com/p.jpg", "thumb_url": "https://example.com/t.jpg", "position": 0}))
        s.flush()
        return o.id


def test_ownership(client, interactions_runtime):
    m = interactions_runtime.db_session_manager
    ts = interactions_runtime.token_service
    a, ta = mk(m, ts, email=f"a-{uuid.uuid4().hex}@e.com", name="Alice")
    b, tb = mk(m, ts, email=f"b-{uuid.uuid4().hex}@e.com", name="Bob")
    mod, tm = mk(m, ts, email=f"m-{uuid.uuid4().hex}@e.com", name="Mod", is_moderator=True)
    cat = _create_cat(m, creator_id=a.id)
    post = _create_post(m, cat_id=cat.id, user_id=a.id)
    com = _create_comment(m, post_id=post, user_id=a.id, content="alice comment")
    lost = mkpet(m, a.id, consent=False)
    lostc = mkpet(m, a.id, consent=True)
    adopt = mkpet(m, a.id, kind="adopt")
    names = {str(post): "{post}", str(com): "{comment}", str(lost): "{lost}", str(lostc): "{lostc}",
             str(adopt): "{adopt}", str(cat.id): "{cat}", str(a.id): "{A}"}
    res = []

    def t(label, meth, path, tok, expect, **kw):
        r = client.request(meth, path, headers=H(tok) if tok else {}, **kw)
        p = path
        for k, v in names.items():
            p = p.replace(k, v)
        who = {tb: "B", tm: "mod", ta: "A"}.get(tok, "anon")
        res.append((label, meth, p, who, r.status_code, expect, "OK" if r.status_code in expect else "MISMATCH"))
        return r

    t("patch other post", "PATCH", f"/api/v1/posts/{post}", tb, (403, 404), json={"description": "pwn"})
    t("delete other post", "DELETE", f"/api/v1/posts/{post}", tb, (403, 404))
    t("patch other comment", "PATCH", f"/api/v1/comments/{com}", tb, (403, 404), json={"content": "pwn"})
    t("delete other comment", "DELETE", f"/api/v1/comments/{com}", tb, (403, 404))
    t("patch other lost pet", "PATCH", f"/api/v1/lost-pets/{lost}", tb, (403, 404), json={"pet_name": "pwn"})
    t("delete other lost pet", "DELETE", f"/api/v1/lost-pets/{lost}", tb, (403, 404))
    t("resolve other lost pet", "PATCH", f"/api/v1/lost-pets/{lost}/resolution", tb, (403, 404), json={"is_resolved": True})
    t("patch other adoption", "PATCH", f"/api/v1/adoption-posts/{adopt}", tb, (403, 404), json={"pet_name": "pwn"})
    t("delete other adoption", "DELETE", f"/api/v1/adoption-posts/{adopt}", tb, (403, 404))
    t("resolve other adoption", "PATCH", f"/api/v1/adoption-posts/{adopt}/resolution", tb, (403, 404), json={"is_resolved": True})
    t("user -> moderation list", "GET", "/api/v1/moderation/reports", tb, (403,))
    t("user -> moderation delete", "DELETE", f"/api/v1/moderation/posts/{post}", tb, (403,))
    t("user -> post history", "GET", f"/api/v1/moderation/posts/{post}/history", tb, (403,))
    t("moderator -> moderation list", "GET", "/api/v1/moderation/reports", tm, (200,))
    t("non-owner renames cat (documented MVP)", "PATCH", f"/api/v1/cats/{cat.id}", tb, (200,), json={"name": "Hacked"})
    t("non-mod sets cat status", "PATCH", f"/api/v1/cats/{cat.id}", tb, (403,), json={"status": "healthy"})
    t("cat cover_photo_url external", "PATCH", f"/api/v1/cats/{cat.id}", tb, (200, 422), json={"cover_photo_url": "http://169.254.169.254/x.jpg"})

    pub = client.get(f"/api/v1/users/{a.id}").json()["data"]
    print("PUBLIC_PROFILE_KEYS", sorted(pub.keys()))
    print("PUBLIC_PROFILE_LEAKED", [k for k in ("email", "phone_number", "telegram_username", "is_moderator") if k in pub])
    lp = client.get(f"/api/v1/lost-pets/{lost}").text
    lpc = client.get(f"/api/v1/lost-pets/{lostc}").text
    print("LOST_PHONE_VISIBLE_ANON noconsent=", PHONE in lp, "consent=", PHONE in lpc)
    print("LOST_LIST_ANON_CONTAINS_PHONE", PHONE in client.get("/api/v1/lost-pets").text)
    print("ADOPT_ANON_PHONE_VISIBLE noconsent=", PHONE in client.get(f"/api/v1/adoption-posts/{adopt}").text)

    client.post(f"/api/v1/posts/{post}/comments", headers=H(tb), json={"content": "hello"})
    items = client.get("/api/v1/notifications", headers=H(ta)).json()["data"]["items"]
    nid = items[0]["id"] if items else str(uuid.uuid4())
    t("read other notification", "POST", f"/api/v1/notifications/{nid}/read", tb, (403, 404))
    t("owner reads own notification", "POST", f"/api/v1/notifications/{nid}/read", ta, (200, 204))

    r = client.patch("/api/v1/users/me", headers=H(ta), json={"allow_public_activity_view": False})
    print("PRIVACY_TOGGLE", r.status_code)
    for p in ("posts", "comments"):
        r = client.get(f"/api/v1/users/{a.id}/{p}", headers=H(tb))
        n = len(r.json().get("data", {}).get("items", [])) if r.status_code == 200 else "-"
        print("ACTIVITY_PRIVATE", p, r.status_code, n)

    client.post(f"/api/v1/users/{b.id}/block", headers=H(ta))
    print("BLOCKED_PROFILE_FETCH", client.get(f"/api/v1/users/{a.id}", headers=H(tb)).status_code)
    t("blocked user contacts owner (lost)", "POST", f"/api/v1/lost-pets/{lostc}/contact", tb, (403, 404), json={})

    c, tc = mk(m, ts, email=f"c-{uuid.uuid4().hex}@e.com", name="Carol")
    r = client.delete("/api/v1/users/me", headers=H(tc))
    print("DELETE_ME", r.status_code, r.text[:120])
    print("TOKEN_AFTER_DELETE", client.get("/api/v1/users/me", headers=H(tc)).status_code)
    print("LIKE_AFTER_DELETE", client.post(f"/api/v1/posts/{post}/likes", headers=H(tc)).status_code)
    for x in res:
        print("AUTHZ", *x)
