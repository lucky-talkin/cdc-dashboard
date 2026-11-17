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
                                      ReplacingMergeTree
```

## Components

- PostgreSQL 16 with logical replication enabled
- Apache Kafka in KRaft mode (no ZooKeeper)
- Debezium PostgreSQL connector
- ClickHouse with a Kafka Engine source table and materialized view
- Optional Go consumer (planned extension)

## Quick start

Requirements: Docker Engine and Docker Compose v2.

```bash
git clone https://github.com/lucky-talkin/cdc-dashboard.git
cd cdc-dashboard
cp .env.example .env
docker compose up -d
```

Register the Debezium connector:

```bash
curl -i -X POST http://localhost:8083/connectors \
  -H 'Content-Type: application/json' \
  --data @debezium/connector.json
```

Check connector status:

```bash
curl -s http://localhost:8083/connectors/inventory-connector/status | jq
```

Insert and update sample rows:

```bash
docker compose exec postgres psql -U cdc -d inventory -c \
  "INSERT INTO public.customers (name, email) VALUES ('Ada Lovelace', 'ada@example.com');"

docker compose exec postgres psql -U cdc -d inventory -c \
  "UPDATE public.customers SET email = 'ada.lovelace@example.com' WHERE name = 'Ada Lovelace';"
```

Inspect Kafka messages:

```bash
docker compose exec kafka /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 \
  --topic dbserver1.public.customers --from-beginning
```

Query ClickHouse:

```bash
docker compose exec clickhouse clickhouse-client \
  --query "SELECT * FROM cdc.customers FINAL ORDER BY id"
```

## Local endpoints

| Service | Endpoint | Credentials |
|---|---|---|
| PostgreSQL | localhost:5432 | cdc / cdc |
| Kafka | localhost:9092 | PLAINTEXT |
| Kafka Connect REST | http://localhost:8083 | — |
| ClickHouse HTTP | http://localhost:8123 | default user, no password |
| ClickHouse native | localhost:9000 | default user, no password |

## Important notes

- This is a local development/demo stack, not a production deployment.
- The ClickHouse Kafka Engine is a streaming ingestion mechanism. ReplacingMergeTree deduplicates versions during merges; use `FINAL` when you need query-time replacement semantics.
- Debezium emits delete events and tombstones. The initial ClickHouse projection is intentionally a learning baseline; validate delete/tombstone behavior before relying on it for correctness-sensitive workloads.
- Pin and review image versions before using this stack outside local development.

## Project roadmap

- [x] Docker Compose foundation
- [x] PostgreSQL logical replication and sample schema
- [x] Debezium connector configuration
- [x] Kafka-to-ClickHouse ingestion baseline
- [ ] Go consumer with graceful shutdown, retries, and structured logging
- [ ] Automated end-to-end INSERT / UPDATE / DELETE tests
- [ ] Metrics, dashboards, and failure-recovery documentation
- [ ] Idempotency, schema evolution, and production hardening

## Troubleshooting

- Connector fails to start: check `docker compose logs connect` and confirm PostgreSQL is healthy.
- No Kafka topic: inspect connector status and `docker compose logs connect`.
- No ClickHouse rows: check `docker compose logs clickhouse`, then inspect `SELECT * FROM cdc.customers_kafka LIMIT 10`.
- Reset the local environment (destroys local volumes): `docker compose down -v`.

## License

MIT (see [LICENSE](LICENSE)).
