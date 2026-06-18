#!/usr/bin/env bash
# Create an isolated project database with owner, read-only, and DB-admin users.
#
# Usage: ./scripts/databases/create-db.sh <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"

DB="${1:-}"
[[ -n "$DB" ]] || { echo "Usage: ./scripts/databases/create-db.sh <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid database name." >&2; exit 1; }

OWNER="${DB}_owner"
READ_USER="${DB}_read"
ADMIN_USER="${DB}_admin"

set_env
require_postgres

echo "Creating database '${DB}' with 3 users:"
echo "  ${OWNER}      — read, write, delete"
echo "  ${READ_USER}  — read only"
echo "  ${ADMIN_USER} — manage users for this database"
echo ""

OWNER_PW="$(sql_escape "$(prompt_password "$OWNER")")"
READ_PW="$(sql_escape "$(prompt_password "$READ_USER")")"
ADMIN_PW="$(sql_escape "$(prompt_password "$ADMIN_USER")")"

echo "Provisioning..."

ensure_role_login "$OWNER" "$OWNER_PW" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
create_project_database "$DB" "$OWNER"
isolate_to_db "$DB" "$OWNER"
setup_project_schema "$DB" "$OWNER"

ensure_role_login "$READ_USER" "$READ_PW" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
isolate_to_db "$DB" "$READ_USER"
grant_read_access "$DB" "$OWNER" "$READ_USER"

ensure_role_login "$ADMIN_USER" "$ADMIN_PW" "NOSUPERUSER NOCREATEDB CREATEROLE NOINHERIT"
isolate_to_db "$DB" "$ADMIN_USER"
grant_db_admin "$DB" "$ADMIN_USER"

print_user_summary "$DB" "$OWNER" "$READ_USER" "$ADMIN_USER"
