#!/usr/bin/env bash
# Usage: ./scripts/status.sh

set -euo pipefail
source "$(dirname "$0")/_common.sh"
set_env

echo "Host: ${POSTGRES_HOST:-not set} | User: ${POSTGRES_USER} | DB: ${POSTGRES_DB}"
docker compose ps

if docker compose exec -T postgres pg_isready -U "$POSTGRES_USER" -d "${POSTGRES_DB:-postgres}" >/dev/null 2>&1; then
  echo "PostgreSQL: ready"
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "\l" | head -15
else
  echo "PostgreSQL: not ready (run: docker compose up -d)"
fi
