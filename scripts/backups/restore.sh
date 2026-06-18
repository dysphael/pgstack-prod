#!/usr/bin/env bash
# Restore a backup and bring the app back online (users + password + verify).
#
# Usage:
#   PGSTACK_PASSWORD='...' ./scripts/backups/restore.sh <backup.sql.gz> <database> [owner_user]
#   PGSTACK_YES=1 skips YES confirmation

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
source "${ROOT}/lib/app-lifecycle.sh"

FILE="${1:-}" DB="${2:-}" OWNER="${3:-}"
PW="${PGSTACK_PASSWORD:-}"

[[ -n "$FILE" && -n "$DB" ]] || {
  echo "Usage: PGSTACK_PASSWORD='...' ./scripts/backups/restore.sh <file.sql.gz> <database> [owner_user]" >&2
  exit 1
}

set_env
require_postgres
require_app_password || exit 1

app_restore "$FILE" "$DB" "$OWNER" "$PW"
