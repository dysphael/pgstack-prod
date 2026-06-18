#!/usr/bin/env bash
# Diagnose why an app user cannot connect (role, grants, password, schema).
#
# Usage:
#   ./scripts/tools/diagnose-user.sh <username> <database>
#   PGSTACK_PASSWORD='...' ./scripts/tools/diagnose-user.sh hyperfx_django hyperfx

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
set_env
require_postgres

USER="${1:-}"
DB="${2:-}"
PW="${PGSTACK_PASSWORD:-}"

[[ -n "$USER" && -n "$DB" ]] || {
  echo "Usage: ./scripts/tools/diagnose-user.sh <username> <database>" >&2
  echo "Optional: PGSTACK_PASSWORD='...' to test remote-style login." >&2
  exit 1
}

echo "=== Diagnose ${USER} @ ${DB} ==="
echo ""

if ! role_exists "$USER"; then
  echo "FAIL role '${USER}' does not exist"
  echo "Fix: ./scripts/users/add-user.sh ${DB} owner ${USER}"
  exit 1
fi
echo "OK   role exists"

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
  "SELECT CASE WHEN rolcanlogin THEN 'OK   can LOGIN' ELSE 'FAIL cannot LOGIN' END
   FROM pg_roles WHERE rolname='${USER}';"

if ! db_exists "$DB"; then
  echo "FAIL database '${DB}' does not exist"
  exit 1
fi
echo "OK   database '${DB}' exists"

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
  "SELECT CASE WHEN has_database_privilege('${USER}', '${DB}', 'CONNECT')
    THEN 'OK   CONNECT on ${DB}' ELSE 'FAIL no CONNECT on ${DB}' END;"

if schema_app_exists "$DB"; then
  echo "OK   schema 'app' exists"
else
  echo "FAIL schema 'app' missing"
  echo "Fix: ./scripts/users/add-user.sh ${DB} owner ${USER}"
fi

echo ""
echo "Databases with access:"
databases_for_role "$USER" | sed 's/^/  /' || echo "  (none)"

if [[ -n "$PW" ]]; then
  echo ""
  if verify_role_login "$USER" "$PW" "$DB"; then
    echo "OK   password works (SCRAM via container IP — same as remote apps)"
  else
    echo "FAIL password does NOT work for remote-style login"
    echo "Fix: PGSTACK_PASSWORD='...' ./scripts/users/set-password.sh ${USER}"
  fi
else
  echo ""
  echo "Tip: set PGSTACK_PASSWORD to test the password:"
  echo "  PGSTACK_PASSWORD='...' ./scripts/tools/diagnose-user.sh ${USER} ${DB}"
fi
