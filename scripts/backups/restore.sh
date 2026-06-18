#!/usr/bin/env bash
# Usage: ./scripts/backups/restore.sh <backup.sql.gz> <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"

FILE="${1:-}" DB="${2:-}"
[[ -n "$FILE" && -n "$DB" ]] || { echo "Usage: ./scripts/backups/restore.sh <file.sql.gz> <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid name '${DB}'." >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "ERROR: file not found: ${FILE}" >&2; exit 1; }

set_env
require_postgres

SNAPSHOT_DB_OWNER=""
SNAPSHOT_USERS=()
if db_exists "$DB"; then
  SNAPSHOT_DB_OWNER="$(db_owner "$DB")"
  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    SNAPSHOT_USERS+=("$user")
  done < <(users_for_database "$DB")
fi

echo "Restore ${FILE} → ${DB}"
echo "WARNING: this replaces existing data."
if [[ ${#SNAPSHOT_USERS[@]} -gt 0 ]]; then
  echo "Users to re-grant after restore: ${SNAPSHOT_USERS[*]}"
fi
read -r -p "Type YES to continue: " OK
[[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }

if db_exists "$DB"; then
  echo "Clearing schema 'app' before restore..."
  wipe_database_for_restore "$DB"
else
  echo "WARNING: database '${DB}' does not exist."
  echo "For isolated users, run first: ./scripts/databases/create-db.sh ${DB}"
  read -r -p "Create empty database without users? (yes/no): " CREATE_OK
  [[ "$CREATE_OK" == "yes" ]] || { echo "Cancelled."; exit 0; }
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "CREATE DATABASE ${DB};"
fi

gunzip -c "$FILE" | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB"

if [[ ${#SNAPSHOT_USERS[@]} -gt 0 ]]; then
  echo "Re-applying user grants..."
  regrant_database_users_after_restore "$DB" "$SNAPSHOT_DB_OWNER" "${SNAPSHOT_USERS[@]}"
fi

echo "OK restored ${DB}"
