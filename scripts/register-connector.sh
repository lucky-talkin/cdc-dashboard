#!/usr/bin/env bash
set -euo pipefail

CONNECT_URL="${CONNECT_URL:-http://localhost:8083}"
CONNECTOR_FILE="${CONNECTOR_FILE:-debezium/connector.json}"

if [[ ! -f "$CONNECTOR_FILE" ]]; then
  echo "Connector config not found: $CONNECTOR_FILE" >&2
  exit 1
fi

curl --fail --show-error --silent \
  -X POST "$CONNECT_URL/connectors" \
  -H 'Content-Type: application/json' \
  --data "@$CONNECTOR_FILE"
printf '\n'

echo "Connector status:"
curl --fail --show-error --silent "$CONNECT_URL/connectors/inventory-connector/status"
printf '\n'
