#!/usr/bin/env bash
# Interactive manager — terminal UI.
# Usage: ./bin/manager.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
source "${ROOT}/lib/backups.sh"
source "${ROOT}/lib/ui.sh"

SCRIPTS="${ROOT}/scripts"
GO_HOME=0
SHOW_BANNER=1

run() {
  local script="${SCRIPTS}/$1/$2"
  [[ -f "$script" ]] || {
    ui_err "Script not found: ${script}"
    ui_dim "Run: git pull"
    return 1
  }
  "$script" "${@:3}"
}

pause_continue() {
  local prc=0
  ui_pause || prc=$?
  [[ $prc -eq 2 ]] && GO_HOME=1
}

run_action() {
  local title="$1"
  shift
  ui_clear
  ui_action_header "$title"
  "$@" || true
  pause_continue
}

require_db_action() {
  if postgres_ready; then
    return 0
  fi
  if postgres_server_up; then
    ui_err "PostgreSQL running but admin '${POSTGRES_USER}' cannot connect."
    ui_dim "See README Troubleshooting (POSTGRES_USER mismatch)."
  else
    ui_err "PostgreSQL is not running."
    ui_dim "Start: docker compose up -d"
  fi
  return 1
}

ui_pick_project_db() {
  local prompt="${1:-Select database:}"
  mapfile -t DBS < <(list_project_dbs)
  [[ ${#DBS[@]} -gt 0 ]] || { ui_err "No project databases found."; return 1; }
  ui_pick_list "$prompt" "${DBS[@]}"
}

dashboard_live() {
  local pg_line db_line backup_line paths_line
  local db_count=0 db_list="" pg_ver="" pg_uptime=""
  local backup_count=0 latest_backup="none" backup_size="0"

  if postgres_ready; then
    read -r pg_ver pg_uptime < <(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
      "SELECT split_part(version(),' ',2), (now() - pg_postmaster_start_time())::text;" 2>/dev/null | tr '|' ' ')
    pg_ver="${pg_ver:-?}"
    pg_uptime="${pg_uptime:-?}"
    pg_line="PostgreSQL   $(ui_badge ok ONLINE)   PG ${pg_ver}   up ${pg_uptime}"
  elif postgres_server_up; then
    pg_line="PostgreSQL   $(ui_badge warn AUTH_FAIL)   check POSTGRES_USER in .env"
  else
    pg_line="PostgreSQL   $(ui_badge err OFFLINE)   docker compose up -d"
  fi

  if postgres_ready; then
    mapfile -t DBS < <(list_project_dbs)
    db_count=${#DBS[@]}
    if [[ $db_count -gt 0 ]]; then
      db_list="$(IFS=', '; echo "${DBS[*]}")"
    else
      db_list="none"
    fi
  else
    db_list="unavailable"
  fi
  db_line="Databases    ${db_count} project   ${db_list}"

  collect_backups
  backup_count=${#BACKUP_FILES[@]}
  if [[ $backup_count -gt 0 ]]; then
    latest_backup="$(backup_mtime "${BACKUP_FILES[0]}")"
    backup_size="$(du -sh "$(backup_dir)" 2>/dev/null | cut -f1)"
  else
    backup_size="0"
  fi
  backup_line="Backups      ${backup_count} files (${backup_size})   latest: ${latest_backup}"

  local docker_state
  docker_state="$(docker compose ps postgres --format '{{.State}}' 2>/dev/null | head -1)"
  docker_state="${docker_state:-not running}"
  local docker_line="Docker       postgres container: ${docker_state}"

  paths_line="Paths        $(backup_dir | sed "s|$ROOT/||")"
  paths_line+="   $(abs_path "${LOG_DIR:-./logs/postgres}" | sed "s|$ROOT/||")"

  ui_box "System" "$pg_line" "$db_line" "$backup_line" "$docker_line" "$paths_line"
}

draw_main_screen() {
  ui_clear
  if [[ "$SHOW_BANNER" -eq 1 ]]; then
    ui_banner
    SHOW_BANNER=0
  fi
  ui_header_compact
  ui_breadcrumb "Main"
  echo ""
  dashboard_live
  echo ""
  ui_box_open "Menu" 40
  ui_menu_item "1" "Overview" "status, stats, logs"
  ui_menu_item "2" "Databases" "create, list, drop"
  ui_menu_item "3" "Users" "roles, passwords"
  ui_menu_item "4" "Backups" "backup, restore"
  ui_menu_item "5" "Tools" "psql shell"
  ui_menu_item "0" "Exit"
  ui_box_close 40
  ui_footer_hints
}

draw_submenu() {
  local section="$1"
  shift
  ui_clear
  ui_header_compact
  ui_breadcrumb "Main > ${section}"
  echo ""
  ui_box_open "$section" 48
  while [[ $# -ge 3 ]]; do
    ui_menu_item "$1" "$2" "$3"
    shift 3
  done
  ui_menu_item "0" "Back"
  ui_box_close 48
  ui_footer_hints
}

handle_nav_input() {
  local choice="$1" is_main="${2:-0}"
  case "$choice" in
    h|H) GO_HOME=1; return 0 ;;
    ?) ui_help_screen; return 0 ;;
    q|Q)
      if [[ "$is_main" -eq 1 ]]; then
        ui_ok "Bye."
        exit 0
      fi
      GO_HOME=1
      return 0
      ;;
  esac
  return 1
}

submenu_overview() {
  local c
  while true; do
    GO_HOME=0
    draw_submenu "Overview" \
      "1" "Status / health" "container + postgres" \
      "2" "Database stats" "sizes, cache hit" \
      "3" "Active connections" "running queries" \
      "4" "Table sizes" "rows per table" \
      "5" "Slow queries" "pg_stat_statements" \
      "6" "View logs" "postgresql logs"
    ui_read_choice
    c="${UI_CHOICE:-}"
    handle_nav_input "$c" 0 && { [[ $GO_HOME -eq 1 ]] && return 0; continue; }

    case "$c" in
      1) run_action "Status" run overview status.sh ;;
      2) require_db_action && run_action "Database stats" run overview db-stats.sh || pause_continue ;;
      3) require_db_action && run_action "Connections" action_connections || pause_continue ;;
      4) require_db_action && run_action "Table sizes" action_tables || pause_continue ;;
      5) require_db_action && run_action "Slow queries" run overview slow-queries.sh || pause_continue ;;
      6) run_action "Logs" run overview logs.sh ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

submenu_databases() {
  local c
  while true; do
    GO_HOME=0
    draw_submenu "Databases" \
      "1" "List databases" "all project DBs" \
      "2" "Create database" "optional users" \
      "3" "Drop database" "destructive" \
      "4" "Connection strings" "per DB"
    ui_read_choice
    c="${UI_CHOICE:-}"
    handle_nav_input "$c" 0 && { [[ $GO_HOME -eq 1 ]] && return 0; continue; }

    case "$c" in
      1) require_db_action && run_action "List databases" run databases list-dbs.sh || pause_continue ;;
      2) require_db_action && run_action "Create database" action_create_db || pause_continue ;;
      3) require_db_action && run_action "Drop database" action_drop_db || pause_continue ;;
      4) require_db_action && run_action "Connection strings" action_conn_info || pause_continue ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

submenu_users() {
  local c
  while true; do
    GO_HOME=0
    draw_submenu "Users" \
      "1" "List users & access" "isolation check" \
      "2" "Add user" "owner/read/write/admin" \
      "3" "Reset password" "any role" \
      "4" "Drop user" "destructive"
    ui_read_choice
    c="${UI_CHOICE:-}"
    handle_nav_input "$c" 0 && { [[ $GO_HOME -eq 1 ]] && return 0; continue; }

    case "$c" in
      1) run_action "Users & access" action_list_access ;;
      2) require_db_action && run_action "Add user" action_add_user || pause_continue ;;
      3) require_db_action && run_action "Reset password" action_reset_password || pause_continue ;;
      4) require_db_action && run_action "Drop user" action_drop_user || pause_continue ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

submenu_backups() {
  local c
  while true; do
    GO_HOME=0
    draw_submenu "Backups" \
      "1" "Backup one database" ".sql.gz" \
      "2" "Backup all" "all project DBs" \
      "3" "List backups" "full paths" \
      "4" "Restore backup" "guided"
    ui_read_choice
    c="${UI_CHOICE:-}"
    handle_nav_input "$c" 0 && { [[ $GO_HOME -eq 1 ]] && return 0; continue; }

    case "$c" in
      1) require_db_action && run_action "Backup" action_backup_one || pause_continue ;;
      2) require_db_action && run_action "Backup all" run backups backup.sh || pause_continue ;;
      3) run_action "Backup list" run backups list-backups.sh ;;
      4) require_db_action && run_action "Restore" action_restore || pause_continue ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

submenu_tools() {
  local c
  while true; do
    GO_HOME=0
    draw_submenu "Tools" \
      "1" "psql shell" "interactive SQL"
    ui_read_choice
    c="${UI_CHOICE:-}"
    handle_nav_input "$c" 0 && { [[ $GO_HOME -eq 1 ]] && return 0; continue; }

    case "$c" in
      1)
        require_db_action || { pause_continue; continue; }
        ui_clear
        ui_action_header "psql shell"
        action_psql
        return 0
        ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

action_connections() {
  if ui_pick_project_db "Filter by database (0 = cancel, skip = all):"; then
    run overview connections.sh "$UI_PICK_RESULT"
  else
    run overview connections.sh
  fi
}

action_tables() {
  ui_pick_project_db "Select database:" || { ui_cancelled; return 0; }
  run overview db-tables.sh "$UI_PICK_RESULT"
}

action_conn_info() {
  ui_pick_project_db "Select database:" || { ui_cancelled; return 0; }
  run databases conn-info.sh "$UI_PICK_RESULT"
}

action_list_access() {
  require_db_action || return 0
  mapfile -t DBS < <(list_project_dbs)
  if [[ ${#DBS[@]} -gt 0 ]] && ui_pick_list "Filter by database:" "All databases" "${DBS[@]}"; then
    if [[ "$UI_PICK_RESULT" == "All databases" ]]; then
      run users list-access.sh
    else
      run users list-access.sh "$UI_PICK_RESULT"
    fi
  else
    run users list-access.sh
  fi
}

action_create_db() {
  require_db_action || return 0
  ui_read_choice "Database name (e.g. myapp)"
  local DB="${UI_CHOICE:-}"
  [[ -n "$DB" ]] || { ui_cancelled; return 0; }
  valid_db_name "$DB" || { ui_err "Invalid name."; return 0; }
  run databases create-db.sh "$DB"
}

action_drop_db() {
  ui_pick_project_db "Select database to drop:" || { ui_cancelled; return 0; }
  run databases drop-db.sh "$UI_PICK_RESULT"
}

action_add_user() {
  require_db_action || return 0
  ui_pick_project_db "Select database:" || { ui_cancelled; return 0; }
  local db="$UI_PICK_RESULT"

  ui_pick_list "Select access level:" "owner" "read" "write" "admin" || { ui_cancelled; return 0; }
  local access="$UI_PICK_RESULT"

  ui_read_choice "Username"
  local user="${UI_CHOICE:-}"
  [[ -n "$user" ]] || { ui_cancelled; return 0; }
  valid_db_name "$user" || { ui_err "Invalid username."; return 0; }

  run users add-user.sh "$db" "$access" "$user"
}

action_reset_password() {
  ui_read_choice "Username"
  local user="${UI_CHOICE:-}"
  [[ -n "$user" ]] || { ui_cancelled; return 0; }
  valid_db_name "$user" || { ui_err "Invalid username."; return 0; }
  run users reset-password.sh "$user"
}

action_drop_user() {
  ui_read_choice "Username"
  local user="${UI_CHOICE:-}"
  [[ -n "$user" ]] || { ui_cancelled; return 0; }
  valid_db_name "$user" || { ui_err "Invalid username."; return 0; }
  run users drop-user.sh "$user"
}

action_backup_one() {
  require_db_action || return 0
  ui_pick_project_db "Select database to backup:" || { ui_cancelled; return 0; }
  run backups backup.sh "$UI_PICK_RESULT"
}

action_restore() {
  require_db_action || return 0
  run backups list-backups.sh || return 0

  echo ""
  ui_read_choice "Backup number (0 = cancel)"
  local choice="${UI_CHOICE:-}"
  [[ "$choice" == "0" || -z "$choice" ]] && { ui_cancelled; return 0; }

  local file
  file="$(run backups list-backups.sh --path "$choice" 2>/dev/null)" || { ui_err "Invalid choice."; return 0; }

  local suggested
  suggested="$(backup_db_from_filename "$file")"

  ui_read_choice "Target database [${suggested}]"
  local DB="${UI_CHOICE:-$suggested}"
  [[ -n "$DB" && "$DB" != "?" ]] || { ui_err "Invalid database name."; return 0; }
  valid_db_name "$DB" || { ui_err "Invalid database name."; return 0; }

  run backups restore.sh "$file" "$DB"
}

action_psql() {
  if ui_pick_project_db "Select database (0 = postgres):"; then
    run tools psql.sh "$UI_PICK_RESULT"
  else
    run tools psql.sh
  fi
}

main() {
  set_env
  ui_init

  while true; do
    GO_HOME=0
    draw_main_screen
    ui_read_choice
    local choice="${UI_CHOICE:-}"

    if handle_nav_input "$choice" 1; then
      continue
    fi

    case "$choice" in
      1) submenu_overview ;;
      2) submenu_databases ;;
      3) submenu_users ;;
      4) submenu_backups ;;
      5) submenu_tools ;;
      0) ui_ok "Bye."; exit 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
  done
}

main "$@"
