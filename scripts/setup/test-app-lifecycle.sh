#!/usr/bin/env bash
# End-to-end lifecycle test: setup → backup → drop → restore → verify.
#
# Usage:
#   ./scripts/setup/test-app-lifecycle.sh
#   PGSTACK_PASSWORD='test-secret' ./scripts/setup/test-app-lifecycle.sh

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
source "${ROOT}/lib/app-lifecycle.sh"

DB="pgstack_lc_$$"
USER="pgstack_lc_user_$$"
PW="${PGSTACK_PASSWORD:-test-lifecycle-$(date +%s)}"
export PGSTACK_PASSWORD="$PW"
export PGSTACK_YES=1

cleanup() {
  cd "$ROOT"
  set +e
  db_exists "$DB" && PGSTACK_YES=1 app_drop "$DB" 0 >/dev/null 2>&1
  role_exists "$USER" && docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
    -c "DROP ROLE IF EXISTS \"${USER}\";" >/dev/null 2>&1
  python3 - "$(app_registry_file)" "$DB" <<'PY' 2>/dev/null || true
import json, sys
path, db = sys.argv[1:3]
with open(path) as f:
    data = json.load(f)
data.pop(db, None)
with open(path, "w") as f:
    json.dump(data, f, indent=2, sort_keys=True)
    f.write("\n")
PY
}
trap cleanup EXIT

set_env
require_postgres
app_registry_ensure

echo "=== pgstack app lifecycle test ==="
echo "DB=${DB} USER=${USER}"
echo ""

app_setup "$DB" "$USER" "$PW" "lifecycle-test" || exit 1
BACKUP_FILE="$(app_backup "$DB")"
[[ -n "$BACKUP_FILE" && -f "$BACKUP_FILE" ]] || { echo "FAIL: backup missing" >&2; exit 1; }
echo "Backup: ${BACKUP_FILE}"

app_drop "$DB" 0
db_exists "$DB" && { echo "FAIL: database still exists after drop" >&2; exit 1; }
echo "Dropped OK"

app_restore "$BACKUP_FILE" "$DB" "$USER" "$PW"
app_verify "$DB" "$USER" "$PW"

echo ""
echo "=== PASS — full lifecycle OK ==="
