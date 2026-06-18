#!/usr/bin/env bash
# Drop a project database (destructive).
# Disconnects sessions, revokes access, drops users exclusive to this DB.
#
# Usage: ./scripts/databases/drop-db.sh <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
set_env
require_postgres

DB="${1:-}"
[[ -n "$DB" ]] || { echo "Usage: ./scripts/databases/drop-db.sh <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid database name." >&2; exit 1; }
[[ "$DB" != "postgres" ]] || { echo "ERROR: cannot drop system database." >&2; exit 1; }

db_exists "$DB" || { echo "ERROR: database '${DB}' not found." >&2; exit 1; }

USERS="$(users_for_database "$DB")"
EXCLUSIVE_USERS=()
if [[ -n "$USERS" ]]; then
  echo "Users with access to '${DB}':"
  while IFS= read -r user; do
    [[ -z "$user" ]] && continue
    if role_exclusive_to_db "$user" "$DB"; then
      EXCLUSIVE_USERS+=("$user")
      echo "  ${user} — will be REMOVED (only this database)"
    else
      others="$(databases_for_role "$user" | grep -vx "$DB" | paste -sd ', ' - || true)"
      echo "  ${user} — will be REVOKED (also has: ${others:-other databases})"
    fi
  done <<< "$USERS"
else
  echo "No project users with CONNECT on '${DB}'."
fi

echo ""
echo "Drop database: ${DB}"
echo "WARNING: all data will be permanently deleted."
read -r -p "Type YES to continue: " OK
[[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }

prepare_database_drop "$DB"

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
  -c "DROP DATABASE ${DB};"

for user in "${EXCLUSIVE_USERS[@]}"; do
  drop_role "$user"
done

echo "OK dropped ${DB}"
