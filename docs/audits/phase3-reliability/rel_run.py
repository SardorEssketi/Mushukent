import sys, json, time, subprocess, httpx
SP = "C:/Users/PRESTIGE/AppData/Local/Temp/claude/D--Data-science-mushukent/565c4ae5-c465-4122-8dcd-3088c125b554/scratchpad"
sys.path.insert(0, SP)
import j as jmod
from j import J, show
jmod.O = "http://127.0.0.1:18431"

VIEW = sys.argv[1]  # desktop | mobile
W, H, MOB = (1366, 768, False) if VIEW == "desktop" else (390, 844, True)
ids = json.load(open(SP + "/ids_rel.json"))
B = "http://127.0.0.1:18430/api/v1"
results = []


def check(label, ok):
    results.append(bool(ok))
    print(("PASS " if ok else "FAIL ") + label, flush=True)


def pid_on(port):
    out = subprocess.run(["netstat", "-ano"], capture_output=True, text=True).stdout
    for line in out.splitlines():
        if f"127.0.0.1:{port} " in line and "LISTENING" in line:
            return int(line.split()[-1])


def kill_backend():
    pid = pid_on(18430)
    subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
    for _ in range(20):
        time.sleep(0.5)
        if pid_on(18430) is None:
            break
    return pid


def start_backend():
    subprocess.Popen(["C:/Program Files/Git/bin/bash.exe", SP + "/start_rel_backend.sh"], stdout=open(SP + "/rel_backend2.log", "w"), stderr=subprocess.STDOUT)
    for _ in range(60):
        time.sleep(1)
        try:
            if httpx.get(B + "/health", timeout=2).status_code == 200:
                return pid_on(18430)
        except Exception:
            pass
    return None


def labels(j):
    return [n["label"] for n in j.nodes(1.0)]


def has(j, text, wait=0):
    end = time.time() + wait
    while True:
        if any(text in l for l in labels(j)):
            return True
        if time.time() >= end:
            return False
        j.b.pump(1.0)


def has_button(j, text):
    return any(n["role"] == "button" and n["label"].strip() == text for n in j.nodes(0.5))


def tokens(b):
    return b.js("JSON.stringify([localStorage.getItem('mushukistan_access_token')?'A':null, localStorage.getItem('mushukistan_refresh_token')?'R':null])")


def api_reqs(b, since=0):
    return [(t, m, u.split("/api/v1")[-1][:40]) for (m, u), t in zip(b.requests, b.req_t) if "18430/api" in u and m != "OPTIONS" and t >= since]


def login(j, email):
    j.open("/login", wait=6)
    for _ in range(15):
        if j.inputs():
            break
        j.b.pump(1.0); j.nodes(0.3)
    j.type_into("email", email); j.type_into("password", "StrongPass123")
    j.tap("Login", exact=True, wait=5)
    for uid in (ids["a"], ids["b"], ids["c"]):
        j.b.js(f"localStorage.setItem('mushukistan_authenticated_onboarding_seen_{uid}','true')")


j = J(port=9620, prof=f"prof_rel_{VIEW}_{int(time.time())}", w=W, h=H, mobile=MOB)
b = j.b
alice_email = "bf-alice@example.com"
try:
    j.theme("light")
    print(f"=== {VIEW} {W}x{H}")
    login(j, alice_email)
    j.open("/profile", wait=6)
    check("signed in: profile shows Alice's account actions", has(j, "Edit profile", wait=6))
    j.shot(f"rel_{VIEW}_1_profile_online")
    tok_online = tokens(b)

    # ---- A. outage while the page is open (in-session) ----
    pid = kill_backend()
    print("backend stopped, old pid", pid)
    j.open("/feed", wait=2)   # fresh feed load is a restore with the backend down? (page reload below)
    # ---- B. browser reload during the outage on a protected route ----
    b.requests.clear(); b.req_t.clear()
    t_reload = time.time()
    j.open("/profile", wait=7)
    print("URL after reload on /profile during outage:", j.url())
    check("reload during outage on /profile -> retry screen, not sign-in", j.url().startswith("/session-unavailable"))
    check("retry screen explains the situation", has(j, "Can’t reach the server"))
    check("no Login / Create account offered during outage", not has_button(j, "Login") and not has_button(j, "Create account"))
    check("credentials preserved in browser storage", tokens(b) == tok_online)
    j.shot(f"rel_{VIEW}_2_outage_profile")

    # ---- C. other direct navigation during the outage ----
    for path in ("/notifications", "/add", "/profile/settings"):
        j.open(path, wait=6)
        check(f"direct navigation {path} -> retry screen (url {j.url()[:40]})", j.url().startswith("/session-unavailable") and has(j, "Can’t reach the server"))
    j.open("/feed", wait=6)
    check("public feed stays reachable during outage", j.url() == "/feed")
    check("feed shows reconnect notice, no signed-out welcome", has(j, "Can’t reach the server") and not has_button(j, "Login") and not has_button(j, "Create account"))
    j.shot(f"rel_{VIEW}_3_outage_feed")
    check("credentials still preserved after navigation", tokens(b) == tok_online)

    # ---- D. polling budget: count restore requests over a quiet minute ----
    b.requests.clear(); b.req_t.clear()
    t0 = time.time()
    j.open("/profile", wait=3)
    b.pump(62)
    me = [r for r in api_reqs(b, t0) if r[2].startswith("/users/me")]
    print("users/me requests in ~65 s outage window:", len(me), [round(r[0] - t0, 1) for r in me])
    check(f"bounded automatic re-checks (<= 1 initial + 5 retries; saw {len(me)})", 1 <= len(me) <= 6)
    others = [r for r in api_reqs(b, t0) if not r[2].startswith("/users/me") and not r[2].startswith("/feed")]
    print("other API calls in window:", [r[2] for r in others][:8])
    check("no runaway request pattern (total API calls in window <= 12)", len(api_reqs(b, t0)) <= 12)

    # ---- E. recovery ----
    newpid = start_backend()
    print("backend restarted, pid", newpid)
    t_up = time.time()
    # click Retry on the screen (works regardless of the automatic schedule)
    j.open("/profile", wait=2)
    clicked = j.tap("Retry", exact=True, wait=1)
    recovered = has(j, "Edit profile", wait=25)
    print("recovery seconds after backend up:", round(time.time() - t_up, 1), "| url", j.url())
    check("session recovers after the backend returns (profile visible)", recovered)
    check("returned to the requested page", j.url() == "/profile")
    check("same credentials, never signed out", tokens(b) == tok_online)
    j.shot(f"rel_{VIEW}_4_recovered")

    # ---- F. automatic recovery without any click ----
    pid = kill_backend()
    j.open("/profile", wait=6)
    check("second outage: retry screen again", j.url().startswith("/session-unavailable"))
    start_backend()
    t_up = time.time()
    auto = has(j, "Edit profile", wait=60)
    print("automatic recovery took", round(time.time() - t_up, 1), "s; url", j.url())
    check("automatic re-check restores the session by itself", auto and j.url() == "/profile")

    # ---- G. explicit logout, then protected route requires sign-in ----
    j.shot(f"rel_{VIEW}_5_before_logout")
    j.tap("Settings", wait=1.5)
    show([n for n in j.nodes() if n["role"] in ("menuitem", "button")][:12], 12)
    out = j.tap("Logout", wait=1.5)
    j.nodes(1)
    confirm = [n for n in j.nodes() if n["role"] == "button" and n["label"].strip().lower() in ("logout", "log out")]
    if confirm:
        b.click(confirm[-1]["x"], confirm[-1]["y"]); b.pump(3)
    check("explicit logout clears stored credentials", tokens(b) == json.dumps([None, None]).replace(" ", ""))
    j.open("/profile", wait=5)
    check("after logout /profile asks to sign in (not the outage screen)", j.url().startswith("/auth-required") and has_button(j, "Login"))
    j.shot(f"rel_{VIEW}_6_after_logout")

    # ---- H. account switching: Bob (Russian) must not see Alice data ----
    login(j, "bf-bob@example.com")
    j.open("/profile", wait=6)
    check("account switch: Bob's profile visible", has(j, "Bob Blocked", wait=6) or has(j, "Bob", wait=2))
    check("account switch: nothing of Alice remains on screen", not has(j, "Alice Blocker"))
    check("account switch: UI switched to Bob's language (Russian)", has(j, "Профиль", wait=3) or has(j, "Редактировать", wait=2))
    j.shot(f"rel_{VIEW}_7_bob_ru")

    # ---- I. outage in Russian after recovery path: stop, reload, language falls back to default ----
    kill_backend()
    j.open("/profile", wait=7)
    print("ru-user outage screen labels:", [l[:40] for l in labels(j) if l][:6])
    j.shot(f"rel_{VIEW}_8_outage_after_bob")
    check("outage screen visible for second account too", j.url().startswith("/session-unavailable"))
    start_backend()
    check("second account recovers automatically", has(j, "Bob", wait=60) or has(j, "Профиль", wait=5))

    print("CONSOLE errors (first 5):", [c[1][:90] for c in b.console if c[0] in ("error", "EXCEPTION")][:5])
finally:
    j.close()
    if pid_on(18430) is None:
        start_backend()
print("SUMMARY", VIEW, sum(results), "/", len(results))
