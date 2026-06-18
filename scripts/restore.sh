#!/usr/bin/env bash
# Restore a database from a .sql.gz backup file.
#
# Usage:
#   ./scripts/restore.sh backups/backup_myapp_20260101_120000.sql.gz myapp
#
# WARNING: This overwrites data in the target database.

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

FILE="${1:-}"
DB_NAME="${2:-}"

if [[ -z "$FILE" || -z "$DB_NAME" ]]; then
  echo ""
  echo "Usage: ./scripts/restore.sh <backup-file.sql.gz> <database-name>"
  echo ""
  echo "Example:"
  echo "  ./scripts/restore.sh backups/backup_myapp_20260101_120000.sql.gz myapp"
  echo ""
  echo "List available backups:"
  echo "  ./scripts/backup.sh --list"
  echo ""
  exit 1
fi

if ! valid_db_name "$DB_NAME"; then
  echo "ERROR: invalid database name '${DB_NAME}'." >&2
  exit 1
fi

if [[ ! -f "$FILE" ]]; then
  echo ""
  echo "ERROR: backup file not found: ${FILE}"
  echo ""
  echo "List available backups:"
  echo "  ./scripts/backup.sh --list"
  echo ""
  exit 1
fi

set_env
require_postgres

echo ""
echo "========================================"
echo "  PostgreSQL restore"
echo "========================================"
echo ""
echo "  Backup file:     ${FILE}"
echo "  Target database: ${DB_NAME}"
echo "  File size:       $(du -h "$FILE" | cut -f1)"
echo ""
echo "  WARNING: existing data in '${DB_NAME}' will be replaced."
echo ""

read -r -p "Type YES to continue: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
  echo ""
  echo "Restore cancelled."
  echo ""
  exit 0
fi

echo ""
echo "→ Checking if database '${DB_NAME}' exists..."

DB_EXISTS="$(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
  "SELECT 1 FROM pg_database WHERE datname = '${DB_NAME}';" || true)"

if [[ -z "$DB_EXISTS" ]]; then
  echo "  Database not found. Creating '${DB_NAME}'..."
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c \
    "CREATE DATABASE ${DB_NAME};"
fi

echo "→ Restoring backup into '${DB_NAME}'..."
gunzip -c "$FILE" | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB_NAME"

echo ""
echo "Done. Database '${DB_NAME}' was restored from:"
echo "  ${FILE}"
echo ""
