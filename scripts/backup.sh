#!/usr/bin/env bash
# Create a compressed backup of one or all databases.
#
# Usage:
#   ./scripts/backup.sh           → backup all project databases
#   ./scripts/backup.sh myapp     → backup only "myapp"
#   ./scripts/backup.sh --list    → show existing backup files

set -euo pipefail

# shellcheck source=_common.sh
source "$(dirname "${BASH_SOURCE[0]}")/_common.sh"
set_env
require_postgres

BACKUP_DIR="${BACKUP_DIR:-./backups}"
mkdir -p "$BACKUP_DIR"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TARGET="${1:-}"

list_backups() {
  echo ""
  echo "Backup folder: ${BACKUP_DIR}"
  echo ""
  if ! ls -1 "${BACKUP_DIR}"/backup_*.sql.gz >/dev/null 2>&1; then
    echo "  (no backups yet — run ./scripts/backup.sh first)"
    echo ""
    return
  fi
  ls -lh "${BACKUP_DIR}"/backup_*.sql.gz
  echo ""
}

backup_db() {
  local db="$1"
  local file="${BACKUP_DIR}/backup_${db}_${TIMESTAMP}.sql.gz"

  echo ""
  echo "→ Backing up database: ${db}"
  docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" -d "$db" | gzip > "$file"

  if [[ ! -s "$file" ]]; then
    echo "  ERROR: backup file is empty. Check: docker compose logs postgres" >&2
    rm -f "$file"
    exit 1
  fi

  echo "  Saved: ${file}"
  echo "  Size:  $(du -h "$file" | cut -f1)"
}

if [[ "${TARGET}" == "--list" || "${TARGET}" == "-l" ]]; then
  list_backups
  exit 0
fi

echo ""
echo "========================================"
echo "  PostgreSQL backup"
echo "========================================"

if [[ -n "$TARGET" ]]; then
  if ! valid_db_name "$TARGET"; then
    echo "ERROR: invalid database name '${TARGET}'." >&2
    exit 1
  fi
  backup_db "$TARGET"
else
  mapfile -t DATABASES < <(
    docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
      "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');"
  )
  if [[ "${#DATABASES[@]}" -eq 0 ]]; then
    echo ""
    echo "No project databases found. Backing up default: ${POSTGRES_DB}"
    backup_db "${POSTGRES_DB}"
  else
    for db in "${DATABASES[@]}"; do
      [[ -n "$db" ]] && backup_db "$db"
    done
  fi
fi

echo ""
echo "Done. To restore later:"
echo "  ./scripts/restore.sh ${BACKUP_DIR}/backup_DATABASE_${TIMESTAMP}.sql.gz DATABASE"
echo ""
list_backups
