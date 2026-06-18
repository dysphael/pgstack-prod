#!/usr/bin/env bash
# Create a project database with a dedicated owner.
# Usage: ./scripts/create-db.sh <database_name> [owner_user]

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"

DB_NAME="${1:-}"
OWNER="${2:-${DB_NAME}_app}"

if [[ -z "$DB_NAME" ]]; then
  echo "Usage: ./scripts/create-db.sh <database_name> [owner_user]" >&2
  exit 1
fi

if ! valid_db_name "$DB_NAME"; then
  echo "ERROR: invalid database name '${DB_NAME}'." >&2
  exit 1
fi

if ! valid_db_name "$OWNER"; then
  echo "ERROR: invalid owner name '${OWNER}'." >&2
  exit 1
fi

set_env
require_postgres

read -r -s -p "Password for new user '${OWNER}': " OWNER_PASSWORD
echo
read -r -s -p "Confirm password: " OWNER_PASSWORD_CONFIRM
echo

if [[ "$OWNER_PASSWORD" != "$OWNER_PASSWORD_CONFIRM" ]]; then
  echo "ERROR: passwords do not match." >&2
  exit 1
fi

OWNER_PASSWORD_ESC="${OWNER_PASSWORD//\'/\'\'}"

docker compose exec -T postgres psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${OWNER}') THEN
    CREATE ROLE ${OWNER} WITH LOGIN PASSWORD '${OWNER_PASSWORD_ESC}';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${OWNER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec

GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${OWNER};
SQL

echo ""
echo "Database ready:"
echo "  postgresql://${OWNER}:****@${POSTGRES_HOST:-localhost}:5432/${DB_NAME}"
