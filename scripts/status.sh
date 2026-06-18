#!/usr/bin/env bash
# Quick health check for PostgreSQL and folders.
# Usage: ./scripts/status.sh

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
set_env

echo ""
echo "========================================"
echo "  pgstack-prod status"
echo "========================================"
echo ""
echo "Host:     ${POSTGRES_HOST:-not set}"
echo "User:     ${POSTGRES_USER}"
echo "Database: ${POSTGRES_DB}"
echo ""

echo "Containers:"
docker compose ps
echo ""

if docker compose ps --status running --services postgres 2>/dev/null | grep -qx postgres; then
  if docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-postgres}" >/dev/null 2>&1; then
    echo "PostgreSQL: ready"
  else
    echo "PostgreSQL: starting (not ready yet)"
  fi

  echo ""
  echo "Databases:"
  docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres -c "\l" | head -20
else
  echo "PostgreSQL: not running"
  echo "Fix: docker compose up -d"
fi

echo ""
echo "Logs:    ${LOG_DIR:-./logs/postgres}"
echo "Backups: ${BACKUP_DIR:-./backups}"
echo ""
