#!/usr/bin/env bash
# Create a project database with a dedicated owner.
# Usage: ./scripts/create-db.sh <database_name> [owner_user]

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DB_NAME="${1:-}"
OWNER="${2:-${DB_NAME}_app}"

if [[ ! -f .env ]]; then
  echo "ERROR: .env not found." >&2
  exit 1
fi

if [[ -z "$DB_NAME" ]]; then
  echo "Usage: ./scripts/create-db.sh <database_name> [owner_user]" >&2
  exit 1
fi

if [[ ! "$DB_NAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "ERROR: invalid database name '${DB_NAME}'." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

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
