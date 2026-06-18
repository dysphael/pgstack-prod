#!/usr/bin/env bash
# Add a user to a project database.
#
# Usage: ./scripts/users/add-user.sh <database> <owner|read|write|admin> <username>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"

DB="${1:-}" ACCESS="${2:-}" USER="${3:-}"
[[ -n "$DB" && -n "$ACCESS" && -n "$USER" ]] || {
  echo "Usage: ./scripts/users/add-user.sh <database> <owner|read|write|admin> <username>" >&2
  exit 1
}

valid_db_name "$DB" && valid_db_name "$USER" || { echo "ERROR: invalid name." >&2; exit 1; }
valid_access_type "$ACCESS" || {
  echo "ERROR: access must be owner, read, write, or admin." >&2
  exit 1
}

set_env
require_postgres
db_exists "$DB" || { echo "ERROR: database '${DB}' not found." >&2; exit 1; }

PW="$(prompt_password "$USER")"
add_project_user "$DB" "$ACCESS" "$USER" "$PW"

echo ""
echo "OK — ${ACCESS} user '${USER}' added to '${DB}'"
print_connection_string "$USER" "$DB"
