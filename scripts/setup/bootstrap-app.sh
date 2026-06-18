#!/usr/bin/env bash
# Bootstrap a project database + owner user after wiping data/postgres/.
# Uses PGSTACK_PASSWORD (same value as DATABASE_URL in your app .env).
#
# Usage:
#   PGSTACK_PASSWORD='app-secret' ./scripts/setup/bootstrap-app.sh <database> <username>
#
# Full reset example:
#   docker compose down
#   rm -rf ./data/postgres
#   docker compose up -d
#   ./scripts/overview/status.sh
#   PGSTACK_PASSWORD='...' ./scripts/setup/bootstrap-app.sh hyperfx hyperfx_django

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"

DB="${1:-}"
USER="${2:-}"
PW="${PGSTACK_PASSWORD:-}"

[[ -n "$DB" && -n "$USER" ]] || {
  echo "Usage: PGSTACK_PASSWORD='...' ./scripts/setup/bootstrap-app.sh <database> <username>" >&2
  exit 1
}
[[ -n "$PW" ]] || {
  echo "ERROR: set PGSTACK_PASSWORD to the exact app password (from DATABASE_URL)." >&2
  exit 1
}
valid_db_name "$DB" && valid_db_name "$USER" || { echo "ERROR: invalid name." >&2; exit 1; }

set_env
require_postgres

if db_exists "$DB"; then
  echo "ERROR: database '${DB}' already exists." >&2
  echo "Use: PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh ${USER}" >&2
  echo " or: ./scripts/users/add-user.sh ${DB} owner ${USER}" >&2
  exit 1
fi

echo "Creating database '${DB}' and owner '${USER}'..."
create_project_database "$DB" "$POSTGRES_USER"
setup_project_schema "$DB" "$POSTGRES_USER"
add_project_user "$DB" owner "$USER" "$PW"

echo ""
echo "OK — bootstrap complete"
print_connection_string "$USER" "$DB"
echo ""
echo "Use this password in your app DATABASE_URL (already set via PGSTACK_PASSWORD)."
echo "Diagnose: PGSTACK_PASSWORD='...' ./scripts/tools/diagnose-user.sh ${USER} ${DB}"
