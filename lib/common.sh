#!/usr/bin/env bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Single root for all persistent files (postgres data, backups, logs).
# BACKUP_DIR and LOG_DIR are always under DATA_DIR — never set them separately in .env.
apply_data_paths() {
  DATA_DIR="${DATA_DIR:-./data}"
  BACKUP_DIR="${DATA_DIR}/backups"
  LOG_DIR="${DATA_DIR}/logs/postgres"
  export DATA_DIR BACKUP_DIR LOG_DIR
}

ensure_data_layout() {
  local d_backups d_logs d_pg
  d_pg="$(abs_path "${DATA_DIR}/postgres")"
  d_backups="$(abs_path "${BACKUP_DIR}")"
  d_logs="$(abs_path "${LOG_DIR}")"
  mkdir -p "$d_pg" "$d_backups" "$d_logs"
  migrate_legacy_data_paths "$d_backups" "$d_logs"
}

# Move old ./backups and ./logs/postgres into data/ if present.
migrate_legacy_data_paths() {
  local d_backups="$1" d_logs="$2"
  local f

  if [[ -d "$ROOT/backups" ]] && [[ "$ROOT/backups" != "$d_backups" ]]; then
    for f in "$ROOT/backups"/*; do
      [[ -e "$f" ]] || continue
      mv "$f" "$d_backups/" 2>/dev/null || true
    done
    rmdir "$ROOT/backups" 2>/dev/null || true
    echo "Moved legacy backups/ → ${BACKUP_DIR}/"
  fi

  if [[ -d "$ROOT/logs/postgres" ]] && [[ "$ROOT/logs/postgres" != "$d_logs" ]]; then
    for f in "$ROOT/logs/postgres"/*; do
      [[ -e "$f" ]] || continue
      mv "$f" "$d_logs/" 2>/dev/null || true
    done
    rm -rf "$ROOT/logs/postgres" 2>/dev/null || true
    echo "Moved legacy logs/postgres/ → ${LOG_DIR}/"
  fi

  if [[ -d "$ROOT/logs" ]] && [[ -z "$(ls -A "$ROOT/logs" 2>/dev/null)" ]]; then
    rmdir "$ROOT/logs" 2>/dev/null || true
  fi
}

set_env() {
  cd "$ROOT"
  if [[ ! -f .env ]]; then
    echo "ERROR: .env not found. Run: cp .env.example .env" >&2
    exit 1
  fi
  # shellcheck disable=SC1091
  set -a && source .env && set +a
  apply_data_paths
  ensure_data_layout
}

data_dir() {
  abs_path "${DATA_DIR:-./data}"
}

postgres_ready() {
  docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-postgres}" >/dev/null 2>&1 \
    && docker compose exec -T postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-postgres}" -c 'SELECT 1' >/dev/null 2>&1
}

postgres_server_up() {
  docker compose exec -T postgres pg_isready -U "postgres" -d "${POSTGRES_DB:-postgres}" >/dev/null 2>&1 \
    || docker compose exec -T postgres pg_isready >/dev/null 2>&1
}

auth_mismatch_hint() {
  echo "ERROR: PostgreSQL is running but user '${POSTGRES_USER}' cannot connect." >&2
  echo "POSTGRES_USER is created only on first boot (empty volume)." >&2
  echo "If you changed .env after the first start:" >&2
  echo "  - Put back the original POSTGRES_USER in .env, or" >&2
  echo "  - Reset data: docker compose down && docker volume rm \$(docker volume ls -q | grep pgdata)" >&2
  echo "    then docker compose up -d (destroys all databases)" >&2
  echo "  - Or remove data folder: docker compose down && rm -rf ./data/postgres" >&2
}

require_postgres() {
  if postgres_ready; then
    return 0
  fi
  if postgres_server_up; then
    auth_mismatch_hint
    exit 1
  fi
  echo "ERROR: PostgreSQL not ready. Run: docker compose up -d" >&2
  exit 1
}

valid_db_name() {
  [[ "${1:-}" =~ ^[a-z][a-z0-9_]*$ ]]
}

abs_path() {
  local path="${1:-.}"
  path="${path#./}"
  printf '%s/%s\n' "$ROOT" "$path"
}

# Host port from POSTGRES_PORT_PUBLISH (e.g. 5432:5432 or 127.0.0.1:5432:5432).
publish_host_port() {
  local spec="${POSTGRES_PORT_PUBLISH:-5432:5432}"
  if [[ "$spec" =~ ^[0-9]+:[0-9]+$ ]]; then
    printf '%s' "${spec%%:*}"
  elif [[ "$spec" =~ :[0-9]+:[0-9]+$ ]]; then
    printf '%s' "$(sed -E 's/.*:([0-9]+):[0-9]+$/\1/' <<<"$spec")"
  else
    printf '%s' "5432"
  fi
}

# Usage: read_array VAR_NAME command [args...]
# Fills a named array from command stdout (bash 3.2+ compatible).
read_array() {
  local __var="$1" __line
  shift
  local -a __items=()
  while IFS= read -r __line; do
    [[ -n "$__line" ]] && __items+=("$__line")
  done < <("$@")
  eval "$__var=(\"\${__items[@]}\")"
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
  local -a DBS=()
  read_array DBS list_project_dbs
  [[ ${#DBS[@]} -gt 0 ]] || { echo "No project databases found." >&2; return 1; }
  pick_from_list "$prompt" "${DBS[@]}"
}
