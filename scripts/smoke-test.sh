#!/usr/bin/env bash
set -euo pipefail

POSTGRES_USER="${POSTGRES_USER:-cdc}"
POSTGRES_DB="${POSTGRES_DB:-inventory}"
CLICKHOUSE_USER="${CLICKHOUSE_USER:-default}"
CLICKHOUSE_PASSWORD="${CLICKHOUSE_PASSWORD:-clickhouse}"
EMAIL="cdc-smoke-$(date +%s)@example.test"
UPDATED_EMAIL="updated-$EMAIL"

psql_source() {
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" "$@"
}

ch_query() {
  docker compose exec -T clickhouse clickhouse-client \
    --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query "$1"
}

wait_for_email() {
  local email="$1"
  local expected="$2"
  local attempt
  for attempt in $(seq 1 30); do
    local actual
    actual="$(ch_query "SELECT count() FROM cdc.customers FINAL WHERE email = '$email' AND is_deleted = 0" 2>/dev/null || true)"
    if [[ "$actual" == "$expected" ]]; then
      return 0
    fi
    sleep 2
  done
  echo "Timed out waiting for ClickHouse: email=$email expected_count=$expected" >&2
  ch_query "SELECT id, name, email, version, is_deleted FROM cdc.customers ORDER BY id, version"
  return 1
}

echo "Checking Debezium connector..."
curl --fail --silent http://localhost:8083/connectors/inventory-connector/status >/dev/null

echo "Testing INSERT..."
psql_source -c "INSERT INTO public.customers (name, email) VALUES ('CDC Smoke Test', '$EMAIL');"
wait_for_email "$EMAIL" 1

echo "Testing UPDATE..."
psql_source -c "UPDATE public.customers SET email = '$UPDATED_EMAIL' WHERE email = '$EMAIL';"
wait_for_email "$UPDATED_EMAIL" 1
wait_for_email "$EMAIL" 0

echo "Testing DELETE..."
psql_source -c "DELETE FROM public.customers WHERE email = '$UPDATED_EMAIL';"
wait_for_email "$UPDATED_EMAIL" 0

echo "CDC smoke test passed (INSERT, UPDATE, DELETE)."
