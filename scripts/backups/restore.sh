#!/usr/bin/env bash
# Restore a backup into a database (drops and recreates it, loads 100%).
# Portable: works with any backup_*.sql.gz, even copied from another server.
#
# Usage:
#   ./scripts/backups/restore.sh <file.sql.gz> [database]
#   PGSTACK_YES=1 skips the YES confirmation
#
# If [database] is omitted, it is inferred from the filename
# (backup_<db>_YYYYMMDD_HHMMSS.sql.gz).
#
# Users are NOT restored. After loading, create the app user with:
#   ./scripts/users/add-user.sh <database> owner <username>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/backups.sh"
source "${ROOT}/lib/db-users.sh"

FILE="${1:-}" DB="${2:-}"
[[ -n "$FILE" ]] || { echo "Usage: ./scripts/backups/restore.sh <file.sql.gz> [database]" >&2; exit 1; }
[[ -f "$FILE" ]] || { echo "ERROR: file not found: ${FILE}" >&2; exit 1; }

set_env
require_postgres

if [[ -z "$DB" ]]; then
  DB="$(backup_db_from_filename "$FILE")"
  [[ "$DB" != "?" && -n "$DB" ]] || {
    echo "ERROR: could not infer database name from filename." >&2
    echo "Pass it explicitly: ./scripts/backups/restore.sh ${FILE} <database>" >&2
    exit 1
  }
fi
valid_db_name "$DB" || { echo "ERROR: invalid database name '${DB}'." >&2; exit 1; }
[[ "$DB" != "postgres" ]] || { echo "ERROR: cannot restore over system database." >&2; exit 1; }

echo "Restore ${FILE} → ${DB}"
echo "WARNING: database '${DB}' will be DROPPED and recreated from the backup."
if [[ "${PGSTACK_YES:-}" != "1" ]]; then
  read -r -p "Type YES to continue: " OK
  [[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }
fi

if db_exists "$DB"; then
  echo "Dropping existing database '${DB}'..."
  terminate_db_connections "$DB"
  docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
    -c "DROP DATABASE ${DB};"
fi

echo "Creating database '${DB}'..."
docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
  -c "CREATE DATABASE ${DB};"

echo "Loading data..."
gunzip -c "$FILE" | docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$DB"

echo ""
echo "OK — restored '${DB}' (data loaded 100%)"
echo ""
echo "Create the app user now (the Django user):"
echo "  ./scripts/users/add-user.sh ${DB} owner <username>"
echo "Then point your app DATABASE_URL to that user."
