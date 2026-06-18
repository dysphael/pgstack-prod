#!/usr/bin/env bash
# Reset a user password.
# Usage: ./scripts/users/reset-password.sh <username>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
set_env
require_postgres

USER="${1:-}"
[[ -n "$USER" ]] || { echo "Usage: ./scripts/users/reset-password.sh <username>" >&2; exit 1; }
valid_db_name "$USER" || { echo "ERROR: invalid username." >&2; exit 1; }
role_exists "$USER" || { echo "ERROR: user '${USER}' not found." >&2; exit 1; }

[[ "$USER" != "$POSTGRES_USER" ]] || {
  echo "WARNING: resetting server admin password. Update .env too."
}

PW="$(sql_escape "$(prompt_password "$USER")")"

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres \
  -c "ALTER ROLE ${USER} WITH PASSWORD '${PW}';"

echo "OK password updated for ${USER}"
