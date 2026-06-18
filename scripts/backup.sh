#!/usr/bin/env bash
# Usage: ./scripts/backup.sh [database|--list]

set -euo pipefail
source "$(dirname "$0")/_common.sh"
set_env
require_postgres

BACKUP_DIR="${BACKUP_DIR:-./backups}"
mkdir -p "$BACKUP_DIR"
TARGET="${1:-}"
TS="$(date +%Y%m%d_%H%M%S)"

list_backups() {
  ls -lh "${BACKUP_DIR}"/backup_*.sql.gz 2>/dev/null || echo "No backups yet."
}

backup_db() {
  local db="$1" file="${BACKUP_DIR}/backup_${db}_${TS}.sql.gz"
  echo "Backing up ${db}..."
  docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" --no-owner --no-acl -d "$db" | gzip > "$file"
  [[ -s "$file" ]] || { rm -f "$file"; echo "ERROR: backup failed." >&2; exit 1; }
  echo "OK ${file} ($(du -h "$file" | cut -f1))"
}

[[ "$TARGET" == "--list" || "$TARGET" == "-l" ]] && { list_backups; exit 0; }

if [[ -n "$TARGET" ]]; then
  valid_db_name "$TARGET" || { echo "ERROR: invalid name '${TARGET}'." >&2; exit 1; }
  backup_db "$TARGET"
else
  mapfile -t DBS < <(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';")
  if [[ ${#DBS[@]} -eq 0 ]]; then
    backup_db "${POSTGRES_DB}"
  else
    for db in "${DBS[@]}"; do [[ -n "$db" ]] && backup_db "$db"; done
  fi
fi
