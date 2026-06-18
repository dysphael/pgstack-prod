#!/usr/bin/env bash
# Show connection strings for a project database.
# Usage: ./scripts/databases/conn-info.sh <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

DB="${1:-}"
[[ -n "$DB" ]] || { echo "Usage: ./scripts/databases/conn-info.sh <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid database name." >&2; exit 1; }

HOST="${POSTGRES_HOST:-localhost}"

echo "Connection strings for '${DB}' (schema: public):"
echo ""

CONN_SQL="
SELECT
  r.rolname AS user,
  CASE
    WHEN r.rolname = pg_catalog.pg_get_userbyid(d.datdba) THEN 'owner'
    WHEN r.rolcreaterole THEN 'admin'
    ELSE 'user'
  END AS access
FROM pg_database d
JOIN pg_roles r ON r.rolcanlogin AND NOT r.rolsuper
WHERE d.datname = '${DB}'
  AND r.rolname <> '${POSTGRES_USER}'
  AND has_database_privilege(r.rolname, d.datname, 'CONNECT')
ORDER BY access, r.rolname;
"

if [[ -n "${PGSTACK_UI:-}" ]]; then
  pg_print_table postgres "$CONN_SQL" 16 10
else
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "$CONN_SQL"
fi

echo ""
echo "Format: postgresql://USER:PASSWORD@${HOST}:5432/${DB}"
