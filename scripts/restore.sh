#!/usr/bin/env bash
# Usage: ./scripts/restore.sh <backup.sql.gz> <database>

set -euo pipefail
source "$(dirname "$0")/_common.sh"

FILE="${1:-}" DB="${2:-}"
[[ -n "$FILE" && -n "$DB" ]] || { echo "Usage: ./scripts/restore.sh <file.sql.gz> <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid name '${DB}'." >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "ERROR: file not found: ${FILE}" >&2; exit 1; }

set_env
require_postgres

echo "Restore ${FILE} → ${DB}"
echo "WARNING: this replaces existing data."
read -r -p "Type YES to continue: " OK
[[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname='${DB}'" | grep -q 1 || \
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE ${DB};"

gunzip -c "$FILE" | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB"
echo "OK restored ${DB}"
