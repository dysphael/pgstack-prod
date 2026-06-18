#!/usr/bin/env bash
# Interactive manager for pgstack-prod.
# Usage: ./scripts/manager.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/_common.sh"

pause() {
  read -r -p "Press Enter to continue..."
}

clear_screen() {
  clear 2>/dev/null || printf '\033[2J\033[H'
}

show_header() {
  local backup_dir log_dir
  backup_dir="$(abs_path "${BACKUP_DIR:-./backups}")"
  log_dir="$(abs_path "${LOG_DIR:-./logs/postgres}")"
  echo "Host: ${POSTGRES_HOST:-not set} | Admin: ${POSTGRES_USER} | Backups: ${backup_dir} | Logs: ${log_dir}"
  if postgres_ready; then
    echo "PostgreSQL: ready"
  else
    echo "PostgreSQL: not ready (run: docker compose up -d)"
  fi
  echo ""
}

require_db_action() {
  if postgres_ready; then
    return 0
  fi
  echo "PostgreSQL is not running. Start it with: docker compose up -d"
  return 1
}

show_menu() {
  echo "  1) Status / health"
  echo "  2) List project databases"
  echo "  3) List users and access"
  echo "  4) Create project database"
  echo "  5) Add user (read / write)"
  echo "  6) Backup one database"
  echo "  7) Backup all databases"
  echo "  8) List backups"
  echo "  9) Restore backup"
  echo " 10) Open psql shell"
  echo "  0) Exit"
  echo ""
}

action_status() {
  "${SCRIPT_DIR}/status.sh"
}

action_list_dbs() {
  require_db_action || return 0
  echo "Project databases:"
  echo ""
  docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -c \
    "SELECT datname AS database, pg_catalog.pg_get_userbyid(datdba) AS owner
     FROM pg_database
     WHERE datistemplate = false AND datname <> 'postgres'
     ORDER BY datname;"
}

action_list_access() {
  require_db_action || return 0
  mapfile -t DBS < <(list_project_dbs)
  if [[ ${#DBS[@]} -gt 0 ]] && pick_from_list "Filter by database (or cancel for all):" "All databases" "${DBS[@]}"; then
    if [[ "$PICK_RESULT" == "All databases" ]]; then
      "${SCRIPT_DIR}/list-access.sh"
    else
      "${SCRIPT_DIR}/list-access.sh" "$PICK_RESULT"
    fi
  else
    "${SCRIPT_DIR}/list-access.sh"
  fi
}

action_create_db() {
  require_db_action || return 0
  read -r -p "Database name (e.g. myapp): " DB
  [[ -n "$DB" ]] || { echo "Cancelled."; return 0; }
  valid_db_name "$DB" || { echo "ERROR: invalid name. Use lowercase letters, numbers, underscore."; return 0; }
  "${SCRIPT_DIR}/create-db.sh" "$DB"
}

action_add_user() {
  require_db_action || return 0
  mapfile -t DBS < <(list_project_dbs)
  [[ ${#DBS[@]} -gt 0 ]] || { echo "No project databases. Create one first (option 4)."; return 0; }

  pick_from_list "Select database:" "${DBS[@]}" || { echo "Cancelled."; return 0; }
  local db="$PICK_RESULT"

  pick_from_list "Select access level:" "read" "write" || { echo "Cancelled."; return 0; }
  local access="$PICK_RESULT"

  read -r -p "Username: " user
  [[ -n "$user" ]] || { echo "Cancelled."; return 0; }
  valid_db_name "$user" || { echo "ERROR: invalid username."; return 0; }

  "${SCRIPT_DIR}/add-user.sh" "$db" "$access" "$user"
}

action_backup_one() {
  require_db_action || return 0
  mapfile -t DBS < <(list_project_dbs)
  [[ ${#DBS[@]} -gt 0 ]] || { echo "No project databases found."; return 0; }
  pick_from_list "Select database to backup:" "${DBS[@]}" || { echo "Cancelled."; return 0; }
  "${SCRIPT_DIR}/backup.sh" "$PICK_RESULT"
}

action_backup_all() {
  require_db_action || return 0
  "${SCRIPT_DIR}/backup.sh"
}

backup_db_from_filename() {
  local file="$1"
  local base="${file##*/}"
  if [[ "$base" =~ ^backup_([a-z][a-z0-9_]*)_[0-9]{8}_[0-9]{6}\.sql\.gz$ ]]; then
    printf '%s' "${BASH_REMATCH[1]}"
  else
    printf '%s' "?"
  fi
}

collect_backups() {
  BACKUP_FILES=()
  local dir
  dir="$(abs_path "${BACKUP_DIR:-./backups}")"
  mkdir -p "$dir"
  mapfile -t BACKUP_FILES < <(find "$dir" -maxdepth 1 -name 'backup_*.sql.gz' -type f 2>/dev/null | sort -r)
}

show_backup_list() {
  collect_backups
  local dir
  dir="$(abs_path "${BACKUP_DIR:-./backups}")"

  if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
    echo "No backups in ${dir}"
    return 1
  fi

  printf '%-3s %-12s %-6s %-20s %s\n' "#" "DB" "Size" "Date" "Path"
  local i file db size mtime
  for i in "${!BACKUP_FILES[@]}"; do
    file="${BACKUP_FILES[$i]}"
    db="$(backup_db_from_filename "$file")"
    size="$(du -h "$file" | cut -f1)"
    mtime="$(date -r "$file" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$file")"
    printf '%-3s %-12s %-6s %-20s %s\n' "$((i + 1))" "$db" "$size" "$mtime" "$file"
  done
  return 0
}

action_list_backups() {
  show_backup_list || true
}

action_restore() {
  require_db_action || return 0
  collect_backups
  show_backup_list || return 0

  echo ""
  read -r -p "Backup number (0 = cancel): " choice
  [[ "$choice" == "0" || -z "$choice" ]] && { echo "Cancelled."; return 0; }
  [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Invalid choice."; return 0; }
  (( choice >= 1 && choice <= ${#BACKUP_FILES[@]} )) || { echo "Invalid choice."; return 0; }

  local file="${BACKUP_FILES[$((choice - 1))]}"
  local suggested
  suggested="$(backup_db_from_filename "$file")"

  read -r -p "Target database [${suggested}]: " DB
  DB="${DB:-$suggested}"
  [[ -n "$DB" && "$DB" != "?" ]] || { echo "ERROR: invalid database name."; return 0; }
  valid_db_name "$DB" || { echo "ERROR: invalid database name."; return 0; }

  "${SCRIPT_DIR}/restore.sh" "$file" "$DB"
}

action_psql() {
  require_db_action || return 0
  echo "Opening psql (type \\q to exit)..."
  docker compose exec -it postgres psql -U "$POSTGRES_USER" -d postgres
}

main() {
  set_env

  while true; do
    clear_screen
    echo "=== pgstack-prod Manager ==="
    echo ""
    show_header
    show_menu
    read -r -p "Choice: " choice

    case "$choice" in
      1)  clear_screen; action_status ;;
      2)  clear_screen; action_list_dbs ;;
      3)  clear_screen; action_list_access ;;
      4)  clear_screen; action_create_db ;;
      5)  clear_screen; action_add_user ;;
      6)  clear_screen; action_backup_one ;;
      7)  clear_screen; action_backup_all ;;
      8)  clear_screen; action_list_backups ;;
      9)  clear_screen; action_restore ;;
      10) clear_screen; action_psql; continue ;;
      0|q|Q) echo "Bye."; exit 0 ;;
      *)  echo "Invalid choice." ;;
    esac

    pause
  done
}

main "$@"
