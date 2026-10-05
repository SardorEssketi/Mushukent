BEGIN TRANSACTION READ ONLY;

SELECT row_to_json(place_row)::text
FROM (
    SELECT p.id, p.name, p.category::text AS category,
           ST_Y(p.location) AS latitude, ST_X(p.location) AS longitude,
           p.address, p.phone, p.phone_2, p.website, p.opening_hours,
           p.source::text AS source, p.source_id, p.is_active,
           p.created_at, p.updated_at, p.verified_at,
           ARRAY(SELECT l.category::text
                 FROM place_category_links AS l
                 WHERE l.place_id = p.id ORDER BY l.category::text) AS categories
    FROM places AS p
    ORDER BY p.id
) AS place_row;

ROLLBACK;
