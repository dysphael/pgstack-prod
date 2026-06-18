#!/usr/bin/env bash
# Show slowest queries from pg_stat_statements.
# Usage: ./scripts/overview/slow-queries.sh [limit]

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

LIMIT="${1:-15}"
[[ "$LIMIT" =~ ^[0-9]+$ ]] || { echo "Usage: ./scripts/overview/slow-queries.sh [limit]" >&2; exit 1; }

echo "Top ${LIMIT} slowest queries (by mean time):"
echo ""

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
SELECT
  left(query, 100) AS query,
  calls,
  round(mean_exec_time::numeric, 2) AS mean_ms,
  round(total_exec_time::numeric, 2) AS total_ms,
  rows
FROM pg_stat_statements
WHERE query NOT LIKE '%pg_stat_statements%'
ORDER BY mean_exec_time DESC
LIMIT ${LIMIT};
" 2>/dev/null || {
  echo "pg_stat_statements not available. Restart postgres after first install."
  exit 1
}
