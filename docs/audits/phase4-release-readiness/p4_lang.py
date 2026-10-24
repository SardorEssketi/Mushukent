import sys, json, time, subprocess, httpx
SP = "C:/Users/PRESTIGE/AppData/Local/Temp/claude/D--Data-science-mushukent/565c4ae5-c465-4122-8dcd-3088c125b554/scratchpad"
sys.path.insert(0, SP)
import j as jmod
from j import J
jmod.O = "http://127.0.0.1:18441"
B = "http://127.0.0.1:18440/api/v1"
ids = json.load(open(SP + "/ids_and.json"))
res = []


def check(l, ok):
    res.append(bool(ok)); print(("PASS " if ok else "FAIL ") + l, flush=True)


def pid_on(port):
    for line in subprocess.run(["netstat", "-ano"], capture_output=True, text=True).stdout.splitlines():
        if f":{port} " in line and "LISTENING" in line:
            return int(line.split()[-1])


def labels(j):
    return [n["label"] for n in j.nodes(1.0)]


def has(j, t, wait=0):
    end = time.time() + wait
    while True:
        if any(t in l for l in labels(j)):
            return True
        if time.time() >= end:
            return False
        j.b.pump(1.0)


tok = httpx.post(B + "/auth/login", json={"email": "bf-bob@example.com", "password": "StrongPass123"}).json()["data"]["access_token"]
httpx.patch(B + "/users/me", headers={"Authorization": "Bearer " + tok}, json={"preferred_language": "uz"})
j = J(port=9650, prof=f"prof_lang_{int(time.time())}", w=390, h=844, mobile=True)
b = j.b
try:
    j.theme("light")
    j.open("/login", wait=6)
    for _ in range(15):
        if j.inputs():
            break
        b.pump(1.0); j.nodes(0.3)
    j.type_into("email", "bf-bob@example.com"); j.type_into("password", "StrongPass123")
    j.tap("Login", exact=True, wait=5)
    for u in ids.values():
        b.js(f"localStorage.setItem('mushukistan_authenticated_onboarding_seen_{u}','true')")
    j.open("/profile", wait=6)
    check("online: UI is Uzbek for the Uzbek account", has(j, "Profil", wait=5) or has(j, "Tahrirlash", wait=3))
    print("stored language key:", b.js("localStorage.getItem('mushukistan_app_language') || Object.keys(localStorage).filter(k=>k.indexOf('lang')>=0).join(',')"))
    pid = pid_on(18440)
    subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True)
    time.sleep(2)
    j.open("/profile", wait=8)
    print("url", j.url(), [l[:40] for l in labels(j)][:5])
    check("cold start during outage shows the OUTAGE screen in Uzbek (saved language)", has(j, "Serverga ulanib bo‘lmadi", wait=5))
    check("not shown in English", not has(j, "Can’t reach the server"))
    j.shot("p4_lang_uz_outage")
    subprocess.Popen(["C:/Program Files/Git/bin/bash.exe", SP + "/start_and_backend.sh"], stdout=open(SP + "/and_backend3.log", "w"), stderr=subprocess.STDOUT)
    for _ in range(60):
        time.sleep(1)
        try:
            if httpx.get(B + "/health", timeout=2).status_code == 200:
                break
        except Exception:
            pass
    check("recovers after the backend returns", has(j, "Profil", wait=60) or has(j, "Tahrirlash", wait=5))
finally:
    j.close()
    httpx.patch(B + "/users/me", headers={"Authorization": "Bearer " + tok}, json={"preferred_language": "en"})
print("SUMMARY", sum(res), "/", len(res))
