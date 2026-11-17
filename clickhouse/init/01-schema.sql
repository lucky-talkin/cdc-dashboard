CREATE DATABASE IF NOT EXISTS cdc;

-- Debezium emits one JSON envelope per row change. JSONAsString keeps the
-- original envelope intact so the materialized view can handle c/u/d/r ops.
CREATE TABLE IF NOT EXISTS cdc.customers_kafka
(
    raw String
)
ENGINE = Kafka
SETTINGS
    kafka_broker_list = 'kafka:9092',
    kafka_topic_list = 'dbserver1.public.customers',
    kafka_group_name = 'clickhouse-customers-v1',
    kafka_format = 'JSONAsString',
    kafka_num_consumers = 1,
    kafka_skip_broken_messages = 1;

CREATE TABLE IF NOT EXISTS cdc.customers
(
    id UInt64,
    name String,
    email String,
    created_at DateTime64(6, 'UTC'),
    version UInt64,
    is_deleted UInt8
)
ENGINE = ReplacingMergeTree(version, is_deleted)
ORDER BY id;

CREATE MATERIALIZED VIEW IF NOT EXISTS cdc.customers_consumer
TO cdc.customers
AS
WITH
    JSONExtractString(raw, 'op') AS operation,
    if(
        operation = 'd',
        JSONExtractRaw(raw, 'before'),
        JSONExtractRaw(raw, 'after')
    ) AS row_data,
    parseDateTime64BestEffortOrNull(
        JSONExtractString(row_data, 'created_at'),
        6,
        'UTC'
    ) AS parsed_created_at
SELECT
    JSONExtract(row_data, 'id', 'UInt64') AS id,
    JSONExtractString(row_data, 'name') AS name,
    JSONExtractString(row_data, 'email') AS email,
    ifNull(parsed_created_at, toDateTime64('1970-01-01 00:00:00', 6, 'UTC')) AS created_at,
    greatest(JSONExtract(raw, 'ts_ms', 'UInt64'), toUInt64(1)) AS version,
    toUInt8(operation = 'd') AS is_deleted
FROM cdc.customers_kafka
WHERE raw != ''
  AND JSONHas(raw, 'op')
  AND operation IN ('c', 'u', 'd', 'r');
