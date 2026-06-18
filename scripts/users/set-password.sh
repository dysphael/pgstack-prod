#!/usr/bin/env bash
# Set a user password non-interactively (exact copy from .env / secret manager).
#
# Usage:
#   PGSTACK_PASSWORD='secret' ./scripts/users/set-password.sh <username>
#   ./scripts/users/set-password.sh <username> 'secret'

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
set_env
require_postgres

USER="${1:-}"
PW="${2:-${PGSTACK_PASSWORD:-}}"
[[ -n "$USER" ]] || {
  echo "Usage: PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh <username>" >&2
  echo "   or: ./scripts/users/set-password.sh <username> 'password'" >&2
  exit 1
}
[[ -n "$PW" ]] || { echo "ERROR: password required (arg or PGSTACK_PASSWORD)." >&2; exit 1; }
valid_db_name "$USER" || { echo "ERROR: invalid username." >&2; exit 1; }
role_exists "$USER" || { echo "ERROR: user '${USER}' not found." >&2; exit 1; }

set_role_password "$USER" "$PW"

VERIFY_DB="$(databases_for_role "$USER" | head -n1)"
if [[ -n "$VERIFY_DB" ]]; then
  if verify_role_login "$USER" "$PW" "$VERIFY_DB"; then
    echo "OK password set for ${USER} (login verified on ${VERIFY_DB})"
  else
    echo "ERROR: password set but login verification failed on '${VERIFY_DB}'." >&2
    exit 1
  fi
else
  echo "OK password set for ${USER} (no database CONNECT to verify)"
fi
