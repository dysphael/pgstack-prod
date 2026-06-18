#!/usr/bin/env bash
# Show active connections and running queries.
# Usage: ./scripts/overview/connections.sh [database]

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

DB_FILTER="${1:-}"

if [[ -n "$DB_FILTER" ]]; then
  valid_db_name "$DB_FILTER" || { echo "ERROR: invalid database name." >&2; exit 1; }
  FILTER_SQL="AND a.datname = '${DB_FILTER}'"
else
  FILTER_SQL=""
fi

echo "Active connections:"
echo ""

CONN_SQL="
SELECT
  a.pid::text AS pid,
  a.usename AS user,
  a.datname AS database,
  coalesce(a.client_addr::text, '') AS client,
  a.state,
  coalesce((now() - a.query_start)::text, '') AS duration,
  left(replace(a.query, E'\n', ' '), 40) AS query
FROM pg_stat_activity a
WHERE a.pid <> pg_backend_pid()
  AND a.datname IS NOT NULL
  ${FILTER_SQL}
ORDER BY a.query_start NULLS LAST;
"

if [[ -n "${PGSTACK_UI:-}" ]]; then
  pg_print_table postgres "$CONN_SQL" 6 10 10 14 8 10 40
else
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
    SELECT
      a.pid,
      a.usename AS user,
      a.datname AS database,
      a.client_addr,
      a.state,
      now() - a.query_start AS query_duration,
      left(a.query, 80) AS query
    FROM pg_stat_activity a
    WHERE a.pid <> pg_backend_pid()
      AND a.datname IS NOT NULL
      ${FILTER_SQL}
    ORDER BY a.query_start NULLS LAST;
  "
fi
