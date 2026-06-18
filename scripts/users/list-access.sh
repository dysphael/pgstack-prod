#!/usr/bin/env bash
# List project users, access level, and database isolation.
# Usage: ./scripts/users/list-access.sh [database]

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
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

USERS_SQL="
SELECT
  d.datname AS database,
  r.rolname AS user,
  CASE
    WHEN r.rolname = pg_catalog.pg_get_userbyid(d.datdba) THEN 'owner'
    WHEN r.rolcreaterole THEN 'admin'
    ELSE 'user'
  END AS role_type,
  has_database_privilege(r.rolname, d.datname, 'CONNECT')::text AS can_connect
FROM pg_database d
JOIN pg_roles r ON r.rolcanlogin AND NOT r.rolsuper
WHERE d.datistemplate = false
  AND d.datname NOT IN ('postgres')
  AND has_database_privilege(r.rolname, d.datname, 'CONNECT')
  ${FILTER_SQL}
ORDER BY d.datname, role_type, r.rolname;
"

CROSS_SQL="
SELECT r.rolname AS user, count(*)::text AS databases
FROM pg_roles r
JOIN pg_database d ON d.datistemplate = false AND d.datname NOT IN ('postgres')
WHERE r.rolcanlogin
  AND NOT r.rolsuper
  AND has_database_privilege(r.rolname, d.datname, 'CONNECT')
GROUP BY r.rolname
HAVING count(*) > 1
ORDER BY r.rolname;
"

if [[ -n "${PGSTACK_UI:-}" ]]; then
  pg_print_table postgres "$USERS_SQL" 10 14 8 6
  echo ""
  echo "Cross-database access (should be empty for project users):"
  echo ""
  pg_print_table postgres "$CROSS_SQL" 14 6
else
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "$USERS_SQL"
  echo ""
  echo "Cross-database access (should be empty for project users):"
  echo ""
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "$CROSS_SQL"
fi

echo "Server admin (all access): ${POSTGRES_USER}"
