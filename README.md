# PostgreSQL → Debezium → Kafka → ClickHouse

A local, Docker Compose-based Change Data Capture (CDC) lab. PostgreSQL is the source of truth; Debezium reads PostgreSQL's write-ahead log (WAL), publishes row changes to Kafka, and ClickHouse consumes the CDC stream for analytical queries.

## Architecture

```text
Application / SQL
      |
      v
 PostgreSQL 16 --WAL/logical replication--> Debezium Connect
                                                |
                                                v
                                         Kafka (KRaft)
                                                |
                                                v
                                      ClickHouse Kafka Engine
                                                |
                                                v
                                      Materialized View
                                                |
                                                v
                                      ReplacingMergeTree
```

## Components

- PostgreSQL 16 with logical replication enabled
- Apache Kafka in KRaft mode (no ZooKeeper)
- Debezium PostgreSQL connector
- ClickHouse Kafka Engine source table, materialized view, and ReplacingMergeTree target
- Optional Go consumer (planned extension)

## Quick start

Requirements: Docker Engine and Docker Compose v2.

```bash
git clone https://github.com/lucky-talkin/cdc-dashboard.git
cd cdc-dashboard
cp .env.example .env
docker compose up -d
```

Wait for the services to become healthy, then register the Debezium connector:

```bash
bash scripts/register-connector.sh
```

The equivalent REST request is:

```bash
curl -i -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  --data @debezium/connector.json
```

Check connector status:

```bash
curl -s http://localhost:8083/connectors/inventory-connector/status | jq
```

## Generate CDC events

Insert, update, and delete a customer:

```bash
docker compose exec postgres psql -U cdc -d inventory -c \
  "INSERT INTO public.customers (name, email) VALUES ('Ada Lovelace', 'ada@example.com');"

docker compose exec postgres psql -U cdc -d inventory -c \
  "UPDATE public.customers SET email = 'ada.lovelace@example.com' WHERE name = 'Ada Lovelace';"

docker compose exec postgres psql -U cdc -d inventory -c \
  "DELETE FROM public.customers WHERE name = 'Ada Lovelace';"
```

Inspect Kafka messages:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic dbserver1.public.customers --from-beginning
```

Query the latest customer state in ClickHouse:

```bash
docker compose exec clickhouse clickhouse-client \
  --user default --password clickhouse \
  --query "SELECT id, name, email FROM cdc.customers FINAL WHERE is_deleted = 0 ORDER BY id"
```

Run the end-to-end smoke test after registering the connector:

```bash
bash scripts/smoke-test.sh
```

The smoke test sends INSERT, UPDATE, and DELETE statements to PostgreSQL and polls ClickHouse for the expected state. It requires Docker Compose, curl, and a running stack.

## Local endpoints

| Service | Endpoint | Credentials |
|---|---|---|
| PostgreSQL | localhost:5432 | cdc / cdc |
| Kafka (host access) | localhost:29092 | PLAINTEXT |
| Kafka (Compose network) | kafka:9092 | PLAINTEXT |
| Kafka Connect REST | http://localhost:8083 | — |
| ClickHouse HTTP | http://localhost:8123 | default / clickhouse |
| ClickHouse native | localhost:9000 | default / clickhouse |

Credentials in `.env.example` are for local development only. Change them before exposing services beyond your machine.

## Data model and CDC semantics

- PostgreSQL source table: `public.customers`
- Kafka topic: `dbserver1.public.customers`
- ClickHouse raw Kafka table: `cdc.customers_kafka`
- ClickHouse materialized view: `cdc.customers_consumer`
- ClickHouse current-state target: `cdc.customers`

The materialized view projects Debezium create, update, delete, and snapshot-read events into the target table. Delete events are represented as rows with `is_deleted = 1`; normal reads should use `FINAL` and filter `is_deleted = 0`.

This is an educational baseline. Event timestamps are used as the ReplacingMergeTree version in this first iteration, so multiple source changes within the same millisecond can require a stronger source-ordering key before correctness-sensitive use. Schema changes, replay strategy, and Kafka offset recovery also need explicit production treatment.

## Important notes

- This is a local development/demo stack, not a production deployment.
- ReplacingMergeTree performs replacement during merges; use `FINAL` when query-time replacement semantics are required.
- Debezium's PostgreSQL connector uses the `pgoutput` logical decoding plugin and the `dbz_publication` publication created by the PostgreSQL init script.
- The PostgreSQL init scripts run only when the data volume is first created. To recreate the database from scratch, use `docker compose down -v` (this destroys local data).
- Pin and review image versions before using this stack outside local development.

## Project roadmap

- [x] Docker Compose foundation
- [x] PostgreSQL logical replication and sample schema
- [x] Debezium connector configuration
- [x] Kafka-to-ClickHouse ingestion baseline
- [ ] Go consumer with graceful shutdown, retries, and structured logging
- [ ] Run and harden automated end-to-end INSERT / UPDATE / DELETE tests
- [ ] Metrics, dashboards, and failure-recovery documentation
- [ ] Idempotency, schema evolution, and production hardening

## Troubleshooting

- Connector fails to start: check `docker compose logs connect` and confirm PostgreSQL is healthy.
- No Kafka topic: inspect `curl http://localhost:8083/connectors/inventory-connector/status` and `docker compose logs connect`.
- No ClickHouse rows: inspect `SELECT * FROM cdc.customers_kafka LIMIT 10` and `docker compose logs clickhouse`.
- Reset the local environment (destroys local volumes): `docker compose down -v`.

## License

MIT (see [LICENSE](LICENSE)).
