#!/usr/bin/env bash
# Add a read-only or read-write user to an existing project database.
#
# Usage: ./scripts/add-user.sh <database> <read|write> <username>

set -euo pipefail
source "$(dirname "$0")/_common.sh"
source "$(dirname "$0")/_db-users.sh"

DB="${1:-}" ACCESS="${2:-}" USER="${3:-}"
[[ -n "$DB" && -n "$ACCESS" && -n "$USER" ]] || {
  echo "Usage: ./scripts/add-user.sh <database> <read|write> <username>" >&2
  exit 1
}

valid_db_name "$DB" && valid_db_name "$USER" || { echo "ERROR: invalid name." >&2; exit 1; }
[[ "$ACCESS" == "read" || "$ACCESS" == "write" ]] || {
  echo "ERROR: access must be 'read' or 'write'." >&2
  exit 1
}

set_env
require_postgres
db_exists "$DB" || { echo "ERROR: database '${DB}' not found. Run: ./scripts/create-db.sh ${DB}" >&2; exit 1; }

OWNER="$(db_owner "$DB")"
[[ -n "$OWNER" ]] || { echo "ERROR: could not find owner for '${DB}'." >&2; exit 1; }

PW="$(sql_escape "$(prompt_password "$USER")")"

ensure_role_login "$USER" "$PW" "NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT"
isolate_to_db "$DB" "$USER"

if [[ "$ACCESS" == "read" ]]; then
  grant_read_access "$DB" "$OWNER" "$USER"
else
  grant_write_access "$DB" "$OWNER" "$USER"
fi

host="${POSTGRES_HOST:-localhost}"
echo ""
echo "OK — ${ACCESS} user '${USER}' added to '${DB}'"
echo "postgresql://${USER}:PASSWORD@${host}:5432/${DB}"
