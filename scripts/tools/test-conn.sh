#!/usr/bin/env bash
# Test PostgreSQL login the same way a remote app does (TCP + password).
#
# Usage:
#   PGSTACK_PASSWORD='secret' ./scripts/tools/test-conn.sh <user> <database> [host] [port]
#   ./scripts/tools/test-conn.sh hyperfx_django hyperfx db.blockway.ai 5432

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env

USER="${1:-}"
DB="${2:-}"
HOST="${3:-${POSTGRES_HOST:-127.0.0.1}}"
PORT="${4:-5432}"
PW="${PGSTACK_PASSWORD:-}"

[[ -n "$USER" && -n "$DB" ]] || {
  echo "Usage: PGSTACK_PASSWORD='...' ./scripts/tools/test-conn.sh <user> <database> [host] [port]" >&2
  exit 1
}
[[ -n "$PW" ]] || { echo "ERROR: set PGSTACK_PASSWORD." >&2; exit 1; }

if command -v psql >/dev/null 2>&1; then
  PGPASSWORD="$PW" psql -v ON_ERROR_STOP=1 -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" \
    -c "SELECT current_user AS user, current_database() AS db;"
else
  docker compose exec -T -e PGPASSWORD="$PW" postgres \
    psql -v ON_ERROR_STOP=1 -h "$HOST" -p "$PORT" -U "$USER" -d "$DB" \
    -c "SELECT current_user AS user, current_database() AS db;"
fi

echo "OK connection to ${HOST}:${PORT}/${DB} as ${USER}"
