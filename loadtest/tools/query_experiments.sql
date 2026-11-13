-- Query-shape experiments for the proposed fixes (REPORT.md). Run on the disposable load DB only:
--   docker exec -i mushukistan-load-db-1 psql -U mushukistan -d mushukistan_load < loadtest/tools/query_experiments.sql
-- Each pair is: (A) the shape the app emits today, simplified only by dropping the empty
-- user_blocks anti-joins, and (B) the proposed shape. Timings are EXPLAIN ANALYZE on one core.
\timing on
\pset pager off
SET max_parallel_workers_per_gather = 0;  -- recommendation for a single-core host; the default (2) is measured separately

\echo '=== N1 nearby page 1, current shape: geography cast, no index-usable predicate'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT * FROM (
  SELECT p.id, p.created_at, ST_Distance(p.location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography) AS d
  FROM posts p JOIN cats c ON c.id = p.cat_id
  WHERE p.deleted_at IS NULL AND p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL
    AND p.location IS NOT NULL
    AND ST_DWithin(p.location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 5000)
  UNION ALL
  SELECT l.id, l.created_at, ST_Distance(l.last_seen_location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography)
  FROM lost_pets l WHERE l.deleted_at IS NULL AND l.is_public AND NOT l.is_resolved
    AND ST_DWithin(l.last_seen_location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 5000)
) m ORDER BY d, created_at DESC, id DESC LIMIT 21;

\echo '=== N2 nearby page 1, proposed: geometry && box prefilter (uses posts_location_gist), lon expanded by 1/cos(lat)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT * FROM (
  SELECT p.id, p.created_at, ST_Distance(p.location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography) AS d
  FROM posts p JOIN cats c ON c.id = p.cat_id
  WHERE p.deleted_at IS NULL AND p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL
    AND p.location && ST_Expand(ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326), 5000 / (111320 * cos(radians(41.3111))), 5000 / 110574.0)
    AND ST_DWithin(p.location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 5000)
  UNION ALL
  SELECT l.id, l.created_at, ST_Distance(l.last_seen_location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography)
  FROM lost_pets l WHERE l.deleted_at IS NULL AND l.is_public AND NOT l.is_resolved
    AND l.last_seen_location && ST_Expand(ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326), 5000 / (111320 * cos(radians(41.3111))), 5000 / 110574.0)
    AND ST_DWithin(l.last_seen_location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 5000)
) m ORDER BY d, created_at DESC, id DESC LIMIT 21;

\echo '=== N3 nearby with a 1 km radius (the shape scales with the number of posts inside the radius)'
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
SELECT p.id FROM posts p
WHERE p.deleted_at IS NULL AND p.is_public
  AND p.location && ST_Expand(ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326), 1000 / (111320 * cos(radians(41.3111))), 1000 / 110574.0)
  AND ST_DWithin(p.location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 1000)
ORDER BY ST_Distance(p.location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography) LIMIT 21;

\echo '=== R1 recent mixed feed, current shape: union of full branches, global sort'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT * FROM (
  SELECT p.id AS item_id, p.created_at, 3 AS type_rank FROM posts p JOIN cats c ON c.id = p.cat_id
  WHERE p.deleted_at IS NULL AND p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL
  UNION ALL
  SELECT id, created_at, 2 FROM lost_pets WHERE deleted_at IS NULL AND is_public AND NOT is_resolved
  UNION ALL
  SELECT id, created_at, 1 FROM adoption_posts WHERE deleted_at IS NULL AND is_public AND NOT is_resolved
) m ORDER BY created_at DESC, type_rank DESC, item_id DESC LIMIT 21;

\echo '=== R2 recent mixed feed, proposed: each branch ordered + limited (index scan), then merge'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT * FROM (
  (SELECT p.id AS item_id, p.created_at, 3 AS type_rank FROM posts p JOIN cats c ON c.id = p.cat_id
   WHERE p.deleted_at IS NULL AND p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL
   ORDER BY p.created_at DESC, p.id DESC LIMIT 21)
  UNION ALL
  (SELECT id, created_at, 2 FROM lost_pets WHERE deleted_at IS NULL AND is_public AND NOT is_resolved
   ORDER BY created_at DESC, id DESC LIMIT 21)
  UNION ALL
  (SELECT id, created_at, 1 FROM adoption_posts WHERE deleted_at IS NULL AND is_public AND NOT is_resolved
   ORDER BY created_at DESC, id DESC LIMIT 21)
) m ORDER BY created_at DESC, type_rank DESC, item_id DESC LIMIT 21;

\echo '=== P1 popular feed core ordering, current (no matching index)'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT p.id FROM posts p JOIN cats c ON c.id = p.cat_id
WHERE p.deleted_at IS NULL AND p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL
ORDER BY p.like_count DESC, p.created_at DESC, p.id DESC LIMIT 21;

\echo '=== C1 map cats bbox (z14), current shape: LATERAL latest public post for every cat in the box'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT c.id, lp.kind FROM cats c
JOIN LATERAL (SELECT p.id, p.kind FROM posts p WHERE p.cat_id = c.id AND p.deleted_at IS NULL AND p.is_public
              AND p.created_at >= now() - interval '10 days' ORDER BY p.created_at DESC, p.id DESC LIMIT 1) lp ON true
WHERE c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL AND c.canonical_location IS NOT NULL
  AND c.canonical_location && ST_MakeEnvelope(69.23, 41.27, 69.33, 41.34, 4326)
ORDER BY coalesce(c.last_seen_at, c.created_at) DESC, c.id LIMIT 101;

\echo '=== C2 same, with a (cat_id, created_at DESC) partial index on posts (created below, dropped after)'
CREATE INDEX IF NOT EXISTS lt_tmp_posts_cat_recent ON posts (cat_id, created_at DESC, id DESC) WHERE deleted_at IS NULL AND is_public;
ANALYZE posts;
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT c.id, lp.kind FROM cats c
JOIN LATERAL (SELECT p.id, p.kind FROM posts p WHERE p.cat_id = c.id AND p.deleted_at IS NULL AND p.is_public
              AND p.created_at >= now() - interval '10 days' ORDER BY p.created_at DESC, p.id DESC LIMIT 1) lp ON true
WHERE c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL AND c.canonical_location IS NOT NULL
  AND c.canonical_location && ST_MakeEnvelope(69.23, 41.27, 69.33, 41.34, 4326)
ORDER BY coalesce(c.last_seen_at, c.created_at) DESC, c.id LIMIT 101;
DROP INDEX lt_tmp_posts_cat_recent;

\echo '=== X1 cats NEARBY east/west truncation (cats/infrastructure/repositories.py ST_Expand in degrees)'
SELECT count(*) FILTER (WHERE ST_DWithin(canonical_location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 5000)) AS within_5km,
       count(*) FILTER (WHERE ST_DWithin(canonical_location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 5000)
                          AND canonical_location && ST_Expand(ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326), 5000 / 111320.0)) AS returned_by_current_filter
FROM cats WHERE deleted_at IS NULL AND is_active AND merged_into IS NULL;

\echo '=== V1 nearby alert recipients (lost-pet create fan-out), current shape'
EXPLAIN (ANALYZE, BUFFERS, COSTS OFF, SUMMARY ON)
SELECT np.user_id FROM notification_preferences np JOIN users u ON u.id = np.user_id
WHERE np.nearby_enabled AND np.alert_location IS NOT NULL AND u.is_active
  AND ST_DWithin(np.alert_location::geography, ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography, 500);

\echo '=== K1 nearby page 1 via KNN on a temporary geography expression index (ORDER BY the distance operator only)'
CREATE INDEX IF NOT EXISTS lt_tmp_posts_geog ON posts USING gist ((location::geography)) WHERE deleted_at IS NULL AND is_public;
ANALYZE posts;
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
SELECT * FROM (
  SELECT p.id, p.location::geography <-> ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography AS d
  FROM posts p JOIN cats c ON c.id = p.cat_id
  WHERE p.deleted_at IS NULL AND p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL
  ORDER BY p.location::geography <-> ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography
  LIMIT 60) k
WHERE d <= 5000 ORDER BY d, id LIMIT 21;

\echo '=== K2 KNN deeper page (distance cursor)'
EXPLAIN (ANALYZE, COSTS OFF, SUMMARY ON)
SELECT * FROM (
  SELECT p.id, p.location::geography <-> ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography AS d
  FROM posts p JOIN cats c ON c.id = p.cat_id
  WHERE p.deleted_at IS NULL AND p.is_public AND c.deleted_at IS NULL AND c.is_active AND c.merged_into IS NULL
  ORDER BY p.location::geography <-> ST_SetSRID(ST_MakePoint(69.2797, 41.3111), 4326)::geography
  LIMIT 300) k
WHERE d <= 5000 AND d > 150 ORDER BY d, id LIMIT 21;
DROP INDEX lt_tmp_posts_geog;
