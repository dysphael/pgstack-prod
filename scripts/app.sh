#!/usr/bin/env bash
# Unified app lifecycle CLI (Manager uses this under the hood).
#
# Usage:
#   PGSTACK_PASSWORD='...' ./scripts/app.sh setup   <db> <user> [label]
#   ./scripts/app.sh backup <db>
#   PGSTACK_PASSWORD='...' ./scripts/app.sh restore <file.sql.gz> [db] [user]
#   PGSTACK_PASSWORD='...' PGSTACK_YES=1 ./scripts/app.sh drop <db> [--backup-first|--no-backup]
#   PGSTACK_PASSWORD='...' ./scripts/app.sh verify  <db> [user]
#   ./scripts/app.sh register <db> <user> [label]
#   ./scripts/app.sh list

set -euo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/lib/init.sh"
source "${ROOT}/lib/db-users.sh"
source "${ROOT}/lib/app-lifecycle.sh"

CMD="${1:-}"
shift || true

usage() {
  cat <<EOF
Usage: ./scripts/app.sh <command> [args]

Commands:
  list                          List registered apps
  register <db> <user> [label]  Save app to registry (no DB changes)
  setup   <db> <user> [label]   Create DB + owner + verify (needs PGSTACK_PASSWORD)
  backup  <db>                  Backup + manifest
  restore <file> [db] [user]    Restore + users + verify (needs PGSTACK_PASSWORD)
  drop    <db> [--backup-first] Drop DB (optional safety backup first)
  verify  <db> [user]           Check app can connect (needs PGSTACK_PASSWORD)

Environment:
  PGSTACK_PASSWORD  Exact password from app DATABASE_URL
  PGSTACK_YES=1     Skip YES confirmation (restore/drop)
EOF
}

set_env
require_postgres

case "$CMD" in
  list)
    app_registry_print_table
    ;;
  register)
    DB="${1:-}" USER="${2:-}" LABEL="${3:-}"
    [[ -n "$DB" && -n "$USER" ]] || { usage; exit 1; }
    valid_db_name "$DB" && valid_db_name "$USER" || exit 1
    app_register "$DB" "$USER" "$LABEL"
    ;;
  setup)
    DB="${1:-}" USER="${2:-}" LABEL="${3:-}"
    [[ -n "$DB" && -n "$USER" ]] || { usage; exit 1; }
    require_app_password || exit 1
    app_setup "$DB" "$USER" "$PGSTACK_PASSWORD" "$LABEL"
    ;;
  backup)
    DB="${1:-}"
    [[ -n "$DB" ]] || { usage; exit 1; }
    app_backup "$DB" >/dev/null
    ;;
  restore)
    FILE="${1:-}" DB="${2:-}" USER="${3:-}"
    [[ -n "$FILE" ]] || { usage; exit 1; }
    require_app_password || exit 1
    app_restore "$FILE" "$DB" "$USER" "$PGSTACK_PASSWORD"
    ;;
  drop)
    DB="${1:-}"
    BACKUP_FIRST=1
    [[ -n "$DB" ]] || { usage; exit 1; }
    [[ "${2:-}" == "--no-backup" ]] && BACKUP_FIRST=0
    [[ "${2:-}" == "--backup-first" ]] && BACKUP_FIRST=1
    if [[ "${PGSTACK_YES:-}" != "1" ]]; then
      echo "Drop '${DB}' (backup first: $([[ "$BACKUP_FIRST" == 1 ]] && echo yes || echo no))"
      confirm_yes "Type YES to continue:" || { echo "Cancelled."; exit 0; }
    fi
    app_drop "$DB" "$BACKUP_FIRST"
    ;;
  verify)
    DB="${1:-}" USER="${2:-}"
    [[ -n "$DB" ]] || { usage; exit 1; }
    require_app_password || exit 1
    app_verify "$DB" "$USER" "$PGSTACK_PASSWORD"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    echo "ERROR: unknown command '${CMD}'" >&2
    usage
    exit 1
    ;;
esac
