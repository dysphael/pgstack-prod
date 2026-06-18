#!/usr/bin/env bash
# Drop a user/role (destructive).
# Usage: ./scripts/users/drop-user.sh <username>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
set_env
require_postgres

USER="${1:-}"
[[ -n "$USER" ]] || { echo "Usage: ./scripts/users/drop-user.sh <username>" >&2; exit 1; }
valid_db_name "$USER" || { echo "ERROR: invalid username." >&2; exit 1; }
role_exists "$USER" || { echo "ERROR: user '${USER}' not found." >&2; exit 1; }
[[ "$USER" != "$POSTGRES_USER" ]] || { echo "ERROR: cannot drop server admin." >&2; exit 1; }

OWNER_OF="$(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
  "SELECT datname FROM pg_database WHERE pg_get_userbyid(datdba) = '${USER}'")"

if [[ -n "$OWNER_OF" ]]; then
  echo "ERROR: '${USER}' owns database(s): ${OWNER_OF//$'\n'/, }"
  echo "Drop the database first: ./scripts/databases/drop-db.sh <database>"
  exit 1
fi

DB_ACCESS="$(databases_for_role "$USER")"
if [[ -n "$DB_ACCESS" ]]; then
  echo "Databases with access: ${DB_ACCESS//$'\n'/, }"
else
  echo "No database CONNECT privileges found (will still clean grants if any)."
fi

echo ""
echo "Drop user: ${USER}"
read -r -p "Type YES to continue: " OK
[[ "$OK" == "YES" ]] || { echo "Cancelled."; exit 0; }

teardown_user_grants "$USER"

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
  -c "DROP ROLE ${USER};"

echo "OK dropped ${USER}"
