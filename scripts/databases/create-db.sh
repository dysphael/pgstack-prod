#!/usr/bin/env bash
# Create an isolated project database. Users are optional.
#
# Usage: ./scripts/databases/create-db.sh <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"

DB="${1:-}"
[[ -n "$DB" ]] || { echo "Usage: ./scripts/databases/create-db.sh <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid database name." >&2; exit 1; }

set_env
require_postgres
db_exists "$DB" && { echo "ERROR: database '${DB}' already exists." >&2; exit 1; }

echo "Creating database '${DB}'..."
echo "Users are optional — you will be asked if you want to add any."

create_project_database "$DB" "$POSTGRES_USER"
setup_project_schema "$DB" "$POSTGRES_USER"

interactive_add_users "$DB"
print_db_summary "$DB"
