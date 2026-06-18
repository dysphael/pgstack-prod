#!/usr/bin/env bash
# Shared helpers for pgstack-prod scripts.

set_env() {
  ROOT="$(cd "$(dirname "${BASH_SOURCE[1]}")/.." && pwd)"
  cd "$ROOT"

  if [[ ! -f .env ]]; then
    echo ""
    echo "ERROR: .env file not found."
    echo "Fix:   cp .env.example .env && nano .env"
    echo ""
    exit 1
  fi

  # shellcheck disable=SC1091
  source .env
}

require_postgres() {
  if ! docker compose ps --status running --services postgres 2>/dev/null | grep -qx postgres; then
    echo ""
    echo "ERROR: PostgreSQL is not running."
    echo "Fix:   docker compose up -d && docker compose ps"
    echo ""
    exit 1
  fi

  if ! docker compose exec -T postgres pg_isready -U "${POSTGRES_USER}" -d "${POSTGRES_DB:-postgres}" >/dev/null 2>&1; then
    echo ""
    echo "ERROR: PostgreSQL is running but not ready yet."
    echo "Fix:   wait a few seconds, then try again."
    echo ""
    exit 1
  fi
}

valid_db_name() {
  local name="$1"
  [[ "$name" =~ ^[a-z][a-z0-9_]*$ ]]
}
