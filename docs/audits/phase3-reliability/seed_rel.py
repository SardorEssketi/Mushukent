import io, json, sys
import httpx
from PIL import Image

B = "http://127.0.0.1:18430/api/v1"
c = httpx.Client(timeout=60)


def jpg(color):
    b = io.BytesIO()
    Image.new("RGB", (640, 480), color).save(b, "JPEG")
    return b.getvalue()


def user(email, name, phone):
    r = c.post(f"{B}/auth/register", json={"email": email, "password": "StrongPass123", "name": name,
                                          "accept_terms": True, "accept_privacy": True, "preferred_language": "en"})
    tok = r.json()["data"]["dev_verification_token"]
    c.post(f"{B}/auth/verify-email", json={"token": tok})
    d = c.post(f"{B}/auth/login", json={"email": email, "password": "StrongPass123"}).json()["data"]
    h = {"Authorization": "Bearer " + d["access_token"]}
    c.patch(f"{B}/users/me", headers=h, json={"phone_number": phone})
    return h, d["user"]["id"]


ha, ida = user("bf-alice@example.com", "Alice Blocker", "+998 90 111 22 33")
hb, idb = user("bf-bob@example.com", "Bob Blocked", "+998 91 444 55 66")
hc, idc = user("bf-carol@example.com", "Carol Bystander", "+998 93 777 88 99")


def post(h, text, color, la=41.31, lo=69.28):
    r = c.post(f"{B}/posts", headers=h, data={"description": text, "kind": "observation", "status": "healthy",
               "location": json.dumps({"latitude": la, "longitude": lo}), "new_cat": json.dumps({"name": text[:20]})},
               files=[("photos", ("p.jpg", jpg(color), "image/jpeg"))])
    assert r.status_code == 201, r.text
    return r.json()["data"]["id"]


ids = {"a": ida, "b": idb, "c": idc}
ids["alice_post"] = post(ha, "ALICE-POST cat by the park", (200, 80, 60))
ids["carol_post"] = post(hc, "CAROL-POST cat on the roof", (60, 160, 80))
ids["bob_post1"] = post(hb, "BOB-POST-ONE cat in the yard", (60, 80, 200))
ids["bob_post2"] = post(hb, "BOB-POST-TWO cat on the fence", (180, 60, 200))
r = c.post(f"{B}/lost-pets", headers=hb, data={"pet_name": "BobsLostPet", "last_seen_location": json.dumps({"latitude": 41.3, "longitude": 69.27}),
           "additional_info": "bob lost pet", "owner_phone_publication_consent": "true"}, files=[("photos", ("l.jpg", jpg((250, 140, 20)), "image/jpeg"))])
ids["bob_lost"] = r.json()["data"]["id"]
r = c.post(f"{B}/lost-pets", headers=ha, data={"pet_name": "AlicesLostPet", "last_seen_location": json.dumps({"latitude": 41.32, "longitude": 69.29}),
           "additional_info": "alice lost pet", "owner_phone_publication_consent": "true"}, files=[("photos", ("l.jpg", jpg((20, 140, 250)), "image/jpeg"))])
ids["alice_lost"] = r.json()["data"]["id"]
# Bob comments on Alice's post BEFORE any block -> Alice gets a notification
r = c.post(f"{B}/posts/{ids['alice_post']}/comments", headers=hb, json={"content": "BOB-COMMENT before the block"})
assert r.status_code == 201, r.text
json.dump(ids, open(sys.argv[1], "w"))
print(ids)
print("alice unread before block:", c.get(f"{B}/notifications/unread-count", headers=ha).json())
