#!/usr/bin/env bash
# Usage: ./scripts/overview/status.sh

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
source "${ROOT}/lib/backups.sh"
set_env

echo "=== pgstack-prod status ==="
echo ""
echo "Host:     ${POSTGRES_HOST:-not set}"
echo "Admin:    ${POSTGRES_USER}"
echo "Backups:  $(backup_dir)"
echo "Logs:     $(abs_path "${LOG_DIR:-./logs/postgres}")"
echo ""

echo "=== Docker ==="
docker compose ps
echo ""

if postgres_ready; then
  echo "PostgreSQL: ready"
  echo ""
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
    SELECT
      version() AS version,
      pg_postmaster_start_time() AS started_at,
      (SELECT count(*) FROM pg_stat_activity) AS connections;
  "
  echo ""
  echo "Project databases:"
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c "
    SELECT datname AS database, pg_size_pretty(pg_database_size(datname)) AS size
    FROM pg_database
    WHERE datistemplate = false AND datname <> 'postgres'
    ORDER BY datname;
  "
elif postgres_server_up; then
  echo "PostgreSQL: running (container healthy)"
  echo "Login failed for admin user '${POSTGRES_USER}'."
  echo ""
  echo "POSTGRES_USER is set only on first boot. Your volume has a different admin user."
  echo "Fix: restore the original user in .env, or reset the volume if this is a fresh install."
else
  echo "PostgreSQL: not ready (run: docker compose up -d)"
fi
