#!/usr/bin/env bash
# End-to-end test: create DB + owner user, verify login, cleanup.
#
# Usage:
#   ./scripts/setup/test-create-flow.sh
#   PGSTACK_PASSWORD='test-secret-123' ./scripts/setup/test-create-flow.sh

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"

DB="pgstack_test_$$"
USER="pgstack_test_user_$$"
PW="${PGSTACK_PASSWORD:-test-pgstack-$(date +%s)}"

cleanup() {
  cd "$ROOT"
  set +e
  db_exists "$DB" && ./scripts/databases/drop-db.sh "$DB" <<< "YES" >/dev/null 2>&1
  role_exists "$USER" && docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres \
    -c "DROP ROLE IF EXISTS \"${USER}\";" >/dev/null 2>&1
}
trap cleanup EXIT

set_env
require_postgres

echo "=== pgstack create-flow test ==="
echo "DB=${DB} USER=${USER}"
echo ""

db_exists "$DB" && { echo "ERROR: test database already exists." >&2; exit 1; }
role_exists "$USER" && { echo "ERROR: test user already exists." >&2; exit 1; }

create_project_database "$DB" "$POSTGRES_USER"
setup_project_schema "$DB" "$POSTGRES_USER"
add_project_user "$DB" owner "$USER" "$PW"

echo ""
echo "=== PASS — create-flow OK ==="
echo "Login, search_path=app, and schema verified."
