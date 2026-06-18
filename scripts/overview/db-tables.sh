#!/usr/bin/env bash
# Show table sizes in a project database.
# Usage: ./scripts/overview/db-tables.sh <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

DB="${1:-}"
[[ -n "$DB" ]] || { echo "Usage: ./scripts/overview/db-tables.sh <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid database name." >&2; exit 1; }

echo "Tables in ${DB} (schema app):"
echo ""

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d "$DB" -c "
SELECT
  schemaname AS schema,
  relname AS table,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  n_live_tup AS rows
FROM pg_stat_user_tables
WHERE schemaname = 'app'
ORDER BY pg_total_relation_size(relid) DESC;
"
