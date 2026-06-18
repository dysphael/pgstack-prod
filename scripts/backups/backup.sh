#!/usr/bin/env bash
# Usage: ./scripts/backups/backup.sh [database|--list]

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env
require_postgres

mkdir -p "$BACKUP_DIR"
TARGET="${1:-}"
TS="$(date +%Y%m%d_%H%M%S)"

backup_db() {
  local db="$1"
  local file="${BACKUP_DIR}/backup_${db}_${TS}.sql.gz"
  echo "Backing up ${db}..."
  docker compose exec -T postgres pg_dump -U "$POSTGRES_USER" --no-owner --no-acl -d "$db" | gzip > "$file"
  [[ -s "$file" ]] || { rm -f "$file"; echo "ERROR: backup failed." >&2; exit 1; }
  echo "OK ${file} ($(du -h "$file" | cut -f1))"
  # shellcheck disable=SC1091
  source "${ROOT}/lib/db-users.sh"
  source "${ROOT}/lib/app-lifecycle.sh"
  write_backup_manifest "$db" "$file"
}

[[ "$TARGET" == "--list" || "$TARGET" == "-l" ]] && exec "$(dirname "$0")/list-backups.sh"

if [[ -n "$TARGET" ]]; then
  valid_db_name "$TARGET" || { echo "ERROR: invalid name '${TARGET}'." >&2; exit 1; }
  backup_db "$TARGET"
else
  DBS=()
  read_array DBS list_project_dbs
  if [[ ${#DBS[@]} -eq 0 ]]; then
    backup_db "${POSTGRES_DB}"
  else
    for db in "${DBS[@]}"; do [[ -n "$db" ]] && backup_db "$db"; done
  fi
fi
