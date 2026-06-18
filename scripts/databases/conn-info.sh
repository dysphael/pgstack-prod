#!/usr/bin/env bash
# Show connection strings for a project database.
# Usage: ./scripts/databases/conn-info.sh <database>

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

DB="${1:-}"
[[ -n "$DB" ]] || { echo "Usage: ./scripts/databases/conn-info.sh <database>" >&2; exit 1; }
valid_db_name "$DB" || { echo "ERROR: invalid database name." >&2; exit 1; }

HOST="${POSTGRES_HOST:-localhost}"

echo "Connection strings for '${DB}':"
echo ""
echo "  Owner (read/write/delete):"
echo "  postgresql://${DB}_owner:PASSWORD@${HOST}:5432/${DB}"
echo ""
echo "  Read only:"
echo "  postgresql://${DB}_read:PASSWORD@${HOST}:5432/${DB}"
echo ""
echo "  Schema: app"
echo ""
echo "  Extra users with access:"

docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc "
SELECT r.rolname
FROM pg_roles r
WHERE r.rolcanlogin
  AND NOT r.rolsuper
  AND r.rolname NOT IN ('${DB}_owner', '${DB}_read', '${DB}_admin')
  AND has_database_privilege(r.rolname, '${DB}', 'CONNECT')
ORDER BY r.rolname;
" | while read -r user; do
  [[ -n "$user" ]] && echo "  postgresql://${user}:PASSWORD@${HOST}:5432/${DB}"
done
