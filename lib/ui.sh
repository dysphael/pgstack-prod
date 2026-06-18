#!/usr/bin/env bash
# Terminal UI helpers (ANSI, no external deps).

UI_USE_COLOR=0
UI_BOLD="" UI_DIM="" UI_RESET=""
UI_CYAN="" UI_GREEN="" UI_YELLOW="" UI_RED="" UI_MAGENTA="" UI_BLUE=""

ui_init() {
  if [[ -n "${NO_COLOR:-}" ]] || [[ ! -t 1 ]]; then
    UI_USE_COLOR=0
    return 0
  fi
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
  ui_dim "  PostgreSQL Operations Console"
  echo ""
}

ui_badge() {
  local state="$1" text="$2"
  case "$state" in
    ok)   ui_c "$UI_GREEN"; printf '● %s' "$text" ;;
    warn) ui_c "$UI_YELLOW"; printf '● %s' "$text" ;;
    err)  ui_c "$UI_RED"; printf '● %s' "$text" ;;
    *)    ui_c "$UI_DIM"; printf '○ %s' "$text" ;;
  esac
  ui_c "$UI_RESET"
}

ui_box_open() {
  local title="$1" width="${2:-58}"
  local line pad
  line="$(printf '─%.0s' $(seq 1 "$width"))"
  pad=$((width - ${#title} - 3))
  (( pad < 0 )) && pad=0
  ui_c "$UI_CYAN"
  printf '┌─ %s %s┐\n' "$title" "$(printf '─%.0s' $(seq 1 "$pad"))"
  ui_c "$UI_RESET"
}

ui_box_line() {
  printf '│ %s\n' "$1"
}

ui_box_close() {
  local width="${1:-58}"
  ui_c "$UI_CYAN"
  printf '└%s┘\n' "$(printf '─%.0s' $(seq 1 "$((width + 1))"))"
  ui_c "$UI_RESET"
}

ui_box() {
  local title="$1"
  shift
  local width=58 line
  ui_box_open "$title" "$width"
  for line in "$@"; do
    ui_box_line "$line"
  done
  ui_box_close "$width"
}

ui_menu_item() {
  local num="$1" label="$2" hint="${3:-}"
  if [[ -n "$hint" ]]; then
    printf '  %2s) %-22s ' "$num" "$label"
    ui_dim "$hint"
  else
    printf '  %2s) %s\n' "$num" "$label"
  fi
}

ui_header_compact() {
  local host="${POSTGRES_HOST:-localhost}"
  local admin="${POSTGRES_USER:-?}"
  local status_badge

  if postgres_ready 2>/dev/null; then
    status_badge="$(ui_badge ok ONLINE)"
  elif postgres_server_up 2>/dev/null; then
    status_badge="$(ui_badge warn AUTH_FAIL)"
  else
    status_badge="$(ui_badge err OFFLINE)"
  fi

  ui_c "$UI_BOLD"
  printf ' pgstack'
  ui_c "$UI_RESET"
  printf ' │ %s │ %s │ ' "$host" "$admin"
  printf '%s\n' "$status_badge"
}

ui_breadcrumb() {
  local path="$1"
  ui_c "$UI_YELLOW"
  printf ' ▸ %s\n' "$path"
  ui_c "$UI_RESET"
}

ui_footer_hints() {
  ui_dim " [0] back/exit  [h] home  [?] help  [q] quit"
  echo ""
}

ui_help_screen() {
  ui_clear
  ui_title "Shortcuts"
  ui_box "Navigation" \
    "1-6 / 1-5  Select menu option" \
    "0          Back (submenu) or Exit (main)" \
    "h          Jump to main menu" \
    "?          This help screen" \
    "q          Quit"
  ui_box "Paths" \
    "Scripts    scripts/{overview,databases,users,backups,tools}/" \
    "Backups    BACKUP_DIR in .env" \
    "Logs       LOG_DIR in .env"
  echo ""
  ui_pause
}

ui_pause() {
  echo ""
  ui_dim " [Enter] continue  [h] home"
  read -r -p "> " _ui_pause_input
  case "${_ui_pause_input:-}" in
    h|H) return 2 ;;
  esac
  return 0
}

ui_read_choice() {
  local prompt="${1:-Choice}"
  ui_c "$UI_GREEN"
  read -r -p " ${prompt}: " UI_CHOICE
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
  ui_info "$prompt"
  for i in "${!items[@]}"; do
    ui_menu_item "$((i + 1))" "${items[$i]}"
  done
  ui_menu_item "0" "Cancel"
  echo ""
  ui_read_choice "Select"

  choice="${UI_CHOICE:-}"
  [[ "$choice" == "0" || -z "$choice" ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || { ui_err "Invalid choice."; return 1; }
  (( choice >= 1 && choice <= ${#items[@]} )) || { ui_err "Invalid choice."; return 1; }

  UI_PICK_RESULT="${items[$((choice - 1))]}"
  return 0
}

ui_action_header() {
  local title="$1"
  echo ""
  ui_title "── $title ──"
  echo ""
}

ui_invalid() {
  ui_warn "Invalid choice."
}

ui_cancelled() {
  ui_dim "Cancelled."
}
