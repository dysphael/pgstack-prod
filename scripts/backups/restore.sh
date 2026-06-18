#!/usr/bin/env bash
# Usage: ./scripts/backups/restore.sh <backup.sql.gz> <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"

FILE="${1:-}" DB="${2:-}"
[[ -n "$FILE" && -n "$DB" ]] || { echo "Usage: ./scripts/backups/restore.sh <file.sql.gz> <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid name '${DB}'." >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "ERROR: file not found: ${FILE}" >&2; exit 1; }

set_env
require_postgres

echo "Restore ${FILE} → ${DB}"
echo "WARNING: this replaces existing data."
read -r -p "Type YES to continue: " OK
[[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -tc \
  "SELECT 1 FROM pg_database WHERE datname='${DB}'" | grep -q 1 || {
  echo "WARNING: database '${DB}' does not exist."
  echo "For isolated users, run first: ./scripts/databases/create-db.sh ${DB}"
  read -r -p "Create empty database without users? (yes/no): " CREATE_OK
  [[ "$CREATE_OK" == "yes" ]] || { echo "Cancelled."; exit 0; }
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE ${DB};"
}

gunzip -c "$FILE" | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB"
echo "OK restored ${DB}"
