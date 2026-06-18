#!/usr/bin/env bash
# Prepare folders and permissions before first deploy.
# Usage: ./scripts/setup.sh

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck disable=SC1091
[[ -f .env ]] && source .env

LOG_DIR="${LOG_DIR:-./logs/postgres}"
BACKUP_DIR="${BACKUP_DIR:-./backups}"
POSTGRES_UID=70
POSTGRES_GID=70

echo ""
echo "Setting up pgstack-prod..."
echo ""

mkdir -p "$LOG_DIR" "$BACKUP_DIR"
chmod +x scripts/*.sh 2>/dev/null || true

if [[ ! -f .env ]]; then
  echo "→ .env not found. Copying from .env.example..."
  cp .env.example .env
  echo "  Edit .env and set POSTGRES_PASSWORD and POSTGRES_HOST before deploying."
fi

if [[ "$(id -u)" -eq 0 ]]; then
  chown -R "${POSTGRES_UID}:${POSTGRES_GID}" "$LOG_DIR"
  echo "→ Log directory ready: ${LOG_DIR} (owner: postgres uid ${POSTGRES_UID})"
else
  if [[ -w "$LOG_DIR" ]]; then
    echo "→ Log directory ready: ${LOG_DIR}"
  else
    echo "→ Log directory created: ${LOG_DIR}"
    echo "  Run once as root: sudo chown -R ${POSTGRES_UID}:${POSTGRES_GID} ${LOG_DIR}"
  fi
fi

echo "→ Backup directory ready: ${BACKUP_DIR}"
echo ""
echo "Next steps:"
echo "  1. nano .env"
echo "  2. docker compose up -d"
echo "  3. docker compose ps"
echo ""
