#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

set_env() {
  cd "$ROOT"
  if [[ ! -f .env ]]; then
    echo "ERROR: .env not found. Run: cp .env.example .env" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  set -a && source .env && set +a
}

require_postgres() {
  if ! docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-postgres}" >/dev/null 2>&1; then
    echo "ERROR: PostgreSQL not ready. Run: docker compose up -d" >&2
    exit 1
  fi
}

valid_db_name() {
  [[ "${1:-}" =~ ^[a-z][a-z0-9_]*$ ]]
}

abs_path() {
  local path="${1:-.}"
  path="${path#./}"
  printf '%s/%s\n' "$ROOT" "$path"
}

postgres_ready() {
  docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-postgres}" >/dev/null 2>&1
}

list_project_dbs() {
  docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d postgres -Atc \
    "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres' ORDER BY datname;"
}

# Usage: pick_from_list "Prompt" item1 item2 ...
# Sets PICK_RESULT to the chosen item. Returns 1 on cancel.
pick_from_list() {
  local prompt="$1"
  shift
  local items=("$@")
  local i choice

  if [[ ${#items[@]} -eq 0 ]]; then
    echo "No options available." >&2
    return 1
  fi

  echo "$prompt"
  for i in "${!items[@]}"; do
    printf '  %d) %s\n' "$((i + 1))" "${items[$i]}"
  done
  printf '  0) Cancel\n'

  read -r -p "Choice: " choice
  [[ "$choice" == "0" || -z "$choice" ]] && return 1
  [[ "$choice" =~ ^[0-9]+$ ]] || { echo "Invalid choice." >&2; return 1; }
  (( choice >= 1 && choice <= ${#items[@]} )) || { echo "Invalid choice." >&2; return 1; }

  PICK_RESULT="${items[$((choice - 1))]}"
  return 0
}

# Prompt to pick a project database. Sets PICK_RESULT. Returns 1 on cancel.
pick_project_db() {
  local prompt="${1:-Select database:}"
  mapfile -t DBS < <(list_project_dbs)
  [[ ${#DBS[@]} -gt 0 ]] || { echo "No project databases found." >&2; return 1; }
  pick_from_list "$prompt" "${DBS[@]}"
}
