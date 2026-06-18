#!/usr/bin/env bash
# Open an interactive psql shell.
# Usage: ./scripts/tools/psql.sh [database]

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

DB="${1:-postgres}"
valid_db_name "$DB" || { echo "ERROR: invalid database name '${DB}'." >&2; exit 1; }

exec docker compose exec -it postgres psql -U "$POSTGRES_USER" -d "$DB"
