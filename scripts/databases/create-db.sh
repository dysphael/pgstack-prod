#!/usr/bin/env bash
# Create an empty project database (schema: public).
# Users are added separately with: ./scripts/users/add-user.sh
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
create_project_database "$DB" "$POSTGRES_USER"
ensure_common_extensions "$DB"

echo ""
echo "OK — database '${DB}' ready (schema: public)"
echo ""
echo "Add a user (e.g. the Django user):"
echo "  ./scripts/users/add-user.sh ${DB} owner <username>"
