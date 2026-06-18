#!/usr/bin/env bash
# Drop a project database (destructive).
# Usage: ./scripts/databases/drop-db.sh <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
set_env
require_postgres

DB="${1:-}"
[[ -n "$DB" ]] || { echo "Usage: ./scripts/databases/drop-db.sh <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid database name." >&2; exit 1; }
[[ "$DB" != "postgres" ]] || { echo "ERROR: cannot drop system database." >&2; exit 1; }

db_exists "$DB" || { echo "ERROR: database '${DB}' not found." >&2; exit 1; }

echo "Drop database: ${DB}"
echo "WARNING: all data will be permanently deleted."
read -r -p "Type YES to continue: " OK
[[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
SELECT pg_terminate_backend(pid)
FROM pg_stat_activity
WHERE datname = '${DB}' AND pid <> pg_backend_pid();
DROP DATABASE ${DB};
SQL

echo "OK dropped ${DB}"
