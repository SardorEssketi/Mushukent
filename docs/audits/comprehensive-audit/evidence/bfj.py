import sys, json, httpx
sys.path.insert(0, "C:/Users/PRESTIGE/AppData/Local/Temp/claude/D--Data-science-mushukent/565c4ae5-c465-4122-8dcd-3088c125b554/scratchpad")
import j as jmod
from j import J, show
jmod.O = "http://127.0.0.1:18411"
import sem
SP = "C:/Users/PRESTIGE/AppData/Local/Temp/claude/D--Data-science-mushukent/565c4ae5-c465-4122-8dcd-3088c125b554/scratchpad"
ids = json.load(open(SP + "/ids_bf.json"))
B = "http://127.0.0.1:18410/api/v1"


def api_token(email):
    return {"Authorization": "Bearer " + httpx.post(B + "/auth/login", json={"email": email, "password": "StrongPass123"}).json()["data"]["access_token"]}


def labels(j):
    return [n["label"] for n in j.nodes(1.0)]


def has(j, text, wait=0):
    import time
    end = time.time() + wait
    while True:
        if any(text in l for l in labels(j)):
            return True
        if time.time() >= end:
            return False
        j.b.pump(1.0)


def login(j, email):
    j.open("/login", wait=6)
    for _ in range(15):
        if j.inputs():
            break
        j.b.pump(1.0); j.nodes(0.3)
    j.type_into("email", email)
    j.type_into("password", "StrongPass123")
    j.tap("Login", exact=True, wait=4)
    for uid in (ids["a"], ids["b"], ids["c"]):
        j.b.js(f"localStorage.setItem('mushukistan_authenticated_onboarding_seen_{uid}','true')")


def reqs(b):
    return [(m, u.split("/api/v1")[-1][:60]) for m, u in b.requests if "18410/api" in u and m != "OPTIONS"]


def check(label, ok):
    print(("PASS " if ok else "FAIL ") + label, flush=True)
    return ok


def scan(j, needles, steps=16):
    """Scroll the feed top to bottom collecting accessibility labels; return which needles appeared."""
    found = set()
    j.b.send("Input.dispatchMouseEvent", type="mouseWheel", x=195, y=500, deltaX=0, deltaY=-8000)
    j.b.pump(1.0)
    for _ in range(steps):
        for l in labels(j):
            for n in needles:
                if n in l:
                    found.add(n)
        j.b.send("Input.dispatchMouseEvent", type="mouseWheel", x=195, y=500, deltaX=0, deltaY=500)
        j.b.pump(1.2)
    j.b.send("Input.dispatchMouseEvent", type="mouseWheel", x=195, y=500, deltaX=0, deltaY=-8000)
    j.b.pump(1.0)
    return found


NEEDLES = ["BOB-POST", "BobsLostPet", "Bob Blocked", "ALICE-POST", "AlicesLostPet", "CAROL-POST"]
