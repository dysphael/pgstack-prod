#!/usr/bin/env bash
# Bootstrap a project database + owner user after wiping data/postgres/.
# Uses PGSTACK_PASSWORD (same value as DATABASE_URL in your app .env).
#
# Usage:
#   PGSTACK_PASSWORD='app-secret' ./scripts/setup/bootstrap-app.sh <database> <username>
#
# Prefer: PGSTACK_PASSWORD='...' ./scripts/app.sh setup <database> <username>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
source "${ROOT}/lib/app-lifecycle.sh"

DB="${1:-}"
USER="${2:-}"
LABEL="${3:-}"

[[ -n "$DB" && -n "$USER" ]] || {
  echo "Usage: PGSTACK_PASSWORD='...' ./scripts/setup/bootstrap-app.sh <database> <username> [label]" >&2
  exit 1
}
require_app_password || exit 1
valid_db_name "$DB" && valid_db_name "$USER" || { echo "ERROR: invalid name." >&2; exit 1; }

set_env
require_postgres
app_setup "$DB" "$USER" "$PGSTACK_PASSWORD" "$LABEL"
