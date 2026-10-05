BEGIN TRANSACTION READ ONLY;

SELECT row_to_json(reference_row)::text
FROM (
    SELECT c.conname AS constraint_name,
           c.conrelid::regclass::text AS referencing_table,
           ARRAY(SELECT a.attname FROM unnest(c.conkey) WITH ORDINALITY AS k(attnum, ord)
                 JOIN pg_attribute AS a ON a.attrelid = c.conrelid AND a.attnum = k.attnum
                 ORDER BY k.ord) AS referencing_columns,
           c.confrelid::regclass::text AS referenced_table,
           c.confdeltype::text AS on_delete_code
    FROM pg_constraint AS c
    WHERE c.contype = 'f' AND c.confrelid = 'places'::regclass
    ORDER BY c.conrelid::regclass::text, c.conname
) AS reference_row;

SELECT row_to_json(column_row)::text
FROM (
    SELECT table_name, column_name, data_type
    FROM information_schema.columns
    WHERE table_schema = 'public' AND column_name ILIKE '%place%'
    ORDER BY table_name, column_name
) AS column_row;

ROLLBACK;
