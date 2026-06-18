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

PW="$(prompt_password "$USER")"
set_role_password "$USER" "$PW"

VERIFY_DB="$(databases_for_role "$USER" | head -n1)"
if [[ -n "$VERIFY_DB" ]]; then
  if verify_role_login "$USER" "$PW" "$VERIFY_DB"; then
    echo "OK password updated for ${USER} (login verified on ${VERIFY_DB})"
  else
    echo "ERROR: password updated but login verification failed on '${VERIFY_DB}'." >&2
    exit 1
  fi
else
  echo "OK password updated for ${USER}"
fi
