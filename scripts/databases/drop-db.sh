#!/usr/bin/env bash
# Drop a project database (destructive). Disconnects sessions first.
# Users/roles are NOT touched — manage them with ./scripts/users/.
#
# Usage:
#   ./scripts/databases/drop-db.sh <database>
#   PGSTACK_YES=1 skips the YES confirmation

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
if [[ "${PGSTACK_YES:-}" != "1" ]]; then
  read -r -p "Type YES to continue: " OK
  [[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }
fi

terminate_db_connections "$DB"

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE ${DB};"

echo "OK dropped ${DB}"
echo ""
echo "Tip: back up first next time — ./scripts/backups/backup.sh ${DB}"
echo "Restore later with — ./scripts/backups/restore.sh data/backups/backup_${DB}_*.sql.gz"
