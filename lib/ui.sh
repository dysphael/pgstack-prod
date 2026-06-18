#!/usr/bin/env bash
# Terminal UI helpers (ANSI, no external deps).

UI_USE_COLOR=0
UI_WIDTH=72
UI_BOLD="" UI_DIM="" UI_RESET=""
UI_CYAN="" UI_GREEN="" UI_YELLOW="" UI_RED="" UI_MAGENTA="" UI_BLUE=""

ui_init() {
  if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    UI_USE_COLOR=0
  else
    UI_USE_COLOR=1
    UI_RESET=$'\033[0m'
    UI_BOLD=$'\033[1m'
    UI_DIM=$'\033[2m'
    UI_CYAN=$'\033[36m'
    UI_GREEN=$'\033[32m'
    UI_YELLOW=$'\033[33m'
    UI_RED=$'\033[31m'
    UI_MAGENTA=$'\033[35m'
    UI_BLUE=$'\033[34m'
  fi

  UI_WIDTH="${PGSTACK_UI_WIDTH:-72}"
  if [[ -t 1 ]]; then
    local cols="${COLUMNS:-}"
    if [[ -z "$cols" ]]; then
      cols="$(stty size 2>/dev/null | awk '{print $2}')"
    fi
    if [[ -n "$cols" && "$cols" -lt "$UI_WIDTH" ]]; then
      UI_WIDTH=$((cols - 2))
    fi
  fi
  if (( UI_WIDTH < 56 )); then
    UI_WIDTH=56
  fi
}

ui_c() {
  [[ "$UI_USE_COLOR" -eq 1 ]] && printf '%s' "$1" || true
}

ui_title()   { ui_c "$UI_BOLD$UI_CYAN"; printf '%s' "$*"; ui_c "$UI_RESET"; printf '\n'; }
ui_ok()      { ui_c "$UI_GREEN"; printf '%s' "$*"; ui_c "$UI_RESET"; printf '\n'; }
ui_err()     { ui_c "$UI_RED"; printf '%s' "$*"; ui_c "$UI_RESET"; printf '\n'; }
ui_warn()    { ui_c "$UI_YELLOW"; printf '%s' "$*"; ui_c "$UI_RESET"; printf '\n'; }
ui_info()    { ui_c "$UI_BLUE"; printf '%s' "$*"; ui_c "$UI_RESET"; printf '\n'; }
ui_dim()     { ui_c "$UI_DIM"; printf '%s' "$*"; ui_c "$UI_RESET"; printf '\n'; }
ui_accent()  { ui_c "$UI_MAGENTA"; printf '%s' "$*"; ui_c "$UI_RESET"; printf '\n'; }

ui_clear() {
  clear 2>/dev/null || printf '\033[2J\033[H'
}

ui_repeat() {
  local char="$1" count="$2"
  if (( count < 0 )); then
    count=0
  fi
  printf '%*s' "$count" '' | tr ' ' "$char"
}

ui_strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g' <<<"$1"
}

ui_truncate() {
  local text="$1" max="$2"
  local plain len
  plain="$(ui_strip_ansi "$text")"
  len=${#plain}
  if (( len <= max )); then
    printf '%s' "$text"
    return 0
  fi
  if (( max <= 3 )); then
    printf '%s' "${plain:0:max}"
    return 0
  fi
  printf '%s...' "${plain:0:$((max - 3))}"
}

ui_inner_width() {
  echo "$((UI_WIDTH - 2))"
}

ui_content_width() {
  echo "$((UI_WIDTH - 4))"
}

ui_box_open() {
  local title="$1"
  local inner title_len dash_count
  inner="$(ui_inner_width)"
  title_len=${#title}
  dash_count=$((UI_WIDTH - title_len - 6))
  if (( dash_count < 0 )); then
    dash_count=0
  fi
  ui_c "$UI_CYAN"
  printf '+-- %s %s+\n' "$title" "$(ui_repeat '-' "$dash_count")"
  ui_c "$UI_RESET"
}

ui_box_close() {
  local inner
  inner="$(ui_inner_width)"
  ui_c "$UI_CYAN"
  printf '+%s+\n' "$(ui_repeat '-' "$inner")"
  ui_c "$UI_RESET"
}

ui_box_line() {
  local text="$1"
  local cw
  cw="$(ui_content_width)"
  printf '| %-*s |\n' "$cw" "$(ui_truncate "$text" "$cw")"
}

ui_box_row() {
  local label="$1" value="$2"
  local label_w=14 value_w line
  value_w=$((UI_WIDTH - 4 - label_w - 1))
  line="$(printf '%-*s %s' "$label_w" "$label" "$(ui_truncate "$value" "$value_w")")"
  ui_box_line "$line"
}

ui_box() {
  local title="$1"
  shift
  local line
  ui_box_open "$title"
  for line in "$@"; do
    ui_box_line "$line"
  done
  ui_box_close
}

ui_rule() {
  local cw
  cw="$(ui_content_width)"
  ui_c "$UI_DIM"
  printf '  %s\n' "$(ui_repeat '-' "$cw")"
  ui_c "$UI_RESET"
}

ui_banner() {
  ui_c "$UI_CYAN"
  cat <<'EOF'
  ██████╗  ██████╗ ███████╗████████╗ █████╗  ██████╗██╗  ██╗
  ██╔══██╗██╔════╝ ██╔════╝╚══██╔══╝██╔══██╗██╔════╝██║ ██╔╝
  ██████╔╝██║  ███╗███████╗   ██║   ███████║██║     █████╔╝
  ██╔═══╝ ██║   ██║╚════██║   ██║   ██╔══██║██║     ██╔═██╗
  ██║     ╚██████╔╝███████║   ██║   ██║  ██║╚██████╗██║  ██╗
  ╚═╝      ╚═════╝ ╚══════╝   ╚═╝   ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
EOF
  ui_c "$UI_RESET"
  ui_box "PostgreSQL Operations Console" \
    "Interactive manager for databases, users, backups"
  echo ""
}

ui_status_text() {
  if postgres_ready 2>/dev/null; then
    printf '%s' "ONLINE"
  elif postgres_server_up 2>/dev/null; then
    printf '%s' "AUTH FAIL"
  else
    printf '%s' "OFFLINE"
  fi
}

ui_menu_item() {
  local num="$1" label="$2" hint="${3:-}"
  local cw label_w hint_w line
  cw="$(ui_content_width)"

  if [[ -n "$hint" ]]; then
    label_w=18
    hint_w=$((cw - 6 - label_w))
    line="$(printf '  %s) %-*s %s' "$num" "$label_w" "$label" "$(ui_truncate "$hint" "$hint_w")")"
  else
    line="$(printf '  %s) %s' "$num" "$label")"
  fi
  ui_box_line "$line"
}

ui_header_compact() {
  local host="${POSTGRES_HOST:-localhost}"
  local admin="${POSTGRES_USER:-?}"

  ui_box_open "pgstack"
  ui_box_row "Host" "$host"
  ui_box_row "Admin" "$admin"
  ui_box_row "Status" "$(ui_status_text)"
  ui_box_close
}

ui_breadcrumb() {
  local path="$1"
  ui_c "$UI_YELLOW"
  printf '  > %s\n' "$path"
  ui_c "$UI_RESET"
}

ui_footer_hints() {
  ui_dim "  Keys: 0 back/exit | h home | ? help | q quit"
}

ui_help_screen() {
  ui_clear
  ui_header_compact
  ui_breadcrumb "Help"
  echo ""
  ui_box "Navigation" \
    "1-6 / 1-5   select menu option" \
    "0           back or exit" \
    "h           jump to main menu" \
    "Enter       continue after action" \
    "?           this help screen" \
    "q           quit or home"
  echo ""
  ui_box "Paths" \
    "Scripts     scripts/{overview,databases,users,backups,tools}/" \
    "Backups     BACKUP_DIR in .env" \
    "Logs        LOG_DIR in .env"
  echo ""
  ui_pause
}

ui_pause() {
  echo ""
  ui_dim "  ---"
  ui_dim "  [Enter] return to menu   [h] main menu"
  read -r -p "  > " _ui_pause_input
  case "${_ui_pause_input:-}" in
    h|H) return 2 ;;
  esac
  return 0
}

ui_read_choice() {
  local prompt="${1:-Choice}"
  echo ""
  ui_c "$UI_GREEN"
  read -r -p "  ${prompt}: " UI_CHOICE
  ui_c "$UI_RESET"
}

# Sets UI_PICK_RESULT. Returns 1 on cancel.
ui_pick_list() {
  local prompt="$1"
  shift
  local items=("$@")
  local i choice

  if [[ ${#items[@]} -eq 0 ]]; then
    ui_err "No options available."
    return 1
  fi

  echo ""
  ui_box_open "Select"
  ui_box_line "$prompt"
  for i in "${!items[@]}"; do
    ui_menu_item "$((i + 1))" "${items[$i]}"
  done
  ui_menu_item "0" "Cancel"
  ui_box_close
  ui_read_choice "Number"

  choice="${UI_CHOICE:-}"
  if [[ "$choice" == "0" || -z "$choice" ]]; then
    return 1
  fi
  if [[ ! "$choice" =~ ^[0-9]+$ ]]; then
    ui_err "Invalid choice."
    return 1
  fi
  if (( choice < 1 || choice > ${#items[@]} )); then
    ui_err "Invalid choice."
    return 1
  fi

  UI_PICK_RESULT="${items[$((choice - 1))]}"
  return 0
}

ui_action_header() {
  local title="$1"
  ui_header_compact
  ui_breadcrumb "Action > ${title}"
  echo ""
  ui_rule
  ui_title "$title"
  ui_rule
  echo ""
}

ui_invalid() {
  ui_warn "Invalid choice. Type ? for help."
}

ui_cancelled() {
  ui_dim "Cancelled."
}
