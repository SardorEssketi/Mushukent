import sys
sys.path.insert(0, "C:/Users/PRESTIGE/AppData/Local/Temp/claude/D--Data-science-mushukent/565c4ae5-c465-4122-8dcd-3088c125b554/scratchpad")
from bfj import *

results = []
j = J(port=9600, prof="prof_bf_alice", w=390, h=844, mobile=True)
b = j.b
BOB = {"BOB-POST", "BobsLostPet", "Bob Blocked"}
try:
    j.theme("light")
    login(j, "bf-alice@example.com")
    print("URL after login", j.url())
    j.open("/feed", wait=7)
    found = scan(j, NEEDLES)
    print("feed before block sees:", sorted(found))
    results.append(check("before block: Alice sees Bob's content (posts, lost pet, author)", BOB <= found))
    results.append(check("before block: Alice sees Carol's and her own content", {"CAROL-POST", "ALICE-POST", "AlicesLostPet"} <= found))
    j.shot("bf_feed_before")
    api = api_token("bf-alice@example.com")
    print("API unread before:", httpx.get(B + "/notifications/unread-count", headers=api).json()["data"])

    # Open Bob's profile from the feed (in-app navigation, no reload) and block him.
    b.js("window.scrollTo(0,0)")
    n = j.find("Bob Blocked", exact=False)
    b.click(n["x"], n["y"]); b.pump(3)
    print("URL profile after tapping Bob's author row:", j.url())
    j.shot("bf_profile_before_block")
    j.tap("Profile actions", wait=1.5)
    j.tap("Block user", wait=2)
    j.nodes(1)
    b.requests.clear()
    btns = [x for x in j.nodes() if x["role"] == "button" and x["label"].strip().lower() == "block"]
    b.click(btns[-1]["x"], btns[-1]["y"]); b.pump(1.2)
    results.append(check("snackbar confirms 'User blocked.'", has(j, "User blocked")))
    j.shot("bf_after_block_profile")
    b.pump(2)
    r = reqs(b)
    print("REQS after block:", r)
    results.append(check("block sends POST /users/{id}/block", ("POST", f"/users/{ids['b']}/block") in r))
    results.append(check("block refreshes feed + unread badge (cache invalidation)", any(x[1].startswith("/feed") for x in r) and any("unread-count" in x[1] for x in r)))
    j.tap("Profile actions", wait=1.5)
    results.append(check("menu now offers Unblock", any(x["label"].strip() == "Unblock" for x in j.nodes())))
    b.key("Escape"); b.pump(1)

    # Back to the feed WITHOUT reloading the page.
    b.js("history.back()"); b.pump(4)
    print("URL after back:", j.url())
    found = scan(j, NEEDLES)
    print("feed after block (no reload) sees:", sorted(found))
    results.append(check("after block (no reload): none of Bob's content in feed", not (BOB & found)))
    results.append(check("after block (no reload): Carol's and Alice's content still there", {"CAROL-POST", "ALICE-POST", "AlicesLostPet"} <= found))
    j.shot("bf_feed_after_block_noreload")

    j.open("/feed", wait=7)
    found = scan(j, NEEDLES)
    print("feed after reload sees:", sorted(found))
    results.append(check("after browser reload: none of Bob's content", not (BOB & found)))
    results.append(check("after browser reload: Alice's & Carol's content visible", {"CAROL-POST", "ALICE-POST"} <= found))

    lost = [i["pet_name"] for i in httpx.get(B + "/lost-pets", headers=api).json()["data"]["items"]]
    results.append(check("API: lost-pets list hides Bob's pet for Alice", "BobsLostPet" not in lost and "AlicesLostPet" in lost))

    j.open(f"/posts/{ids['bob_post1']}", wait=5)
    j.shot("bf_blocked_post_direct")
    results.append(check("direct URL to blocked user's post shows no post content", not has(j, "BOB-POST") and not has(j, "Bob Blocked")))

    j.open("/notifications", wait=5)
    j.shot("bf_notifications_blocked")
    results.append(check("pre-block comment notification from Bob hidden in inbox", not has(j, "Bob Blocked") and not has(j, "BOB-COMMENT")))
    unread = httpx.get(B + "/notifications/unread-count", headers=api).json()["data"]
    results.append(check(f"unread count is 0 while blocked (got {unread})", unread.get("count") == 0))

    j.open("/profile/settings", wait=5)
    j.shot("bf_settings")
    j.tap("Blocked users", wait=3)
    print("URL blocked users:", j.url())
    results.append(check("Settings > Blocked users lists Bob", has(j, "Bob Blocked", wait=4)))
    j.shot("bf_blocked_users_screen")
    b.requests.clear()
    j.tap("Unblock", exact=True, wait=1.5)
    results.append(check("unblock snackbar 'User unblocked.'", has(j, "User unblocked")))
    b.pump(2)
    r = reqs(b)
    print("REQS after unblock:", r)
    results.append(check("unblock sends DELETE", ("DELETE", f"/users/{ids['b']}/block") in r))
    results.append(check("row removed, empty state shown", has(j, "You have not blocked anyone", wait=4)))
    j.shot("bf_blocked_users_empty")
    j.open("/feed", wait=7)
    found = scan(j, NEEDLES)
    print("feed after unblock sees:", sorted(found))
    results.append(check("after unblock: Bob's content is back", BOB <= found))
    j.shot("bf_feed_after_unblock")
    print("unread after unblock:", httpx.get(B + "/notifications/unread-count", headers=api).json()["data"])
    print("CONSOLE errors:", [c for c in b.console if c[0] in ("error", "EXCEPTION")][:5])
finally:
    j.close()
print("SUMMARY", sum(results), "/", len(results))
