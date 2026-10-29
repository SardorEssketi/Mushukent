import sys
sys.path.insert(0, "C:/Users/PRESTIGE/AppData/Local/Temp/claude/D--Data-science-mushukent/565c4ae5-c465-4122-8dcd-3088c125b554/scratchpad")
from bfj import *

results = []
alice = api_token("bf-alice@example.com")
httpx.delete(f"{B}/users/{ids['b']}/block", headers=alice)   # start from a clean relationship
j = J(port=9600, prof="prof_bf_bob", w=390, h=844, mobile=True)
b = j.b
ALICE = {"ALICE-POST", "AlicesLostPet"}
ALICE_ABSENT = ALICE | {"Alice Blocker"}
try:
    j.theme("light")
    login(j, "bf-bob@example.com")
    j.open("/feed", wait=7)
    found = scan(j, NEEDLES)
    print("Bob feed before block sees:", sorted(found))
    results.append(check("before block: Bob sees Alice content", ALICE <= found))

    # Stale UI: Bob has Alice's lost-pet page open, composes a comment...
    j.open(f"/lost-pets/{ids['alice_lost']}", wait=6)
    results.append(check("before block: Bob can open Alice's lost-pet page", has(j, "AlicesLostPet", wait=4)))
    b.send("Input.dispatchMouseEvent", type="mouseWheel", x=195, y=500, deltaX=0, deltaY=600); b.pump(1.5)
    j.nodes(0.5)
    j.type_into("comment", "BOB-STALE-COMMENT"); b.pump(1)
    j.shot("bf_bob_stale_compose")
    # ...and meanwhile Alice blocks Bob.
    print("Alice blocks Bob:", httpx.post(f"{B}/users/{ids['b']}/block", headers=alice).status_code)
    b.requests.clear()
    n = j.find("Post comment"); b.click(n["x"], n["y"]); b.pump(2.5)
    r = reqs(b)
    print("REQS on stale submit:", r)
    post = [x for x in r if x[0] == "POST"]
    results.append(check("stale submit reaches server and is rejected (no crash)", bool(post)))
    j.shot("bf_bob_stale_submit")
    results.append(check("UI still responsive after rejection", has(j, "Post comment") or has(j, "Comments")))
    stored = httpx.get(f"{B}/lost-pets/{ids['alice_lost']}/comments", headers=alice).json()["data"]["items"]
    results.append(check("rejected comment was not stored", all("BOB-STALE" not in c["content"] for c in stored)))
    print("snackbar/error text present:", [l for l in labels(j) if "not" in l.lower() or "could" in l.lower()][:4])

    # Bob's feed after the block: Alice's content hidden, Carol's visible.
    j.open("/feed", wait=7)
    found = scan(j, NEEDLES)
    print("Bob's feed after block sees:", sorted(found))
    results.append(check("after block: Alice's content hidden from Bob", not (ALICE_ABSENT & found)))
    results.append(check("after block: Carol's and Bob's own content visible to Bob", {"CAROL-POST", "BOB-POST", "BobsLostPet"} <= found))
    j.open(f"/lost-pets/{ids['alice_lost']}", wait=6)
    j.shot("bf_bob_blocked_lostpet")
    results.append(check("direct URL to Alice's lost pet shows no content to Bob", not has(j, "AlicesLostPet") and not has(j, "alice lost pet")))
    j.open(f"/posts/{ids['alice_post']}", wait=5)
    results.append(check("direct URL to Alice's post shows no content to Bob", not has(j, "ALICE-POST") and not has(j, "Alice Blocker")))

    # Unblock and confirm everything returns.
    print("Alice unblocks Bob:", httpx.delete(f"{B}/users/{ids['b']}/block", headers=alice).status_code)
    j.open("/feed", wait=7)
    found = scan(j, NEEDLES)
    results.append(check("after unblock: Alice's content visible to Bob again", ALICE <= found))
    j.open(f"/lost-pets/{ids['alice_lost']}", wait=6)
    results.append(check("after unblock: Bob can open Alice's lost pet again", has(j, "AlicesLostPet", wait=4)))
    print("CONSOLE errors:", [c for c in b.console if c[0] in ("error", "EXCEPTION")][:4])
finally:
    j.close()
print("SUMMARY", sum(results), "/", len(results))
