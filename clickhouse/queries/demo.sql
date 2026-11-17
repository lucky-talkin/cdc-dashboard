-- Latest-state view of the CDC sink. FINAL applies ReplacingMergeTree
-- version/deletion semantics at query time.
SELECT
    id,
    name,
    email,
    created_at
FROM cdc.customers FINAL
WHERE is_deleted = 0
ORDER BY id;

-- Inspect physical versions before background merges have compacted them.
SELECT
    id,
    name,
    email,
    version,
    is_deleted
FROM cdc.customers
ORDER BY id, version;
