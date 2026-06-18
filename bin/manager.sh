#!/usr/bin/env bash
# Interactive manager — delegates to CLI scripts under scripts/.
# Usage: ./bin/manager.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
source "${ROOT}/lib/backups.sh"

SCRIPTS="${ROOT}/scripts"

pause() {
  read -r -p "Press Enter to continue..."
}

clear_screen() {
  clear 2>/dev/null || printf '\033[2J\033[H'
}

show_header() {
  echo "Host: ${POSTGRES_HOST:-not set} | Admin: ${POSTGRES_USER} | Backups: $(backup_dir) | Logs: $(abs_path "${LOG_DIR:-./logs/postgres}")"
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

# Usage: run <category> <script> [args...]
run() {
  "${SCRIPTS}/$1/$2" "${@:3}"
}

submenu_overview() {
  while true; do
    clear_screen
    echo "=== Overview ==="
    echo ""
    echo "  1) Status / health       → overview/status.sh"
    echo "  2) Database stats        → overview/db-stats.sh"
    echo "  3) Active connections    → overview/connections.sh"
    echo "  4) Table sizes           → overview/db-tables.sh"
    echo "  5) Slow queries          → overview/slow-queries.sh"
    echo "  6) View logs             → overview/logs.sh"
    echo "  0) Back"
    echo ""
    read -r -p "Choice: " c
    case "$c" in
      1) clear_screen; run overview status.sh ;;
      2) clear_screen; require_db_action && run overview db-stats.sh || true ;;
      3) clear_screen; require_db_action && action_connections || true ;;
      4) clear_screen; require_db_action && action_tables || true ;;
      5) clear_screen; require_db_action && run overview slow-queries.sh || true ;;
      6) clear_screen; run overview logs.sh || true ;;
      0) return 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
    pause
  done
}

submenu_databases() {
  while true; do
    clear_screen
    echo "=== Databases ==="
    echo ""
    echo "  1) List databases        → databases/list-dbs.sh"
    echo "  2) Create database       → databases/create-db.sh"
    echo "  3) Drop database         → databases/drop-db.sh"
    echo "  4) Connection strings    → databases/conn-info.sh"
    echo "  0) Back"
    echo ""
    read -r -p "Choice: " c
    case "$c" in
      1) clear_screen; require_db_action && run databases list-dbs.sh || true ;;
      2) clear_screen; action_create_db ;;
      3) clear_screen; require_db_action && action_drop_db || true ;;
      4) clear_screen; require_db_action && action_conn_info || true ;;
      0) return 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
    pause
  done
}

submenu_users() {
  while true; do
    clear_screen
    echo "=== Users ==="
    echo ""
    echo "  1) List users & access   → users/list-access.sh"
    echo "  2) Add user              → users/add-user.sh"
    echo "  3) Reset password        → users/reset-password.sh"
    echo "  4) Drop user             → users/drop-user.sh"
    echo "  0) Back"
    echo ""
    read -r -p "Choice: " c
    case "$c" in
      1) clear_screen; action_list_access ;;
      2) clear_screen; action_add_user ;;
      3) clear_screen; require_db_action && action_reset_password || true ;;
      4) clear_screen; require_db_action && action_drop_user || true ;;
      0) return 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
    pause
  done
}

submenu_backups() {
  while true; do
    clear_screen
    echo "=== Backups ==="
    echo ""
    echo "  1) Backup one database   → backups/backup.sh <db>"
    echo "  2) Backup all            → backups/backup.sh"
    echo "  3) List backups          → backups/list-backups.sh"
    echo "  4) Restore backup        → backups/restore.sh"
    echo "  0) Back"
    echo ""
    read -r -p "Choice: " c
    case "$c" in
      1) clear_screen; action_backup_one ;;
      2) clear_screen; require_db_action && run backups backup.sh || true ;;
      3) clear_screen; run backups list-backups.sh || true ;;
      4) clear_screen; action_restore ;;
      0) return 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
    pause
  done
}

submenu_tools() {
  while true; do
    clear_screen
    echo "=== Tools ==="
    echo ""
    echo "  1) psql shell            → tools/psql.sh"
    echo "  0) Back"
    echo ""
    read -r -p "Choice: " c
    case "$c" in
      1) clear_screen; require_db_action && action_psql || true; return 0 ;;
      0) return 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

action_connections() {
  if pick_project_db "Filter by database (or cancel for all):"; then
    run overview connections.sh "$PICK_RESULT"
  else
    run overview connections.sh
  fi
}

action_tables() {
  pick_project_db "Select database:" || { echo "Cancelled."; return 0; }
  run overview db-tables.sh "$PICK_RESULT"
}

action_conn_info() {
  pick_project_db "Select database:" || { echo "Cancelled."; return 0; }
  run databases conn-info.sh "$PICK_RESULT"
}

action_list_access() {
  require_db_action || return 0
  mapfile -t DBS < <(list_project_dbs)
  if [[ ${#DBS[@]} -gt 0 ]] && pick_from_list "Filter by database (or cancel for all):" "All databases" "${DBS[@]}"; then
    if [[ "$PICK_RESULT" == "All databases" ]]; then
      run users list-access.sh
    else
      run users list-access.sh "$PICK_RESULT"
    fi
  else
    run users list-access.sh
  fi
}

action_create_db() {
  require_db_action || return 0
  read -r -p "Database name (e.g. myapp): " DB
  [[ -n "$DB" ]] || { echo "Cancelled."; return 0; }
  valid_db_name "$DB" || { echo "ERROR: invalid name."; return 0; }
  run databases create-db.sh "$DB"
}

action_drop_db() {
  pick_project_db "Select database to drop:" || { echo "Cancelled."; return 0; }
  run databases drop-db.sh "$PICK_RESULT"
}

action_add_user() {
  require_db_action || return 0
  pick_project_db "Select database:" || { echo "Cancelled."; return 0; }
  local db="$PICK_RESULT"

  pick_from_list "Select access level:" "owner" "read" "write" "admin" || { echo "Cancelled."; return 0; }
  local access="$PICK_RESULT"

  read -r -p "Username: " user
  [[ -n "$user" ]] || { echo "Cancelled."; return 0; }
  valid_db_name "$user" || { echo "ERROR: invalid username."; return 0; }

  run users add-user.sh "$db" "$access" "$user"
}

action_reset_password() {
  read -r -p "Username: " user
  [[ -n "$user" ]] || { echo "Cancelled."; return 0; }
  valid_db_name "$user" || { echo "ERROR: invalid username."; return 0; }
  run users reset-password.sh "$user"
}

action_drop_user() {
  read -r -p "Username: " user
  [[ -n "$user" ]] || { echo "Cancelled."; return 0; }
  valid_db_name "$user" || { echo "ERROR: invalid username."; return 0; }
  run users drop-user.sh "$user"
}

action_backup_one() {
  require_db_action || return 0
  pick_project_db "Select database to backup:" || { echo "Cancelled."; return 0; }
  run backups backup.sh "$PICK_RESULT"
}

action_restore() {
  require_db_action || return 0
  run backups list-backups.sh || return 0

  echo ""
  read -r -p "Backup number (0 = cancel): " choice
  [[ "$choice" == "0" || -z "$choice" ]] && { echo "Cancelled."; return 0; }

  local file
  file="$(run backups list-backups.sh --path "$choice" 2>/dev/null)" || { echo "Invalid choice."; return 0; }

  local suggested
  suggested="$(backup_db_from_filename "$file")"

  read -r -p "Target database [${suggested}]: " DB
  DB="${DB:-$suggested}"
  [[ -n "$DB" && "$DB" != "?" ]] || { echo "ERROR: invalid database name."; return 0; }
  valid_db_name "$DB" || { echo "ERROR: invalid database name."; return 0; }

  run backups restore.sh "$file" "$DB"
}

action_psql() {
  if pick_project_db "Select database (or cancel for postgres):"; then
    run tools psql.sh "$PICK_RESULT"
  else
    run tools psql.sh
  fi
}

show_menu() {
  echo "  1) Overview    (status, stats, connections, logs)"
  echo "  2) Databases   (list, create, drop, connection strings)"
  echo "  3) Users       (list, add, reset password, drop)"
  echo "  4) Backups     (backup, restore, list)"
  echo "  5) Tools       (psql shell)"
  echo "  0) Exit"
  echo ""
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
      1) submenu_overview ;;
      2) submenu_databases ;;
      3) submenu_users ;;
      4) submenu_backups ;;
      5) submenu_tools ;;
      0|q|Q) echo "Bye."; exit 0 ;;
      *) echo "Invalid choice."; pause ;;
    esac
  done
}

main "$@"
