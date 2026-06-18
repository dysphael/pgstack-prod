#!/usr/bin/env bash
# List project databases.
# Usage: ./scripts/databases/list-dbs.sh

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

echo "Project databases:"
echo ""
docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c \
  "SELECT datname AS database, pg_catalog.pg_get_userbyid(datdba) AS owner
   FROM pg_database
   WHERE datistemplate = false AND datname <> 'postgres'
   ORDER BY datname;"
