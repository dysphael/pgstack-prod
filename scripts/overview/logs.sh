#!/usr/bin/env bash
# View PostgreSQL log files.
# Usage: ./scripts/overview/logs.sh
#        ./scripts/overview/logs.sh --tail [lines]
#        ./scripts/overview/logs.sh --list

set -euo pipefail
source "$(cd "$(dirname "$0")/../.." && pwd)/lib/init.sh"
set_env

LOG_DIR="$(abs_path "${LOG_DIR:-./logs/postgres}")"
mkdir -p "$LOG_DIR"

case "${1:-}" in
  --list|-l)
    echo "Log directory: ${LOG_DIR}"
    ls -lh "${LOG_DIR}"/postgresql-*.log 2>/dev/null || echo "No log files yet."
    ;;
  --tail|-t)
    LINES="${2:-50}"
    TODAY="${LOG_DIR}/postgresql-$(date +%Y-%m-%d).log"
    if [[ -f "$TODAY" ]]; then
      echo "=== ${TODAY} (last ${LINES} lines) ==="
      tail -n "$LINES" "$TODAY"
    else
      LATEST="$(ls -t "${LOG_DIR}"/postgresql-*.log 2>/dev/null | head -1)"
      if [[ -n "$LATEST" ]]; then
        echo "=== ${LATEST} (last ${LINES} lines) ==="
        tail -n "$LINES" "$LATEST"
      else
        echo "No log files in ${LOG_DIR} yet."
        exit 0
      fi
    fi
    ;;
  *)
    echo "Log directory: ${LOG_DIR}"
    echo ""
    "${0}" --list
    echo ""
    "${0}" --tail 30 || true
    ;;
esac
