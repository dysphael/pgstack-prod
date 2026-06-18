#!/usr/bin/env bash
# Interactive manager — terminal UI.
# Usage: ./bin/manager.sh

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
source "${ROOT}/lib/backups.sh"
source "${ROOT}/lib/db-users.sh"
source "${ROOT}/lib/app-lifecycle.sh"
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
  (
    PGSTACK_UI=1 PGSTACK_TABLE_WIDTH=$((UI_WIDTH - 4)) "$script" "${@:3}"
  ) || true
}

pause_continue() {
  local prc=0
  ui_pause || prc=$?
  if [[ $prc -eq 2 ]]; then
    GO_HOME=1
  fi
  return 0
}

run_action() {
  local title="$1"
  shift
  ui_clear
  ui_action_header "$title"
  "$@" || true
  pause_continue
  return 0
}

# require postgres, then run_action; pause once on auth/offline errors.
run_db_action() {
  local title="$1"
  shift
  if require_db_action; then
    run_action "$title" "$@"
  else
    pause_continue
  fi
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
  local -a DBS=()
  read_array DBS list_project_dbs
  [[ ${#DBS[@]} -gt 0 ]] || { ui_err "No project databases found."; return 1; }
  ui_pick_list "$prompt" "${DBS[@]}"
}

dashboard_live() {
  local db_count=0 db_list="" pg_ver="" pg_uptime=""
  local backup_count=0 latest_backup="none" backup_size="0"
  local docker_state backup_path log_path

  ui_box_open "System"

  if postgres_ready; then
    pg_ver="?"
    pg_uptime="?"
    read -r pg_ver pg_uptime < <(docker compose exec -T postgres psql -U "$POSTGRES_USER" -d postgres -Atc \
      "SELECT split_part(version(),' ',2), (now() - pg_postmaster_start_time())::text;" 2>/dev/null | tr '|' ' ') || true
    pg_ver="${pg_ver:-?}"
    pg_uptime="${pg_uptime%%.*}"
    pg_uptime="${pg_uptime:-?}"
    ui_box_row "PostgreSQL" "ONLINE"
    ui_box_row "Version" "PG ${pg_ver}"
    ui_box_row "Uptime" "${pg_uptime}"
  elif postgres_server_up; then
    ui_box_row "PostgreSQL" "AUTH FAIL"
    ui_box_row "Fix" "Check POSTGRES_USER in .env"
  else
    ui_box_row "PostgreSQL" "OFFLINE"
    ui_box_row "Start" "docker compose up -d"
  fi

  if postgres_ready; then
    local -a DBS=()
    read_array DBS list_project_dbs
    db_count=${#DBS[@]}
    if [[ $db_count -gt 0 ]]; then
      db_list="$(IFS=', '; echo "${DBS[*]}")"
    else
      db_list="none yet"
    fi
    ui_box_row "Databases" "${db_count} project: ${db_list}"
  else
    ui_box_row "Databases" "unavailable"
  fi

  collect_backups
  backup_count=${#BACKUP_FILES[@]}
  if [[ $backup_count -gt 0 ]]; then
    latest_backup="$(backup_mtime "${BACKUP_FILES[0]}")"
    backup_size="$(du -sh "$(backup_dir)" 2>/dev/null | cut -f1)"
    ui_box_row "Backups" "${backup_count} files (${backup_size})"
    ui_box_row "Latest" "${latest_backup}"
  else
    ui_box_row "Backups" "none"
  fi

  docker_state="not running"
  docker_state="$(docker compose ps postgres --format '{{.State}}' 2>/dev/null | head -1)" || docker_state="not running"
  docker_state="${docker_state:-not running}"
  ui_box_row "Docker" "postgres: ${docker_state}"

  backup_path="$(backup_dir | sed "s|$ROOT/||")"
  log_path="$(abs_path "${LOG_DIR:-./data/logs/postgres}" | sed "s|$ROOT/||")"
  local data_path
  data_path="$(data_dir 2>/dev/null | sed "s|$ROOT/||")" || data_path="data"
  ui_box_row "Data root" "${data_path}"
  ui_box_row "Backup dir" "${backup_path}"
  ui_box_row "Logs dir" "${log_path}"

  ui_box_close
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
  ui_box_open "Menu"
  ui_menu_item "1" "Overview" "status, stats, logs"
  ui_menu_item "2" "Databases" "create, list, drop"
  ui_menu_item "3" "Users" "roles, passwords"
  ui_menu_item "4" "Backups" "backup, restore"
  ui_menu_item "5" "Apps" "setup, backup, restore"
  ui_menu_item "6" "Tools" "psql shell"
  ui_menu_item "0" "Exit"
  ui_box_close
  ui_footer_hints
}

draw_submenu() {
  local section="$1"
  shift
  local -a items=("$@")
  local i

  ui_clear
  ui_header_compact
  ui_breadcrumb "Main > ${section}"
  echo ""
  ui_box_open "$section"
  for ((i = 0; i + 2 < ${#items[@]}; i += 3)); do
    ui_menu_item "${items[i]}" "${items[i + 1]}" "${items[i + 2]}"
  done
  ui_menu_item "0" "Back"
  ui_box_close
  ui_footer_hints
}

handle_nav_input() {
  local choice="$1" is_main="${2:-0}"
  case "$choice" in
    h|H) GO_HOME=1; return 0 ;;
    \?) ui_help_screen; return 0 ;;
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
      2) run_db_action "Database stats" run overview db-stats.sh ;;
      3) run_db_action "Connections" action_connections ;;
      4) run_db_action "Table sizes" action_tables ;;
      5) run_db_action "Slow queries" run overview slow-queries.sh ;;
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
      1) run_db_action "List databases" run databases list-dbs.sh ;;
      2) run_db_action "Create database" action_create_db ;;
      3) run_db_action "Drop database" action_drop_db ;;
      4) run_db_action "Connection strings" action_conn_info ;;
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
      2) run_db_action "Add user" action_add_user ;;
      3) run_db_action "Reset password" action_reset_password ;;
      4) run_db_action "Drop user" action_drop_user ;;
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
      1) run_db_action "Backup" action_backup_one ;;
      2) run_db_action "Backup all" run backups backup.sh ;;
      3) run_action "Backup list" run backups list-backups.sh ;;
      4) run_db_action "Restore" action_restore ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

manager_prompt_password() {
  local prompt="${1:-App password (from DATABASE_URL): }"
  read -r -s -p "$prompt" PGSTACK_PASSWORD
  echo
  export PGSTACK_PASSWORD
  [[ -n "$PGSTACK_PASSWORD" ]] || { ui_err "Password required."; return 1; }
}

ui_pick_registered_app() {
  local prompt="${1:-Select app:}"
  local -a APPS=()
  read_array APPS app_registry_list_dbs
  [[ ${#APPS[@]} -gt 0 ]] || { ui_err "No apps registered. Use Apps → Setup app."; return 1; }
  ui_pick_list "$prompt" "${APPS[@]}"
}

submenu_apps() {
  local c
  while true; do
    GO_HOME=0
    draw_submenu "Apps" \
      "1" "List apps" "registry + status" \
      "2" "Setup app" "DB + owner + verify" \
      "3" "Backup app" "sql.gz + manifest" \
      "4" "Restore app" "backup → app online" \
      "5" "Drop app" "optional backup first" \
      "6" "Verify app" "login + schema check"
    ui_read_choice
    c="${UI_CHOICE:-}"
    handle_nav_input "$c" 0 && { [[ $GO_HOME -eq 1 ]] && return 0; continue; }

    case "$c" in
      1) run_db_action "Apps" action_app_list ;;
      2) run_db_action "Setup app" action_app_setup ;;
      3) run_db_action "Backup app" action_app_backup ;;
      4) run_db_action "Restore app" action_app_restore ;;
      5) run_db_action "Drop app" action_app_drop ;;
      6) run_db_action "Verify app" action_app_verify ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

action_app_list() {
  app_registry_print_table
}

action_app_setup() {
  ui_read_choice "Database name (e.g. myapp)"
  local db="${UI_CHOICE:-}"
  [[ -n "$db" ]] || { ui_cancelled; return 0; }
  valid_db_name "$db" || { ui_err "Invalid database name."; return 0; }

  ui_read_choice "App user (e.g. myapp_api)"
  local user="${UI_CHOICE:-}"
  [[ -n "$user" ]] || { ui_cancelled; return 0; }
  valid_db_name "$user" || { ui_err "Invalid username."; return 0; }

  ui_read_choice "Label (optional, e.g. My App)"
  local label="${UI_CHOICE:-}"

  manager_prompt_password || return 0
  app_setup "$db" "$user" "$PGSTACK_PASSWORD" "$label" || true
}

action_app_backup() {
  if ui_pick_registered_app "Select app to backup:"; then
    app_backup "$UI_PICK_RESULT" >/dev/null || true
  else
    ui_pick_project_db "Or select database:" || { ui_cancelled; return 0; }
    app_backup "$UI_PICK_RESULT" >/dev/null || true
  fi
}

action_app_restore() {
  local db file choice i

  if ui_pick_registered_app "Select app to restore:"; then
    db="$UI_PICK_RESULT"
  else
    ui_pick_project_db "Select target database:" || { ui_cancelled; return 0; }
    db="$UI_PICK_RESULT"
  fi

  collect_backups_for_db "$db"
  if [[ ${#BACKUP_FILES[@]} -eq 0 ]]; then
    ui_err "No backups found for '${db}'."
    ui_dim "Run Apps → Backup app first."
    return 0
  fi

  echo ""
  printf '%-3s %-20s %-6s %s\n' "#" "Date" "Size" "File"
  for i in "${!BACKUP_FILES[@]}"; do
    file="${BACKUP_FILES[$i]}"
    printf '%-3s %-20s %-6s %s\n' "$((i + 1))" "$(backup_mtime "$file")" "$(du -h "$file" | cut -f1)" "${file##*/}"
  done
  echo ""
  ui_read_choice "Backup number (0 = cancel)"
  choice="${UI_CHOICE:-}"
  [[ "$choice" == "0" || -z "$choice" ]] && { ui_cancelled; return 0; }
  [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#BACKUP_FILES[@]} )) || { ui_err "Invalid choice."; return 0; }
  file="${BACKUP_FILES[$((choice - 1))]}"

  manager_prompt_password || return 0
  echo ""
  ui_warn "This replaces all data in '${db}'."
  read -r -p "Type YES to continue: " OK
  [[ "$OK" == "YES" ]] || { ui_cancelled; return 0; }

  local user
  user="$(app_registry_get "$db" user)"
  app_restore "$file" "$db" "$user" "$PGSTACK_PASSWORD" || true
}

action_app_drop() {
  local db backup_first=1 answer

  if ui_pick_registered_app "Select app to drop:"; then
    db="$UI_PICK_RESULT"
  else
    ui_pick_project_db "Select database:" || { ui_cancelled; return 0; }
    db="$UI_PICK_RESULT"
  fi

  ui_read_choice "Backup before drop? (Y/n)"
  answer="${UI_CHOICE:-Y}"
  [[ "$answer" =~ ^[nN] ]] && backup_first=0

  ui_warn "Drop '${db}' — all data will be deleted."
  read -r -p "Type YES to continue: " OK
  [[ "$OK" == "YES" ]] || { ui_cancelled; return 0; }

  app_drop "$db" "$backup_first" || true
}

action_app_verify() {
  local db user

  if ui_pick_registered_app "Select app to verify:"; then
    db="$UI_PICK_RESULT"
  else
    ui_pick_project_db "Select database:" || { ui_cancelled; return 0; }
    db="$UI_PICK_RESULT"
  fi

  user="$(app_registry_get "$db" user)"
  if [[ -z "$user" ]]; then
    ui_read_choice "App user"
    user="${UI_CHOICE:-}"
    [[ -n "$user" ]] || { ui_cancelled; return 0; }
  fi

  manager_prompt_password || return 0
  app_verify "$db" "$user" "$PGSTACK_PASSWORD" || true
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
        ui_info "Entering interactive psql. Type \\q to return to menu."
        echo ""
        action_psql || true
        pause_continue
        [[ $GO_HOME -eq 1 ]] && return 0
        continue
        ;;
      0) return 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
    [[ $GO_HOME -eq 1 ]] && return 0
  done
}

action_connections() {
  if ui_pick_project_db "Filter by database (0 = cancel, skip = all):"; then
    run overview connections.sh "$UI_PICK_RESULT" || true
  else
    run overview connections.sh || true
  fi
}

action_tables() {
  ui_pick_project_db "Select database:" || { ui_cancelled; return 0; }
  run overview db-tables.sh "$UI_PICK_RESULT" || true
}

action_conn_info() {
  ui_pick_project_db "Select database:" || { ui_cancelled; return 0; }
  run databases conn-info.sh "$UI_PICK_RESULT" || true
}

action_list_access() {
  require_db_action || return 0
  local -a DBS=()
  read_array DBS list_project_dbs
  if [[ ${#DBS[@]} -gt 0 ]] && ui_pick_list "Filter by database:" "All databases" "${DBS[@]}"; then
    if [[ "$UI_PICK_RESULT" == "All databases" ]]; then
      run users list-access.sh || true
    else
      run users list-access.sh "$UI_PICK_RESULT" || true
    fi
  else
    run users list-access.sh || true
  fi
}

action_create_db() {
  require_db_action || return 0
  ui_info "Tip: for apps (Django, etc.) use Apps → Setup app instead."
  echo ""
  ui_read_choice "Database name (e.g. myapp)"
  local DB="${UI_CHOICE:-}"
  [[ -n "$DB" ]] || { ui_cancelled; return 0; }
  valid_db_name "$DB" || { ui_err "Invalid name."; return 0; }
  run databases create-db.sh "$DB" || true
}

action_drop_db() {
  ui_pick_project_db "Select database to drop:" || { ui_cancelled; return 0; }
  run databases drop-db.sh "$UI_PICK_RESULT" || true
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

  run users add-user.sh "$db" "$access" "$user" || true
}

action_reset_password() {
  ui_read_choice "Username"
  local user="${UI_CHOICE:-}"
  [[ -n "$user" ]] || { ui_cancelled; return 0; }
  valid_db_name "$user" || { ui_err "Invalid username."; return 0; }
  ui_pick_list "Method:" "From DATABASE_URL (exact)" "Interactive prompt"
  if [[ "$UI_PICK_RESULT" == "From DATABASE_URL (exact)" ]]; then
    manager_prompt_password "DATABASE_URL password: " || return 0
    PGSTACK_PASSWORD="$PGSTACK_PASSWORD" run users set-password.sh "$user" || true
  else
    run users reset-password.sh "$user" || true
  fi
}

action_drop_user() {
  ui_read_choice "Username"
  local user="${UI_CHOICE:-}"
  [[ -n "$user" ]] || { ui_cancelled; return 0; }
  valid_db_name "$user" || { ui_err "Invalid username."; return 0; }
  run users drop-user.sh "$user" || true
}

action_backup_one() {
  require_db_action || return 0
  ui_pick_project_db "Select database to backup:" || { ui_cancelled; return 0; }
  run backups backup.sh "$UI_PICK_RESULT" || true
}

action_restore() {
  require_db_action || return 0
  run backups list-backups.sh || return 0

  echo ""
  ui_read_choice "Backup number (0 = cancel)"
  local choice="${UI_CHOICE:-}"
  [[ "$choice" == "0" || -z "$choice" ]] && { ui_cancelled; return 0; }

  local file
  file="$(backup_path_at "$choice" 2>/dev/null)" || { ui_err "Invalid choice."; return 0; }

  local suggested db user
  suggested="$(backup_db_from_filename "$file")"

  ui_read_choice "Target database [${suggested}]"
  DB="${UI_CHOICE:-$suggested}"
  [[ -n "$DB" && "$DB" != "?" ]] || { ui_err "Invalid database name."; return 0; }
  valid_db_name "$DB" || { ui_err "Invalid database name."; return 0; }

  user="$(app_registry_get "$DB" user)"
  manager_prompt_password || return 0
  echo ""
  ui_warn "Restore replaces data in '${DB}'."
  read -r -p "Type YES to continue: " OK
  [[ "$OK" == "YES" ]] || { ui_cancelled; return 0; }

  app_restore "$file" "$DB" "$user" "$PGSTACK_PASSWORD" || true
}

action_psql() {
  if ui_pick_project_db "Select database (0 = postgres):"; then
    run tools psql.sh "$UI_PICK_RESULT" || true
  else
    run tools psql.sh || true
  fi
}

main() {
  set_env
  ui_init

  trap 'echo ""; ui_warn "Interrupted — returning to menu."; echo ""' INT

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
      5) submenu_apps ;;
      6) submenu_tools ;;
      0) ui_ok "Bye."; exit 0 ;;
      *) ui_invalid; pause_continue ;;
    esac
  done
}

main "$@"
