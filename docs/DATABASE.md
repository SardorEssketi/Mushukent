DATABASE.md

Purpose
-------
This document defines the canonical database design for Mushukistan MVP. It is the source of truth for schema, types, indexes and migration notes used by the backend (FastAPI + SQLAlchemy + Alembic) and follows the Clean Architecture principle: domain entities are represented in the database but business rules remain in application/domain code.

MVP constraints and decisions
----------------------------
- MVP only (no AI, no background workers, no Redis, no RabbitMQ).
- Single relational database: PostgreSQL with PostGIS extension (hosted on a Hetzner VPS for MVP).
- Images live in Cloudflare R2; DB stores URLs only.
- Use UUID primary keys (v4) for entities to avoid accidental coupling to integer IDs and to make later migrations easier.
- SRID: EPSG:4326 (WGS 84) for all geospatial points.
- Soft-delete semantics for user-facing content to allow moderation/appeals.
- Denormalized counters (likes/comments) allowed for performance; maintain them transactionally when possible.

Extensions required
-------------------
The database must enable these extensions:
- postgis
- pgcrypto (for gen_random_uuid() if generating UUIDs in SQL)

SQL to enable extensions (run once per database):

-- Enable PostGIS and pgcrypto
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

Naming conventions
------------------
- Tables: plural, snake_case (users, cats, posts, comments, likes, reports, leaderboard_cache, places, place_category_links, lost_pets, lost_pet_photos, adoption_posts, adoption_post_photos, user_blocks).
- Columns: snake_case.
- Primary keys: id (UUID) using gen_random_uuid() as default value.
- Timestamps: created_at (TIMESTAMP WITH TIME ZONE), updated_at, deleted_at (nullable).
- Soft-delete: set deleted_at instead of hard delete for posts/comments/cats; users may be deactivated.

High-level ER summary
---------------------
- users 1 --- * posts
- cats 1 --- * posts
- posts 1 --- * comments
- posts 1 --- * post_photos
- posts * --- * likes (through likes table)
- users * --- * reports (reporter -> report target)
- places are independent map points used for pet shops, veterinary clinics and shelters
- place_category_links allows one real place to belong to multiple supported categories
- lost_pets 1 --- * lost_pet_photos
- lost_pets 1 --- * comments
- adoption_posts 1 --- * adoption_post_photos
- adoption_posts 1 --- * comments
- users 1 --- * lost_pets
- users 1 --- * adoption_posts
- users * --- * users through user_blocks

Table definitions (recommended DDL)
----------------------------------
-- Users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email TEXT UNIQUE NOT NULL,
    email_verified BOOLEAN NOT NULL DEFAULT FALSE,
    password_hash TEXT NULL, -- nullable for OAuth-only accounts
    name TEXT,
    avatar_url TEXT,
    phone_number TEXT NULL, -- Uzbekistan format: +998 XX XXX XXXX
    telegram_username TEXT NULL, -- 5-32 letters/numbers/underscores
    preferred_language TEXT NOT NULL DEFAULT 'en',
    allow_public_activity_view BOOLEAN NOT NULL DEFAULT TRUE,
    bio TEXT,
    accepted_terms_version TEXT NULL,
    accepted_privacy_version TEXT NULL,
    accepted_legal_at TIMESTAMPTZ NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    is_moderator BOOLEAN NOT NULL DEFAULT FALSE,
    registered_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_login_at TIMESTAMPTZ NULL
);
CREATE INDEX idx_users_registered_at ON users (registered_at);

-- Cats (the primary domain entity)
CREATE TYPE cat_status AS ENUM ('healthy','injured','needs_help','adopted','unknown','feed');

CREATE TABLE cats (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NULL,
    status cat_status NOT NULL DEFAULT 'unknown',
    approximate_age_smallyears SMALLINT NULL,
    created_by UUID REFERENCES users(id) ON DELETE SET NULL,
    first_seen_at TIMESTAMPTZ NULL,
    last_seen_at TIMESTAMPTZ NULL,
    cover_photo_url TEXT NULL,
    canonical_location GEOMETRY(POINT, 4326) NULL, -- optional canonical location for the cat
    total_observations INTEGER NOT NULL DEFAULT 0,
    total_contributors INTEGER NOT NULL DEFAULT 0,
    total_likes INTEGER NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    merged_into UUID NULL, -- if two cats are merged (manual moderator action)
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);
-- GIST index on canonical_location for radius searches when cat has canonical point
CREATE INDEX cats_canonical_location_gist ON cats USING GIST (canonical_location);
CREATE INDEX idx_cats_created_at ON cats (created_at);

-- Posts (observations)
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    cat_id UUID REFERENCES cats(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    photo_url TEXT NOT NULL,
    thumb_url TEXT NULL,
    -- store both geometry and lat/lon to simplify some client queries and debugging
    location GEOMETRY(POINT, 4326) NOT NULL,
    latitude DOUBLE PRECISION GENERATED ALWAYS AS (ST_Y(location::geometry)) STORED,
    longitude DOUBLE PRECISION GENERATED ALWAYS AS (ST_X(location::geometry)) STORED,
    description TEXT NULL,
    status cat_status NULL, -- observation may indicate perceived cat status at time of sighting
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    like_count INTEGER NOT NULL DEFAULT 0,
    comment_count INTEGER NOT NULL DEFAULT 0
);
-- GIST index for nearby queries
CREATE INDEX posts_location_gist ON posts USING GIST (location);
-- Common filters
CREATE INDEX idx_posts_created_at ON posts (created_at DESC);
CREATE INDEX idx_posts_user_id ON posts (user_id);
CREATE INDEX idx_posts_cat_id ON posts (cat_id);

CREATE TABLE post_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    photo_url TEXT NOT NULL,
    thumb_url TEXT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_post_photos_post_id_position ON post_photos (post_id, position);

-- Comments
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID NULL REFERENCES posts(id) ON DELETE CASCADE,
    lost_pet_id UUID NULL REFERENCES lost_pets(id) ON DELETE CASCADE,
    adoption_post_id UUID NULL REFERENCES adoption_posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    content TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX idx_comments_post_id ON comments (post_id);
CREATE INDEX idx_comments_lost_pet_id ON comments (lost_pet_id);
CREATE INDEX idx_comments_adoption_post_id ON comments (adoption_post_id);
CREATE INDEX idx_comments_user_id ON comments (user_id);

-- Likes: ensure unique (user + post) to prevent duplicate likes
CREATE TABLE likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (post_id, user_id)
);
CREATE INDEX idx_likes_post_id ON likes (post_id);
CREATE INDEX idx_likes_user_id ON likes (user_id);

CREATE TABLE user_blocks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    blocker_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    blocked_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);
CREATE INDEX idx_user_blocks_blocker_id ON user_blocks (blocker_id);
CREATE INDEX idx_user_blocks_blocked_id ON user_blocks (blocked_id);

-- Reports (content moderation)
CREATE TYPE report_target_type AS ENUM ('post','comment','user','cat','lost_pet','adoption_post');
CREATE TYPE report_status AS ENUM ('open','resolved','dismissed');

CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID REFERENCES users(id) ON DELETE SET NULL,
    target_type report_target_type NOT NULL,
    target_id UUID NOT NULL,
    reason TEXT NULL,
    metadata JSONB NULL, -- optional structured data (e.g., screenshot url, extra info)
    status report_status NOT NULL DEFAULT 'open',
    handled_by UUID REFERENCES users(id) ON DELETE SET NULL,
    handled_at TIMESTAMPTZ NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Index commonly queried fields
CREATE INDEX idx_reports_status ON reports (status);
CREATE INDEX idx_reports_target ON reports (target_type, target_id);

-- Leaderboard cache (optional, used to store precomputed leaderboard snapshots)
CREATE TYPE leaderboard_type AS ENUM ('most_active','most_popular','top_helpers');

CREATE TABLE leaderboard_cache (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    leaderboard_type leaderboard_type NOT NULL,
    period TEXT NOT NULL, -- e.g. "daily", "weekly", "monthly", or ISO range
    data JSONB NOT NULL, -- array of leaderboard entries {user_id, score, rank, meta}
    computed_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_leaderboard_type_period ON leaderboard_cache (leaderboard_type, period);

-- Places (free OSM/manual cat-support POIs)
CREATE TYPE place_category AS ENUM ('pet_shop','veterinary','shelter');
CREATE TYPE place_source AS ENUM ('osm','manual');

CREATE TABLE places (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    category place_category NOT NULL, -- primary/backward-compatible category
    location GEOMETRY(POINT, 4326) NOT NULL,
    latitude DOUBLE PRECISION GENERATED ALWAYS AS (ST_Y(location::geometry)) STORED,
    longitude DOUBLE PRECISION GENERATED ALWAYS AS (ST_X(location::geometry)) STORED,
    address TEXT NULL,
    phone TEXT NULL,
    phone_2 TEXT NULL,
    instagram TEXT NULL,
    telegram TEXT NULL,
    website TEXT NULL,
    opening_hours TEXT NULL,
    days_off TEXT NULL,
    description TEXT NULL,
    source place_source NOT NULL DEFAULT 'manual',
    source_id TEXT NULL,
    verified_at TIMESTAMPTZ NULL,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX places_location_gist ON places USING GIST (location);
CREATE INDEX idx_places_category ON places (category);
CREATE INDEX idx_places_source ON places (source, source_id);
CREATE UNIQUE INDEX uq_places_source_source_id ON places (source, source_id) WHERE source_id IS NOT NULL;

CREATE TABLE place_category_links (
    place_id UUID NOT NULL REFERENCES places(id) ON DELETE CASCADE,
    category place_category NOT NULL,
    PRIMARY KEY (place_id, category)
);
CREATE INDEX idx_place_category_links_category ON place_category_links (category);

-- Lost pet posts
CREATE TABLE lost_pets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    pet_name TEXT NOT NULL,
    owner_phone_number TEXT NOT NULL, -- copied from users.phone_number in Uzbekistan format: +998 XX XXX XXXX
    owner_telegram_username TEXT NULL, -- copied from users.telegram_username when provided
    owner_phone_publication_consent BOOLEAN NOT NULL DEFAULT FALSE,
    last_seen_location GEOMETRY(POINT, 4326) NOT NULL,
    last_seen_latitude DOUBLE PRECISION GENERATED ALWAYS AS (ST_Y(last_seen_location::geometry)) STORED,
    last_seen_longitude DOUBLE PRECISION GENERATED ALWAYS AS (ST_X(last_seen_location::geometry)) STORED,
    additional_info TEXT NULL,
    is_resolved BOOLEAN NOT NULL DEFAULT FALSE,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    comment_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX lost_pets_last_seen_location_gist ON lost_pets USING GIST (last_seen_location);
CREATE INDEX idx_lost_pets_created_at ON lost_pets (created_at DESC);
CREATE INDEX idx_lost_pets_user_id ON lost_pets (user_id);

CREATE TABLE lost_pet_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lost_pet_id UUID NOT NULL REFERENCES lost_pets(id) ON DELETE CASCADE,
    photo_url TEXT NOT NULL,
    thumb_url TEXT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_lost_pet_photos_lost_pet_id_position ON lost_pet_photos (lost_pet_id, position);

-- Adoption posts
CREATE TABLE adoption_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES users(id) ON DELETE SET NULL,
    pet_name TEXT NOT NULL,
    owner_phone_number TEXT NOT NULL, -- copied from users.phone_number in Uzbekistan format: +998 XX XXX XXXX
    owner_telegram_username TEXT NULL,
    owner_phone_publication_consent BOOLEAN NOT NULL DEFAULT FALSE,
    additional_info TEXT NULL,
    is_public BOOLEAN NOT NULL DEFAULT TRUE,
    comment_count INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    deleted_at TIMESTAMPTZ NULL
);
CREATE INDEX idx_adoption_posts_created_at ON adoption_posts (created_at DESC);
CREATE INDEX idx_adoption_posts_active_created_at ON adoption_posts (created_at DESC) WHERE deleted_at IS NULL;
CREATE INDEX idx_adoption_posts_user_id ON adoption_posts (user_id);

CREATE TABLE adoption_post_photos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    adoption_post_id UUID NOT NULL REFERENCES adoption_posts(id) ON DELETE CASCADE,
    photo_url TEXT NOT NULL,
    thumb_url TEXT NULL,
    position INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_adoption_post_photos_post_id_position ON adoption_post_photos (adoption_post_id, position);


Important constraints, indexes and rationale
------------------------------------------
- Use geometry(Point, 4326) and GIST indexes for all geospatial queries (nearby posts/cats). Use ST_DWithin for distance searches when querying in meters (note: ST_DWithin with geography is meter-accurate; if using geometry keep in mind the units).
- Posts.location is required. We also store latitude/longitude as generated columns for convenience.
- For "nearby cats" suggestion flow, query posts within a radius first (e.g., 100–200m) using posts.location, then group by cat_id.
- Unique constraint (post_id, user_id) in likes enforces single-like policy.
- Soft-delete: queries should include WHERE deleted_at IS NULL where appropriate; consider adding partial indexes to speed up active-only queries. Example:
CREATE INDEX idx_posts_active_created_at ON posts (created_at DESC) WHERE deleted_at IS NULL;

Denormalized counters
---------------------
- posts.like_count and posts.comment_count and cats.total_observations/total_likes/total_contributors are denormalized for performance on feeds and cat pages.
- Update counters transactionally at the time of insert/delete where possible. If race conditions occur under heavy load, reconcile counters periodically with a background job (post-MVP), or use database triggers.

Transaction patterns and idempotency
-----------------------------------
- Creating a post (observation): transaction should
  1) insert post row
  2) update cats.total_observations, cats.total_contributors if this user is a new contributor (a simple upsert or check)
  3) set cats.first_seen_at/last_seen_at accordingly
  This should be implemented in application service layer; avoid heavy logic in DB. For safety, use a DB transaction to make the writes atomic.

- Deleting content: set deleted_at. Moderator actions should be recorded in an audit log (can be stored in application logs or a DB table if required). Keep soft-deleted content for appeals.

Search & pagination
-------------------
- Use cursor-based pagination for feeds and map tiles (paging by created_at,id) to avoid performance issues with large offsets.
- For map queries, return GeoJSON from backend; paginate by result windows (limit/offset or bounding box + limit).

Alembic / SQLAlchemy notes
--------------------------
- Represent PostGIS geometry columns in SQLAlchemy using GeoAlchemy2's Geometry type: Geometry(geometry_type='POINT', srid=4326).
- Use UUID columns with SQLAlchemy's UUID type or as postgresql.UUID; use server_default=text('gen_random_uuid()') when generating on DB side.
- Alembic migrations should enable extensions in a migration script or require DB admin to enable them.

Example SQLAlchemy column snippets (illustrative)
- from geoalchemy2 import Geometry
- Column('location', Geometry(geometry_type='POINT', srid=4326, management=True), nullable=False)
- Column('id', postgresql.UUID(as_uuid=True), primary_key=True, server_default=text('gen_random_uuid()'))

Operational notes (MVP)
-----------------------
- Backups: schedule nightly logical backups (pg_dump) and periodic physical backups. Store backups offsite (object storage). Test restore procedures regularly.
- Migrations: use Alembic for schema changes. Follow semantic migration naming and peer-review any migration that modifies existing data.
- Local dev: recommend a docker-compose service for Postgres + PostGIS. Example image: postgis/postgis:15-3.4.

Sample docker-compose service for Postgres (dev)
-----------------------------------------------
postgres:
  image: postgis/postgis:15-3.4
  environment:
    POSTGRES_DB: mushukistan
    POSTGRES_USER: mushukistan
    POSTGRES_PASSWORD: mushukistan
  volumes:
    - ./data/postgres:/var/lib/postgresql/data
  ports:
    - "5432:5432"

Recommended queries & examples
-----------------------------
1) Nearby posts within X meters (use ST_DWithin with geography for meters accuracy):
SELECT id, ST_AsGeoJSON(location) as location_geojson, photo_url, created_at
FROM posts
WHERE deleted_at IS NULL
  AND ST_DWithin(location::geography, ST_SetSRID(ST_Point(:lon,:lat),4326)::geography, :radius_meters)
ORDER BY created_at DESC
LIMIT :limit;

2) Suggest nearby cats for a new observation (group posts by cat within radius):
SELECT c.id, c.name, count(p.id) as obs_count, ST_AsGeoJSON(c.canonical_location) as loc
FROM cats c
JOIN posts p ON p.cat_id = c.id
WHERE p.deleted_at IS NULL
  AND ST_DWithin(p.location::geography, ST_SetSRID(ST_Point(:lon,:lat),4326)::geography, :radius_meters)
GROUP BY c.id
ORDER BY obs_count DESC
LIMIT 50;

3) Feed (recent public posts):
SELECT p.id, p.description, p.photo_url, p.created_at, p.user_id, p.cat_id
FROM posts p
WHERE p.deleted_at IS NULL AND p.is_public = TRUE
ORDER BY p.created_at DESC
LIMIT :limit OFFSET :offset;
-- Prefer cursor pagination: WHERE (created_at, id) < (:last_created_at, :last_id)

4) Nearby cat-support places:
SELECT id, name, category, phone, website, opening_hours, ST_AsGeoJSON(location) as location_geojson
FROM places
WHERE is_active = TRUE
  AND category = ANY(:categories)
  AND ST_DWithin(location::geography, ST_SetSRID(ST_Point(:lon,:lat),4326)::geography, :radius_meters)
ORDER BY ST_Distance(location::geography, ST_SetSRID(ST_Point(:lon,:lat),4326)::geography)
LIMIT :limit;

Security & privacy considerations (DB-related)
----------------------------------------------
- Passwords: store only hashed password (bcrypt/argon2) in password_hash; never store plaintext. Email used for login must be unique and verified.
- Sensitive PII: limit what is stored — do not store device identifiers in plain DB without hashing. Be careful with location retention policies for privacy-sensitive content.
- Data deletion: account deletion anonymizes the account, disables login, deletes likes, hides/anonymizes owned posts/comments/lost-pet posts, removes copied lost-pet phone numbers, clears report actor links where possible, and attempts best-effort media cleanup.
- Audit logs: keep moderator actions and important security events in write-once logs or a separate audit table. Don't store secrets in DB.

Data retention policy (recommended for MVP)
------------------------------------------
- Soft-deleted posts/comments/cats/lost pets/adoption posts: keep for 90 days by default, then run `backend/scripts/cleanup_retention.py` from a scheduled production job after legal review.
- Backups: keep 30 days of daily backups and 12 monthly snapshots (adjust later as needed).

Open questions / decisions to confirm (these will affect final schema)
--------------------------------------------------------------------
1. Should we require unique human-friendly numeric IDs in addition to UUIDs for public references (e.g., cat numeric id visible in URLs)? If yes, we should add a serial 'seq' column.
2. Exact set of cat statuses: the docs list several; confirm the final enumeration and whether it changes often.
3. Do we need an explicit audit table for moderator actions now, or can app logs suffice for MVP?

Next steps (after approval)
--------------------------
- If you approve this design I will implement a first Alembic migration stub and provide a SQL file or Alembic migration script (not application code) for DB provisioning in dev/staging.
- I can also produce a short `docs/DB_QUERIES.md` with the most common queries used by the backend (nearby search, feed queries, leaderboards) optimized for the schema above.

Versioning and change control
-----------------------------
- Treat this file as authoritative. Any schema change must be accompanied by an entry in `docs/ADRS.md` explaining the reason and migration plan.

Appendix: rationale for key choices
----------------------------------
- UUID primary keys: avoid leaking cardinality and make merging data across environments easier. UUIDs are slightly larger but are standard for mobile-first apps.
- PostGIS SRID 4326: simplest and interoperable with mobile devices using lat/lon.
- Geometry + generated lat/lon columns: some clients and simple queries benefit from direct lat/lon; we keep them generated to avoid inconsistency.
- No Redis/Background workers for MVP: simplifies infra and speeds shipping. Some tasks (thumbnails, embeddings) need background processing — postponed per your direction.

Document history
----------------
- 2026-07-23: Initial draft (MVP-focused) by engineering.



