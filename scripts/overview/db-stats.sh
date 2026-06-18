#!/usr/bin/env bash
# Database overview: version, sizes, connections, cache hit ratio.
# Usage: ./scripts/overview/db-stats.sh [database]

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

DB_FILTER="${1:-}"

echo "=== PostgreSQL overview ==="
echo ""

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
SELECT version() AS postgres_version;
"

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
SELECT
  pg_postmaster_start_time() AS started_at,
  now() - pg_postmaster_start_time() AS uptime,
  (SELECT count(*) FROM pg_stat_activity) AS total_connections,
  (SELECT count(*) FROM pg_stat_activity WHERE state = 'active') AS active_queries,
  (SELECT setting FROM pg_settings WHERE name = 'max_connections') AS max_connections;
"

echo ""
echo "=== Database sizes ==="
echo ""

if [[ -n "$DB_FILTER" ]]; then
  valid_db_name "$DB_FILTER" || { echo "ERROR: invalid database name." >&2; exit 1; }
  SIZE_FILTER="AND d.datname = '${DB_FILTER}'"
  CACHE_FILTER="AND datname = '${DB_FILTER}'"
else
  SIZE_FILTER="AND d.datname NOT IN ('postgres')"
  CACHE_FILTER="AND datname NOT IN ('template0', 'template1')"
fi

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
SELECT
  d.datname AS database,
  pg_catalog.pg_get_userbyid(d.datdba) AS owner,
  pg_size_pretty(pg_database_size(d.datname)) AS size,
  s.numbackends AS connections
FROM pg_database d
LEFT JOIN pg_stat_database s ON s.datid = d.oid
WHERE d.datistemplate = false
  ${SIZE_FILTER}
ORDER BY pg_database_size(d.datname) DESC;
"

echo ""
echo "=== Cache hit ratio (higher is better) ==="
echo ""

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
SELECT
  datname AS database,
  CASE WHEN blks_hit + blks_read = 0 THEN 'n/a'
       ELSE round(100.0 * blks_hit / (blks_hit + blks_read), 2)::text || '%'
  END AS cache_hit_ratio
FROM pg_stat_database
WHERE datname IS NOT NULL
  ${CACHE_FILTER}
ORDER BY datname;
"
