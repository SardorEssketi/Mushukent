"""Seed the disposable load-test database with Tashkent-area data and mint test tokens.

Usage (inside the backend image, see compose.yml `seed` service):
    python /seed/seed.py --scale 1      # "realistic" dataset for ~300 concurrent users
    python /seed/seed.py --scale 10     # 10x content and users (places stay the same)

Everything is generated with set-based SQL (generate_series) so the 10x dataset takes minutes,
not hours. Popularity is skewed (likes/views/comments follow a power law over posts) and
locations cluster around the city centre, so the popular feed, map bboxes and the hot-row cases
look like a real city rather than uniform noise.

Refuses to run unless the database name contains "load" or "test" and the host is the compose
`db` service or localhost (same spirit as backend/tests/db_safety.py).

Writes /results/tokens.json: access tokens (JWT, signed with the stack's throwaway secret)
for the first N users, so the load generator never calls /auth/login (10/min per IP).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import secrets
import time
import uuid
from datetime import UTC, datetime, timedelta

from jose import jwt
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url

BASE = {
    "users": 12_000,
    "cats": 10_000,
    "posts": 30_000,
    "comments": 60_000,
    "likes": 250_000,
    "views": 1_200_000,
    "saved": 20_000,
    "lost_pets": 800,
    "adoption": 400,
    "notifications": 100_000,
}
PLACES = 1_000
LOGIN_PASSWORD = "LoadTest-Password-1"  # disposable local accounts only
ALERT_USERS_SHARE = 0.30  # users with nearby lost-pet alerts on and an alert location
DEVICE_USERS_SHARE = 0.40  # users with an Android push device

# Tashkent: centre and the client's allowed map bounds (frontend map_viewport.dart).
LON0, LAT0 = 69.2797, 41.3111
LON_MIN, LON_MAX, LAT_MIN, LAT_MAX = 69.05, 69.47, 41.18, 41.43

# Point near the centre: sum of three uniforms gives a bell shape, clamped to the bounds.
POINT_SQL = f"""
ST_SetSRID(ST_MakePoint(
  least(greatest({LON0} + (random()+random()+random()-1.5)*0.16, {LON_MIN}), {LON_MAX}),
  least(greatest({LAT0} + (random()+random()+random()-1.5)*0.10, {LAT_MIN}), {LAT_MAX})
), 4326)
"""


def guard(url: str) -> None:
    parsed = make_url(url)
    host = (parsed.host or "").lower()
    name = parsed.database or ""
    if host not in {"db", "localhost", "127.0.0.1"} or not any(w in name for w in ("load", "test")):
        raise SystemExit(f"refusing to seed host={host!r} db={name!r}: not a disposable load DB")


def run(conn, label: str, sql: str, **params) -> None:
    started = time.perf_counter()
    result = conn.execute(text(sql), params)
    rows = result.rowcount if result.rowcount is not None else -1
    print(f"  {label:<34} {rows:>10} rows  {time.perf_counter() - started:6.1f}s", flush=True)


def seed(conn, n: dict[str, int]) -> None:
    run(conn, "truncate", """
        TRUNCATE users, cats, posts, post_photos, comments, likes, post_views, saved_posts,
                 lost_pets, lost_pet_photos, adoption_posts, adoption_post_photos, places,
                 place_category_links, notifications, notification_preferences,
                 notification_devices, notification_push_jobs, auth_refresh_sessions,
                 lost_pet_follow_ups, adoption_follow_ups, contact_reveals,
                 publication_operations, post_history, reports, user_blocks CASCADE
    """)

    run(conn, "users", """
        INSERT INTO users (email, email_verified, name, preferred_language, is_active,
                           is_moderator, registered_at, last_active_at, phone_number,
                           accepted_terms_version, accepted_privacy_version, accepted_legal_at)
        SELECT 'load-user-' || g || '@example.com', true, 'Load User ' || g,
               (ARRAY['ru','uz','en'])[1 + (g % 3)], true, g <= 5,
               now() - (random() * interval '365 days'), now() - (random() * interval '20 days'),
               '+99890' || lpad(g::text, 7, '0'), '2026-10-01', '2026-10-01', now()
        FROM generate_series(1, :n) g
    """, n=n["users"])
    run(conn, "user index", """
        CREATE TEMP TABLE u AS
        SELECT id, row_number() OVER (ORDER BY email) AS rn FROM users;
        CREATE UNIQUE INDEX ON u (rn); ANALYZE u;
    """)

    run(conn, "notification_preferences", f"""
        INSERT INTO notification_preferences (user_id, nearby_enabled, inactivity_enabled,
                                              alert_location)
        SELECT id, true, false, {POINT_SQL}
        FROM u WHERE random() < :share
    """, share=ALERT_USERS_SHARE)
    run(conn, "notification_devices", """
        INSERT INTO notification_devices (user_id, platform, token_hash, token_encrypted)
        SELECT id, 'android', md5(id::text), 'not-a-real-token'
        FROM u WHERE random() < :share
    """, share=DEVICE_USERS_SHARE)

    run(conn, "cats", f"""
        INSERT INTO cats (name, status, created_by, first_seen_at, last_seen_at,
                          canonical_location, created_at)
        SELECT 'Cat ' || g,
               (ARRAY['healthy','healthy','healthy','injured','needs_help','unknown','feed']
                  ::cat_status[])[1 + floor(random()*7)::int],
               (SELECT id FROM u WHERE rn = 1 + (g::bigint * 7919) % :users),
               ts, ts + random() * interval '60 days', {POINT_SQL}, ts
        FROM (SELECT g, now() - power(random(), 2) * interval '365 days' AS ts
              FROM generate_series(1, :n) g) s
    """, n=n["cats"], users=n["users"])
    run(conn, "cat index", """
        CREATE TEMP TABLE c AS
        SELECT id, canonical_location AS loc, row_number() OVER (ORDER BY id) AS rn FROM cats;
        CREATE UNIQUE INDEX ON c (rn); ANALYZE c;
    """)

    # Posts: newest-heavy timeline (power on age), 15% needs-help, author and cat by hash.
    run(conn, "posts", """
        INSERT INTO posts (cat_id, user_id, photo_url, thumb_url, location,
                           description, status, created_at, updated_at, is_public, kind)
        SELECT c.id, u.id,
               'https://media.example.invalid/posts/' || g || '.jpg',
               'https://media.example.invalid/posts/' || g || '_thumb.jpg',
               c.loc,
               'Load-test observation ' || g || ' near the park, friendly and well fed.',
               'healthy', ts, ts, random() > 0.02,
               (CASE WHEN random() < 0.15 THEN 'needs_help' ELSE 'observation' END)::post_kind
        FROM (SELECT g, now() - power(random(), 2.5) * interval '365 days' AS ts,
                     1 + (g::bigint * 104729) % :cats AS cat_rn, 1 + (g::bigint * 15485863) % :users AS user_rn
              FROM generate_series(1, :n) g) s
        JOIN c ON c.rn = s.cat_rn JOIN u ON u.rn = s.user_rn
    """, n=n["posts"], cats=n["cats"], users=n["users"])
    run(conn, "post index (random popularity)", """
        CREATE TEMP TABLE p AS
        SELECT id, row_number() OVER (ORDER BY random()) AS rn FROM posts;
        CREATE UNIQUE INDEX ON p (rn); ANALYZE p;
    """)
    run(conn, "post_photos", """
        INSERT INTO post_photos (post_id, photo_url, thumb_url, position)
        SELECT id, photo_url, thumb_url, 0 FROM posts
        UNION ALL
        SELECT id, photo_url || '?2', thumb_url || '?2', 1 FROM posts WHERE random() < 0.3
    """)
    run(conn, "deleted posts (1%)", """
        UPDATE posts SET deleted_at = created_at + interval '1 day' WHERE random() < 0.01
    """)

    for label, table, extra_cols, extra_vals, count, skew in (
        ("likes", "likes", "", "", n["likes"], 3.0),
        ("post_views", "post_views", ", post_kind", ", 'post'", n["views"], 2.0),
        ("saved_posts", "saved_posts", "", "", n["saved"], 3.0),
    ):
        run(conn, label, f"""
            WITH picks AS MATERIALIZED (
                SELECT 1 + floor(:posts * power(random(), {skew}))::int AS prn,
                       1 + floor(:users * random())::int AS urn
                FROM generate_series(1, :n)
            )
            INSERT INTO {table} (post_id, user_id{extra_cols})
            SELECT p.id, u.id{extra_vals} FROM picks
            JOIN p ON p.rn = picks.prn JOIN u ON u.rn = picks.urn
            ON CONFLICT DO NOTHING
        """, n=count, posts=n["posts"], users=n["users"])

    run(conn, "comments", """
        WITH picks AS MATERIALIZED (
            SELECT g, 1 + floor(:posts * power(random(), 2.5))::int AS prn,
                   1 + floor(:users * random())::int AS urn
            FROM generate_series(1, :n) g
        )
        INSERT INTO comments (post_id, user_id, content, created_at, updated_at)
        SELECT p.id, u.id, 'Load-test comment ' || picks.g, now() - random() * interval '200 days',
               now()
        FROM picks JOIN p ON p.rn = picks.prn JOIN u ON u.rn = picks.urn
    """, n=n["comments"], posts=n["posts"], users=n["users"])

    run(conn, "lost_pets", f"""
        INSERT INTO lost_pets (user_id, owner_phone_number, last_seen_location, additional_info,
                               is_resolved, pet_name, owner_phone_publication_consent,
                               contact_consent_version, contact_consent_at, created_at,
                               updated_at)
        SELECT u.id, '+998901234567', loc, 'Load-test lost pet ' || g,
               random() > 0.25, 'Lost ' || g, true, 1, now(), ts, ts
        FROM (SELECT g, {POINT_SQL} AS loc, now() - random() * interval '180 days' AS ts,
                     1 + (g::bigint * 7907) % :users AS urn
              FROM generate_series(1, :n) g) s
        JOIN u ON u.rn = s.urn
    """, n=n["lost_pets"], users=n["users"])
    run(conn, "lost_pet_photos", """
        INSERT INTO lost_pet_photos (lost_pet_id, photo_url, thumb_url, position)
        SELECT id, 'https://media.example.invalid/lost/' || id || '.jpg',
               'https://media.example.invalid/lost/' || id || '_thumb.jpg', 0 FROM lost_pets
    """)
    run(conn, "adoption_posts", """
        INSERT INTO adoption_posts (user_id, pet_name, owner_phone_number,
                                    owner_phone_publication_consent, additional_info,
                                    is_resolved, contact_consent_version, contact_consent_at,
                                    created_at, updated_at)
        SELECT u.id, 'Adopt ' || g, '+998901234567', true, 'Load-test adoption ' || g,
               random() > 0.25, 1, now(), ts, ts
        FROM (SELECT g, now() - random() * interval '180 days' AS ts,
                     1 + (g::bigint * 6007) % :users AS urn FROM generate_series(1, :n) g) s
        JOIN u ON u.rn = s.urn
    """, n=n["adoption"], users=n["users"])
    run(conn, "adoption_post_photos", """
        INSERT INTO adoption_post_photos (adoption_post_id, photo_url, thumb_url, position)
        SELECT id, 'https://media.example.invalid/adopt/' || id || '.jpg',
               'https://media.example.invalid/adopt/' || id || '_thumb.jpg', 0
        FROM adoption_posts
    """)

    run(conn, "places", f"""
        INSERT INTO places (name, category, location, address, source,
                            source_id, is_active)
        SELECT 'Place ' || g, cat, loc, 'Tashkent', 'manual',
               'load-' || g, true
        FROM (SELECT g, (ARRAY['pet_shop','veterinary','shelter','veterinary_pharmacy']
                           ::place_category[])[1 + (g % 4)] AS cat,
                     {POINT_SQL} AS loc
              FROM generate_series(1, :n) g) s
    """, n=PLACES)
    run(conn, "place_category_links", """
        INSERT INTO place_category_links (place_id, category) SELECT id, category FROM places
    """)

    run(conn, "notifications", """
        WITH picks AS MATERIALIZED (
            SELECT g, 1 + floor(:users * random())::int AS urn,
                   1 + floor(:posts * random())::int AS prn
            FROM generate_series(1, :n) g
        )
        INSERT INTO notifications (recipient_id, kind, target_kind, target_id, event_key,
                                   created_at, read_at)
        SELECT u.id, 'comment', 'post', p.id, 'load:' || picks.g,
               now() - random() * interval '90 days',
               CASE WHEN random() < 0.8 THEN now() ELSE NULL END
        FROM picks JOIN u ON u.rn = picks.urn JOIN p ON p.rn = picks.prn
    """, n=n["notifications"], users=n["users"], posts=n["posts"])

    # Denormalised counters must match the rows, or the data-integrity checks are meaningless.
    run(conn, "posts.like_count", """
        UPDATE posts SET like_count = s.c
        FROM (SELECT post_id, count(*) c FROM likes GROUP BY post_id) s WHERE s.post_id = posts.id
    """)
    run(conn, "posts.view_count", """
        UPDATE posts SET view_count = s.c
        FROM (SELECT post_id, count(*) c FROM post_views WHERE post_kind = 'post'
              GROUP BY post_id) s WHERE s.post_id = posts.id
    """)
    run(conn, "posts.comment_count", """
        UPDATE posts SET comment_count = s.c
        FROM (SELECT post_id, count(*) c FROM comments WHERE deleted_at IS NULL
              GROUP BY post_id) s WHERE s.post_id = posts.id
    """)
    run(conn, "cats stats + cover", """
        UPDATE cats SET total_observations = s.n, total_contributors = s.uc, total_likes = s.l,
                        cover_photo_url = s.photo
        FROM (SELECT cat_id, count(*) n, count(DISTINCT user_id) uc, sum(like_count) l,
                     max(photo_url) photo
              FROM posts WHERE deleted_at IS NULL GROUP BY cat_id) s
        WHERE s.cat_id = cats.id
    """)
    run(conn, "analyze", "ANALYZE")


def encrypt_devices(conn) -> None:
    """Device tokens must be Fernet ciphertext under the stack's key, or the worker's delivery
    pass aborts on the first undecryptable row (see REPORT finding on poison push jobs)."""
    from cryptography.fernet import Fernet

    cipher = Fernet(os.environ["PUSH_TOKEN_ENCRYPTION_KEY"].encode())
    ids = [row[0] for row in conn.execute(text("SELECT id FROM notification_devices")).all()]
    for start in range(0, len(ids), 1000):
        conn.execute(
            text("UPDATE notification_devices SET token_encrypted = :t WHERE id = :i"),
            [{"i": i, "t": cipher.encrypt(f"fake-fcm-token-{i}".encode()).decode()}
             for i in ids[start:start + 1000]],
        )


def mint_tokens(conn, count: int) -> list[dict[str, str]]:
    secret = os.environ["JWT_SECRET_KEY"]
    issuer = os.getenv("JWT_ISSUER", "mushukistan-api")
    audience = os.getenv("JWT_AUDIENCE", "mushukistan-mobile")
    now = datetime.now(UTC)
    # Long-lived on purpose (7 days by default, SEED_TOKEN_TTL_HOURS): the load generator models
    # refresh separately (LT_EXPIRED_TOKENS), and run.sh refuses to start with tokens that would
    # expire during a run. Production access tokens live 60 minutes (JWT_ACCESS_TOKEN_EXP_MINUTES).
    exp = now + timedelta(hours=int(os.getenv("SEED_TOKEN_TTL_HOURS", "168")))
    rows = conn.execute(
        text("SELECT id::text, email FROM users WHERE NOT is_moderator ORDER BY email LIMIT :n"),
        {"n": count},
    ).all()
    tokens = []
    for user_id, email in rows:
        claims = {
            "sub": user_id, "role": "user", "iss": issuer, "aud": audience,
            "iat": int(now.timestamp()), "nbf": int(now.timestamp()),
            "exp": int(exp.timestamp()), "token_type": "access",
        }
        expired = dict(claims, iat=claims["iat"] - 7200, nbf=claims["nbf"] - 7200,
                       exp=int((now - timedelta(minutes=5)).timestamp()))
        refresh = secrets.token_urlsafe(48)
        conn.execute(
            text("""INSERT INTO auth_refresh_sessions (user_id, token_hash, expires_at)
                    VALUES (:u, :h, now() + interval '30 days')"""),
            {"u": user_id, "h": hashlib.sha256(refresh.encode()).hexdigest()},
        )
        tokens.append({"user_id": user_id, "email": email,
                       "token": jwt.encode(claims, secret, algorithm="HS256"),
                       "expired_token": jwt.encode(expired, secret, algorithm="HS256"),
                       "refresh_token": refresh})
    # One shared password for login-cost measurements (argon2, as the app hashes it).
    from passlib.context import CryptContext

    password_hash = CryptContext(schemes=["argon2", "bcrypt"], default="argon2").hash(
        LOGIN_PASSWORD
    )
    conn.execute(text("UPDATE users SET password_hash = :h"), {"h": password_hash})
    return tokens


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--scale", type=int, default=1)
    parser.add_argument("--tokens", type=int, default=600)
    parser.add_argument("--tokens-only", action="store_true")
    args = parser.parse_args()
    url = os.environ["DATABASE_URL"]
    guard(url)
    engine = create_engine(url)
    counts = {key: value * args.scale for key, value in BASE.items()}
    started = time.perf_counter()
    if not args.tokens_only:
        print(f"seeding scale x{args.scale}: {counts}", flush=True)
        with engine.begin() as conn:
            seed(conn, counts)
    with engine.begin() as conn:
        encrypt_devices(conn)
        conn.execute(text("TRUNCATE auth_refresh_sessions, notification_push_jobs"))
        tokens = mint_tokens(conn, args.tokens)
        sample = conn.execute(text("""
            SELECT (SELECT array_agg(id::text) FROM (SELECT id FROM posts WHERE deleted_at IS NULL
                     AND is_public ORDER BY like_count DESC LIMIT 50) a) AS hot_posts,
                   (SELECT array_agg(id::text) FROM (SELECT id FROM posts WHERE deleted_at IS NULL
                     AND is_public ORDER BY random() LIMIT 2000) b) AS posts,
                   (SELECT array_agg(id::text) FROM (SELECT id FROM lost_pets WHERE deleted_at IS
                     NULL AND NOT is_resolved ORDER BY random() LIMIT 200) c) AS lost_pets,
                   (SELECT array_agg(id::text) FROM (SELECT id FROM cats ORDER BY random()
                     LIMIT 500) d) AS cats
        """)).mappings().one()
    out = {"scale": args.scale, "users": tokens, **{k: list(v or []) for k, v in sample.items()}}
    with open("/results/tokens.json", "w", encoding="utf-8") as handle:
        json.dump(out, handle)
    print(f"done in {time.perf_counter() - started:.0f}s; {len(tokens)} tokens -> /results/tokens.json")


if __name__ == "__main__":
    main()
