#!/usr/bin/env bash
# List project users, access level, and database isolation.
# Usage: ./scripts/list-access.sh [database]

set -euo pipefail
source "$(dirname "$0")/_common.sh"
set_env
require_postgres

DB_FILTER="${1:-}"

echo ""
echo "Users per database:"
echo ""

if [[ -n "$DB_FILTER" ]]; then
  valid_db_name "$DB_FILTER" || { echo "ERROR: invalid database name." >&2; exit 1; }
  FILTER_SQL="AND d.datname = '${DB_FILTER}'"
else
  FILTER_SQL=""
fi

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
SELECT
  d.datname AS database,
  r.rolname AS user,
  CASE
    WHEN r.rolname = pg_catalog.pg_get_userbyid(d.datdba) THEN 'owner'
    WHEN r.rolname LIKE d.datname || '_read' THEN 'read'
    WHEN r.rolname LIKE d.datname || '_admin' THEN 'admin'
    ELSE 'extra'
  END AS role_type,
  has_database_privilege(r.rolname, d.datname, 'CONNECT') AS can_connect
FROM pg_database d
JOIN pg_roles r ON r.rolcanlogin AND NOT r.rolsuper
WHERE d.datistemplate = false
  AND d.datname NOT IN ('postgres')
  AND has_database_privilege(r.rolname, d.datname, 'CONNECT')
  ${FILTER_SQL}
ORDER BY d.datname, role_type, r.rolname;
"

echo ""
echo "Cross-database access (should be empty for project users):"
echo ""

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
SELECT r.rolname AS user, count(*) AS databases
FROM pg_roles r
JOIN pg_database d ON d.datistemplate = false AND d.datname NOT IN ('postgres')
WHERE r.rolcanlogin
  AND NOT r.rolsuper
  AND has_database_privilege(r.rolname, d.datname, 'CONNECT')
GROUP BY r.rolname
HAVING count(*) > 1
ORDER BY r.rolname;
"

echo "Server admin (all access): ${POSTGRES_USER}"
